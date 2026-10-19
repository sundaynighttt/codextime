#!/usr/bin/env python3
"""Render the production AppKit views without starting account/network clients."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
output = root / "docs/screenshots"
with tempfile.TemporaryDirectory(prefix="codextime-docs-macos-") as temp:
    package = Path(temp)
    source = package / "Sources/DocsPreview"
    shutil.copytree(root / "macos/Sources/CodexUsageMonitor", source)
    (source / "CodexUsageMonitorApp.swift").unlink()
    shutil.copy2(output / "render-macos.swift", source / "DocumentationPreview.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DocsPreview", platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "DocsPreview", resources: [.process("Resources")])],
    swiftLanguageModes: [.v5])
''')
    subprocess.run(["swift", "run", "--package-path", str(package),
                    "DocsPreview", str(output)], check=True)
