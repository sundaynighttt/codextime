import SwiftUI
import UIKit

struct ContentView: View {
    let model: AppModel
    @StateObject private var webUsage = WebUsageCoordinator()
    @State private var grok = GrokAppModel()
    @State private var claude = ClaudeNativeAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasLoaded = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copiedUserCode: String?
    @State private var presentedSheet: SheetDestination?

    private enum SheetDestination: String, Identifiable {
        case guide, nativeGrok, nativeClaude, grok, claude
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
              VStack(spacing: 24) {
                Spacer(minLength: 32)

                Text("CodexTime")
                    .font(.title2.bold())

                usageCard

                webProviderControls
                    .frame(maxWidth: 380)

                content
                    .frame(maxWidth: 380)

                Button("이용 안내 · 개인정보 · 지원") {
                    presentedSheet = .guide
                }
                .font(.footnote)
                .accessibilityIdentifier("open-guide")

                Spacer()
            }
            .padding(24)
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .guide: UsageGuideView()
            case .nativeGrok: GrokConnectionView(model: grok, manualWebModel: webUsage.model(for: .grok))
            case .nativeClaude: ClaudeNativeConnectionView(model: claude, manualWebModel: webUsage.model(for: .claude))
            case .grok: ProviderWebUsageView(model: webUsage.model(for: .grok))
            case .claude: ProviderWebUsageView(model: webUsage.model(for: .claude))
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active,
                  ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
            if !hasLoaded {
                hasLoaded = true
                async let codexLoad: Void = model.load()
                async let grokLoad: Void = grok.load()
                async let claudeLoad: Void = claude.load()
                _ = await (codexLoad, grokLoad, claudeLoad)
            } else {
                async let grokLoad: Void = grok.load()
                async let codexRefresh: Void = refreshCodexIfNeeded(force: false)
                async let claudeLoad: Void = claude.load()
                _ = await (grokLoad, codexRefresh, claudeLoad)
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) }
                catch { return }
                guard scenePhase == .active else { return }
                await refreshConnectedProviders(force: false)
            }
        }
        .onChange(of: currentSnapshot?.isDemo == true) { _, _ in
            Task {
                async let grokDemo: Void = grok.synchronizeDemoState()
                async let claudeDemo: Void = claude.synchronizeDemoState()
                _ = await (grokDemo, claudeDemo)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            ProgressView("확인 중…")
                .controlSize(.large)

        case .signedOut:
            VStack(spacing: 20) {
                Text("ChatGPT를 연결하면 Codex 잔여량이 표시됩니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("ChatGPT로 연결") {
                    model.beginSignIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("connect-chatgpt")

                Button("예시 데이터로 둘러보기") { model.beginDemo() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("start-demo")

                Text("Codex 사용량은 ChatGPT 연결 후 조회합니다.\n각 서비스가 제공하는 공식 앱이 아닙니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case let .signingIn(authorization):
            signInView(authorization)

        case let .connected(snapshot):
            connectedView(snapshot)

        case let .failed(message):
            VStack(spacing: 18) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("다시 확인") {
                    Task { await model.load() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retry-load")
            }
        }
    }

    private func signInView(_ authorization: DeviceAuthorization) -> some View {
        VStack(spacing: 18) {
            Text("ChatGPT에서 아래 코드를 입력하세요")
                .font(.headline)

            Button {
                copyUserCode(authorization.userCode)
            } label: {
                Text(authorization.userCode)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("로그인 코드 \(authorization.userCode), 탭하여 복사")
            .accessibilityIdentifier("device-code")

            Button {
                copyUserCode(authorization.userCode)
            } label: {
                Label(
                    copiedUserCode == authorization.userCode ? "복사됨" : "코드 복사",
                    systemImage: copiedUserCode == authorization.userCode ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("copy-device-code")

            Button("ChatGPT 열기") {
                copyUserCode(authorization.userCode)
                openURL(authorization.verificationURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("open-chatgpt")

            HStack(spacing: 8) {
                ProgressView()
                Text("로그인 완료를 기다리는 중")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("취소", role: .cancel) {
                model.cancelSignIn()
            }
            .accessibilityIdentifier("cancel-signin")
        }
    }

    private func copyUserCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedUserCode = code

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard copiedUserCode == code else { return }
            copiedUserCode = nil
        }
    }

    private var currentSnapshot: UsageSnapshot? {
        guard case let .connected(snapshot) = model.state else { return nil }
        return snapshot
    }

    private var cardUpdateText: String {
        if let snapshot = currentSnapshot {
            return "Codex 업데이트 " + UsageFormatter.updateTime(snapshot.updatedAt)
        }
        if let snapshot = grok.snapshot {
            return "Grok 업데이트 " + UsageFormatter.updateTime(snapshot.updatedAt)
        }
        if let snapshot = claude.snapshot {
            return "Claude 업데이트 " + UsageFormatter.updateTime(snapshot.updatedAt)
        }
        return "서비스별로 계정을 연결하세요"
    }

    private func refreshConnectedProviders(force: Bool) async {
        async let codexRefresh: Void = refreshCodexIfNeeded(force: force)
        async let grokRefresh: Void = refreshGrokIfNeeded(force: force)
        async let claudeRefresh: Void = refreshClaudeIfNeeded(force: force)
        _ = await (codexRefresh, grokRefresh, claudeRefresh)
    }

    private func refreshCodexIfNeeded(force: Bool) async {
        guard case let .connected(snapshot) = model.state else { return }
        guard force || (snapshot.isDemo != true && Date().timeIntervalSince(snapshot.updatedAt) >= 600) else { return }
        await model.refresh()
    }

    private func refreshGrokIfNeeded(force: Bool) async {
        if force { await grok.refresh() }
        else { await grok.refreshIfNeeded() }
    }

    private func refreshClaudeIfNeeded(force: Bool) async {
        if force { await claude.refresh() }
        else { await claude.refreshIfNeeded() }
    }

    private var usageCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.secondarySystemGroupedBackground))
            .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 0.6 : 1, contentMode: .fit)
            .overlay {
              VStack(spacing: 16) {
            HStack {
                Text(currentSnapshot?.isDemo == true ? "예시 데이터" : "잔여 사용량")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if currentSnapshot != nil || grok.snapshot != nil || grok.isConnected || claude.snapshot != nil || claude.isConnected {
                    Button {
                        Task { await refreshConnectedProviders(force: true) }
                    } label: {
                        if model.isRefreshing || grok.isRefreshing || claude.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .disabled(model.isRefreshing || grok.isRefreshing || claude.isRefreshing)
                    .accessibilityLabel("Codex·Grok·Claude 사용량 새로고침")
                    .accessibilityIdentifier("refresh-usage")
                }
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ProviderUsageColumns(snapshot: currentSnapshot, now: context.date,
                                     webReadings: webUsage.readings,
                                     webMetricReadings: webUsage.metricReadings,
                                     grokSnapshot: grok.snapshot,
                                     grokRequiresSignIn: grok.requiresSignIn,
                                     claudeSnapshot: claude.snapshot,
                                     claudeRequiresSignIn: claude.requiresSignIn)
            }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Spacer(minLength: 0)
            Text(cardUpdateText)
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(20)
            }
        .frame(maxWidth: 280)
        .accessibilityIdentifier("provider-usage-card")
    }

    private var webProviderControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    presentedSheet = .nativeGrok
                } label: {
                    Text(grok.requiresSignIn ? "Grok 재연결" : grok.isConnected ? "Grok 계정" : "Grok 연결")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentSnapshot?.isDemo == true)
                .accessibilityIdentifier("connect-grok")
                Button {
                    presentedSheet = .nativeClaude
                } label: {
                    Text(claude.requiresSignIn ? "Claude 재연결" : claude.isConnected ? "Claude 계정" : "Claude 연결")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentSnapshot?.isDemo == true)
                .accessibilityIdentifier("connect-claude")
            }
            Text(currentSnapshot?.isDemo == true
                 ? "예시를 끝내면 Grok·Claude 계정을 연결할 수 있습니다. 예시 모드에서는 웹 로그인이나 실제 사용량 확인을 시작하지 않습니다."
                 : "Grok은 연결 후 자동 조회합니다. Claude는 iPhone 단독 호환 연결을 시도할 수 있으며, 지원되지 않으면 웹에서 직접 확인합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if currentSnapshot?.isDemo != true, let message = grok.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("grok-usage-message")
            }
            if currentSnapshot?.isDemo != true, let message = claude.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-usage-message")
            }
            if currentSnapshot?.isDemo != true && !webUsage.readings.isEmpty {
                DisclosureGroup("웹 사용량 관리") {
                    ForEach(WebUsageProvider.allCases) { provider in
                        if webUsage.readings[provider] != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(WebUsageMetric.allCases.filter { $0.provider == provider }) { metric in
                                    if let limit = webUsage.metricReadings[metric] {
                                        Text("\(provider.name) · \(metric.name) · 사용 \(WebUsageReading.percentText(limit.usedPercent)) / 잔여 \(WebUsageReading.percentText(limit.remainingPercent)) · 확인 \(limit.confirmationTimeText(at: Date()))")
                                            .font(.footnote)
                                    }
                                }
                                Button(provider.name + " 연결 해제·기록 삭제", role: .destructive) {
                                    webUsage.disconnect(provider)
                                }
                                .font(.footnote)
                                .accessibilityIdentifier("disconnect-" + provider.rawValue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                }
                .font(.footnote)
            }
        }
    }

    private func connectedView(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 18) {
            if snapshot.isDemo == true {
                Text("예시 데이터 · 실제 계정 사용량이 아닙니다")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            DisclosureGroup("Codex 상세") {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("리셋까지 " + UsageFormatter.remainingTime(until: snapshot.resetAt, now: context.date))
                        if let tokens = snapshot.lifetimeTokens {
                            Text("누적 토큰 " + UsageFormatter.compactTokenCount(tokens))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 280)

            Button(snapshot.isDemo == true ? "예시 끝내기" : "연결 해제", role: .destructive) {
                Task { await model.signOut() }
            }
            .font(.footnote)
            .accessibilityIdentifier("disconnect-chatgpt")
        }
    }

}

#Preview("연결 전") {
    ContentView(model: AppModel())
}
