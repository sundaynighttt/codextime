import SwiftUI

@main
struct CodexTimeScreenshotPreviewApp: App {
    var body: some Scene {
        WindowGroup("CodexTime") {
            PreviewCard()
        }
        .windowResizability(.contentSize)
    }
}

private struct PreviewCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Codex 95% (6d 16h)")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(.bar)

            VStack(alignment: .leading, spacing: 14) {
                Text("CODEX")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("95% 남음 · 6d 16h")
                    .monospacedDigit()

                Divider()

                Label("지금 새로고침", systemImage: "arrow.clockwise")
                Label("로그인 시 자동 실행", systemImage: "checkmark.square")
                Text("Codex 사용량 설정 열기")
                Text("업데이트 오전 10:24")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("종료")
            }
            .padding(18)
        }
        .frame(width: 310)
        .background(.background)
    }
}
