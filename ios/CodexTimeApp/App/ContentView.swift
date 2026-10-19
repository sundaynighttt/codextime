import SwiftUI
import UIKit
import UsageSync
import WidgetKit

struct ContentView: View {
    let model: AppModel
    @ObservedObject private var cloudSync: UsageCloudSync
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLoad = false

    init(model: AppModel) {
        self.model = model
        _cloudSync = ObservedObject(wrappedValue: model.cloudSync)
    }
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copiedUserCode: String?
    @State private var presentedSheet: SheetDestination?

    private enum SheetDestination: String, Identifiable {
        case guide
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

                CloudSyncSettingsView(cloudSync: cloudSync, isDemoMode: model.isDemoEnabled)
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
        .sheet(item: $presentedSheet) { _ in UsageGuideView() }
        .task {
            async let codex: Void = model.load()
            async let cloud: Void = refreshCloud()
            _ = await (codex, cloud)
            didLoad = true
        }
        .onChange(of: model.isDemoEnabled) { _, isDemoEnabled in
            guard !isDemoEnabled else { return }
            Task { await refreshCloud() }
        }
        .onChange(of: cloudSync.isEnabled) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: scenePhase) { _, phase in
            guard didLoad, phase == .active else { return }
            Task { await refreshCloud() }
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

                Text("실제 사용량은 ChatGPT 연결 후 조회합니다.\nOpenAI가 제공하는 공식 앱이 아닙니다.")
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
                if currentSnapshot != nil {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .disabled(model.isRefreshing)
                    .accessibilityLabel("Codex 사용량 새로고침")
                    .accessibilityIdentifier("refresh-usage")
                }
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ProviderUsageColumns(
                    snapshot: currentSnapshot, now: context.date,
                    cloudReadings: cloudSync.readings, cloudEnabled: cloudSync.isEnabled,
                    cloudHadError: cloudSync.state.hasCloudReadError
                )
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            Spacer(minLength: 0)
            Text(currentSnapshot.map { "업데이트 " + UsageFormatter.updateTime($0.updatedAt) } ?? "계정을 연결해 주세요")
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(20)
            }
        .frame(maxWidth: 280)
        .accessibilityIdentifier("provider-usage-card")
    }

    private func refreshCloud() async {
        await model.refreshCloudIfAllowed()
        WidgetCenter.shared.reloadAllTimelines()
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

            Button(snapshot.isDemo == true ? "예시 끝내기" : "ChatGPT 연결 해제", role: .destructive) {
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
