#!/usr/bin/env python3
"""Render the pinned widget candidate with isolated, offline synthetic data."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
output = root / "docs/screenshots"
bundle_id = "com.sundaynighttt.codextime.docs-preview"
# Keep production presentation code fixed to the public build-17 candidate.
source_ref = "5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0"
image_name = "ios-widget-v1.0-b17.png"
devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
runtime = os.environ.get("DOCS_IOS_RUNTIME")
candidates = [d for key, group in devices.items() if not runtime or key == runtime for d in group
              if "iPhone" in d["name"] and d.get("isAvailable")]
if not candidates:
    raise RuntimeError("No available iPhone Simulator matches DOCS_IOS_RUNTIME")
requested_simulator = os.environ.get("DOCS_IOS_SIMULATOR")
if requested_simulator:
    device = next((d for d in candidates if d["udid"] == requested_simulator), None)
    if device is None:
        raise RuntimeError("DOCS_IOS_SIMULATOR is not an available iPhone Simulator")
else:
    device = next((d for d in candidates if d["state"] == "Booted"), candidates[0])
simulator = device["udid"]
booted_here = device["state"] != "Booted"
if booted_here:
    subprocess.run(["xcrun", "simctl", "boot", simulator], check=True)
try:
    with tempfile.TemporaryDirectory(prefix="codextime-docs-ios-") as temp:
        project = Path(temp)
        source = project / "Sources"
        files = subprocess.check_output(
            ["git", "-C", str(root), "ls-tree", "-r", "--name-only", source_ref, "ios/Shared"],
            text=True).splitlines()
        # Copy only presentation/data-model sources and assets. The preview target
        # contains no account client, token store, usage cache, auth lock, or entitlements.
        presentation_files = {
            "AuthModels.swift", "GrokAuthModels.swift", "ClaudeNativeAuthModels.swift",
            "UsageModels.swift", "ProviderUsageCard.swift", "WebProviderUsage.swift",
            "RefreshUsageIntent.swift", "PrivacyInfo.xcprivacy", "ThirdPartyNotices.txt",
        }
        for name in files:
            relative = Path(name).relative_to("ios/Shared")
            if relative.name not in presentation_files and relative.parts[0] != "ProviderAssets.xcassets":
                continue
            target = source / Path(name).relative_to("ios")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(subprocess.check_output(
                ["git", "-C", str(root), "show", source_ref + ":" + name]))
        widget = subprocess.check_output(
            ["git", "-C", str(root), "show",
             source_ref + ":ios/CodexTimeWidget/CodexTimeWidget.swift"], text=True)
        # Keep the production view and entry verbatim; omit the extension's @main
        # and network timeline provider from this separate offline preview host.
        entry = widget[widget.index("struct UsageEntry:"):widget.index("struct UsageTimelineProvider:")]
        view = widget[widget.index("struct CodexTimeWidgetView:"):widget.index("#Preview")]
        (source / "WidgetView.swift").write_text("import SwiftUI\nimport WidgetKit\n" + entry + view)
        (source / "DocsPreview.swift").write_text('''import SwiftUI
import UIKit
import WidgetKit

@main
struct DocsPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await exportWidget() }
        }
    }

    @MainActor
    private func exportWidget() async {
        let now = Date(timeIntervalSince1970: 1_792_373_040)
        // These are documentation fixtures, never account responses or product demo data.
        // A non-demo entry makes the unchanged production view show its direct-query labels.
        let codex = UsageSnapshot(remainingPercent: 73,
            resetAt: now.addingTimeInterval(3 * 86_400 + 17 * 3_600),
            updatedAt: now, lifetimeTokens: nil, isDemo: false)
        let grok = GrokUsageSnapshot(usedPercent: 18, period: .monthly,
            resetAt: now.addingTimeInterval(7 * 86_400), updatedAt: now)
        let claude = ClaudeNativeUsageSnapshot(
            fiveHour: ClaudeNativeUsageWindow(usedPercent: 10, resetAt: now.addingTimeInterval(2 * 3_600)),
            sevenDay: ClaudeNativeUsageWindow(usedPercent: 25, resetAt: now.addingTimeInterval(3 * 86_400)),
            updatedAt: now)
        let widget = CodexTimeWidgetView(entry: UsageEntry(date: now, snapshot: codex,
            grokSnapshot: grok, claudeSnapshot: claude))
            .environment(\\.locale, Locale(identifier: "ko_KR"))
            .environment(\\.colorScheme, .light)
            .padding(16)
            .frame(width: 170, height: 170)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        let preview = VStack(spacing: 5) {
            widget
            Text("합성 UI 예시 · 실제 계정 검증 아님")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 7)
        .background(Color.white)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 3
        let data = renderer.uiImage!.pngData()!
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try! data.write(to: folder.appendingPathComponent("ios-widget-v1.0-b17.png"))
    }
}
''')
        (project / "project.yml").write_text('''name: DocsPreview
options:
  deploymentTarget:
    iOS: "17.0"
targets:
  DocsPreview:
    type: application
    platform: iOS
    sources: [Sources]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sundaynighttt.codextime.docs-preview
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_VERSION: "5.0"
''')
        subprocess.run(["xcodegen", "generate", "--spec", str(project / "project.yml")], check=True)
        build = project / "DerivedData"
        subprocess.run(["xcodebuild", "-project", str(project / "DocsPreview.xcodeproj"),
                        "-scheme", "DocsPreview", "-destination", "platform=iOS Simulator,id=" + simulator,
                        "-derivedDataPath", str(build), "CODE_SIGNING_ALLOWED=NO",
                        "ASSETCATALOG_COMPILER_APPICON_NAME=", "build"], check=True)
        try:
            subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"],
                           check=True, timeout=30)
        except subprocess.TimeoutExpired:
            # CoreLocation migration may outlive usable launch services on CI.
            # Actual install/launch below confirms the preview can run.
            print("Background migration continues; checking app install/launch.", flush=True)
        app = build / "Build/Products/Debug-iphonesimulator/DocsPreview.app"
        subprocess.run(["xcrun", "simctl", "install", simulator, str(app)], check=True)
        preview_env = {**os.environ, "SIMCTL_CHILD_TZ": "Asia/Seoul"}
        subprocess.run(["xcrun", "simctl", "launch", simulator, bundle_id],
                       env=preview_env, check=True)
        container = Path(subprocess.check_output(
            ["xcrun", "simctl", "get_app_container", simulator, bundle_id, "data"], text=True).strip())
        image = container / "Documents" / image_name
        for _ in range(60):
            if image.exists() and image.stat().st_size > 0:
                shutil.copy2(image, output / image.name)
                print("Exported pinned production iOS widget view with offline synthetic data:", output / image.name)
                break
            time.sleep(1)
        else:
            raise RuntimeError("Preview host did not export the widget image within 60 seconds")
finally:
    subprocess.run(["xcrun", "simctl", "uninstall", simulator, bundle_id], check=False)
    if booted_here:
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], check=False)
