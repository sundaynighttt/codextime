import SwiftUI
import UsageSync
import WidgetKit

struct CloudSyncSettingsView: View {
    @ObservedObject var cloudSync: UsageCloudSync
    var isDemoMode = false
    @State private var isExpanded = false
    @State private var isWorking = false
    @State private var showingDeletionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text("Mac → iCloud 동기화")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "펼쳐짐" : "접힘")
            .accessibilityIdentifier("toggle-icloud-settings")

            if isExpanded {
            VStack(alignment: .leading, spacing: 14) {
                Text(isDemoMode ? "예시 보기 중 iCloud 동기화 일시 정지" : cloudSync.state.message)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("icloud-sync-status")

                if isDemoMode {
                    Text("예시 카드와 위젯에는 실제 iCloud 값을 섞지 않습니다. 예시를 끝내면 기존 동기화 설정으로 수신을 다시 시작합니다.")
                }
                Text("본인 Apple 계정의 비공개 iCloud에 Grok 잔여율·리셋·조회 시각·상태만 보관합니다. 비밀번호와 인증 토큰은 Mac에 남습니다.")
                Text("같은 Apple 계정의 Mac에서 동기화를 켜 주세요. 최신 값은 Mac 앱이 실행되고 인터넷에 연결되어 있을 때 도착합니다. 20분이 지난 값은 오래된 정보로 표시합니다.")

                if cloudSync.isEnabled && !isDemoMode {
                    if let reading = cloudSync.readings[.grok], let observedAt = reading.observedAt {
                        Text("Grok 조회 " + UsageFormatter.updateTime(observedAt))
                        if let resetAt = reading.resetAt {
                            Text("Grok 리셋 " + resetAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    Button("iCloud에서 새로고침") {
                        perform { await cloudSync.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("refresh-icloud")

                    Button("이 iPhone에서 동기화 해제", role: .destructive) {
                        cloudSync.stopReceiving()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    .accessibilityIdentifier("disconnect-icloud")
                } else {
                    Button("본인 iCloud로 연결") {
                        perform { await cloudSync.enable() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("connect-icloud")
                }

                Text("Claude는 공급자 허용 확인 전까지 연결을 차단하며 실제 잔여량을 표시하지 않습니다.")
                    .accessibilityIdentifier("claude-cloud-blocked")

                Text("ChatGPT 연결과 iCloud 동기화는 독립적입니다. iPhone 동기화 해제 시 이 기기의 동기화 캐시만 지우며 Mac과 iCloud의 데이터는 유지합니다. iCloud 로그아웃이나 Apple 계정 변경이 감지되면 이전 계정의 값을 지웁니다.")

                Button("iCloud 동기화 데이터 삭제", role: .destructive) {
                    showingDeletionConfirmation = true
                }
                .accessibilityIdentifier("delete-icloud-data")

                Text("다른 Mac에서 동기화가 켜져 있으면 다음 조회 때 다시 저장될 수 있습니다. 영구히 중단하려면 Mac에서도 동기화를 해제하세요.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .disabled(isWorking || isDemoMode)
            }
        }
        .font(.subheadline)
        .accessibilityIdentifier("icloud-sync-settings")
        .confirmationDialog("본인 iCloud의 동기화 결과를 삭제할까요?", isPresented: $showingDeletionConfirmation, titleVisibility: .visible) {
            Button("iCloud 데이터 삭제", role: .destructive) {
                perform { await cloudSync.disableAndDelete() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("Grok·Claude 동기화 결과를 삭제하고 이 iPhone의 수신을 중단합니다. 서비스 계정과 ChatGPT 연결은 유지됩니다.")
        }
    }

    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        guard !isWorking, !isDemoMode else { return }
        isWorking = true
        Task { @MainActor in
            await operation()
            WidgetCenter.shared.reloadAllTimelines()
            isWorking = false
        }
    }
}
