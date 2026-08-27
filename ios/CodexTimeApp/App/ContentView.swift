import SwiftUI
import UIKit

struct ContentView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var copiedUserCode: String?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 32)

                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("CodexTime")
                    .font(.largeTitle.bold())

                content
                    .frame(maxWidth: 380)

                Spacer()
            }
            .padding(24)
        }
        .task {
            await model.load()
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
                Text("남은 Codex 사용량과 리셋 시간을\n위젯에서 바로 확인합니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("ChatGPT로 연결") {
                    model.beginSignIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("connect-chatgpt")
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

    private func connectedView(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Codex")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("\(snapshot.remainingPercent)%")
                        .font(.system(size: 54, weight: .bold, design: .rounded))

                    Text(UsageFormatter.remainingTime(until: snapshot.resetAt, now: context.date))
                        .font(.title3.bold())
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
            }

            Text("마지막 업데이트 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView()
                } else {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing)
            .accessibilityIdentifier("refresh-usage")

            Button("연결 해제", role: .destructive) {
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
