import SwiftUI
import UIKit

@MainActor
struct GrokConnectionView: View {
    let model: GrokAppModel
    let manualWebModel: ProviderWebUsageModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copiedCode: String?
    @State private var panel: Panel?

    private enum Panel: String, Identifiable {
        case manualWeb
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.isAuthenticating {
                    authorizationSection
                } else {
                    connectionSection
                }
                if let snapshot = model.snapshot {
                    usageSection(snapshot)
                }
                Section("자동 갱신") {
                    Text("앱을 사용하는 동안 약 10분마다 조회하고, 다시 열면 오래된 값을 확인합니다. 위젯은 iOS가 허용하는 시점에 갱신합니다.")
                        .font(.footnote)
                    Text("조회에 실패하면 마지막 값과 확인 시각을 유지합니다. 구독 한도에 따라 주간 또는 월간으로 표시됩니다.")
                        .font(.footnote)
                }
                Section {
                    Button("웹에서 직접 확인", systemImage: "safari") {
                        panel = .manualWeb
                    }
                    .disabled(model.isAuthenticating || model.isDisconnecting)
                    .accessibilityIdentifier("grok-open-manual-web")
                } header: {
                    Text("공식 웹 사용량")
                } footer: {
                    Text("웹에서 직접 읽은 숫자는 수동 기록입니다. 자동 연결된 계정의 사용량과 구분해 보관합니다.")
                }
            }
            .navigationTitle("Grok 계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                        Task { await model.cancelSignIn() }
                    }
                    .accessibilityIdentifier("grok-native-close")
                }
            }
            .sheet(item: $panel) { _ in
                ProviderWebUsageView(model: manualWebModel)
            }
        }
        .onDisappear {
            Task { await model.cancelSignIn() }
        }
    }

    private var connectionSection: some View {
        Section {
            if model.isDisconnecting {
                HStack {
                    ProgressView()
                    Text("연결 해제 중…")
                }
            }
            if model.isConnected {
                Label("이 iPhone에 연결됨", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("grok-native-message")
                if model.connectionFailureStage == .firstUsage, model.isConnected, model.snapshot == nil {
                    Text("다시 로그인하지 않고 ‘지금 새로고침’으로 사용량을 다시 확인할 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("grok-native-first-usage-retry-guidance")
                }
            }
            Button(model.isConnected || model.requiresSignIn ? "Grok 다시 로그인" : "Grok 연결") {
                guard model.canBeginSignIn else { return }
                manualWebModel.disconnect()
                model.beginSignIn()
            }
            .disabled(!model.canBeginSignIn)
            .accessibilityIdentifier("grok-native-signin")

            if model.isConnected {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isRefreshing {
                        HStack {
                            ProgressView()
                            Text("사용량 확인 중…")
                        }
                    } else {
                        Label("지금 새로고침", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!model.canRefresh)
                .accessibilityIdentifier("grok-native-refresh")
            }
            if model.isConnected || model.snapshot != nil {
                Button("연결 해제·기록 삭제", role: .destructive) {
                    Task {
                        await model.disconnect()
                        manualWebModel.disconnect()
                    }
                }
                .accessibilityIdentifier("grok-native-disconnect")
            }
        } header: {
            Text("계정 연결")
        } footer: {
            Text("본인의 공식 xAI 승인 페이지에서 연결합니다. xAI의 공유 로그인 방식을 사용해 승인 화면에 Grok Build가 표시될 수 있습니다. CodexTime은 구독 사용량만 조회하며 대화를 읽거나 모델을 호출하지 않습니다. 연결을 시작하면 이전 Grok 웹 확인 기록을 초기화합니다.")
        }
    }

    private var authorizationSection: some View {
        Section("Grok에서 연결 승인") {
            if let authorization = model.authorization {
                Text("공식 승인 페이지에 아래 코드를 입력하세요.")
                    .font(.subheadline)
                Text(authorization.userCode)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("grok-native-device-code")
                Button(copiedCode == authorization.userCode ? "복사됨" : "코드 복사",
                       systemImage: copiedCode == authorization.userCode ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.setItems(
                        [[UIPasteboard.typeAutomatic: authorization.userCode]],
                        options: [.localOnly: true, .expirationDate: authorization.expiresAt]
                    )
                    copiedCode = authorization.userCode
                }
                .accessibilityIdentifier("grok-native-copy-code")
                Button("Grok에서 승인하기", systemImage: "arrow.up.right.square") {
                    openURL(authorization.verificationURL)
                }
                .accessibilityIdentifier("grok-native-open-approval")
                HStack {
                    ProgressView()
                    Text("승인 후 이 앱으로 돌아오세요.")
                        .font(.footnote)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("공식 연결을 준비하는 중…")
                }
            }
            Button("연결 취소", role: .cancel) {
                Task { await model.cancelSignIn() }
            }
            .accessibilityIdentifier("grok-native-cancel-signin")
        }
    }

    private func usageSection(_ snapshot: GrokUsageSnapshot) -> some View {
        Section(snapshot.period.name + " 사용량") {
            LabeledContent("남은 사용량", value: WebUsageReading.percentText(snapshot.remainingPercent))
            LabeledContent("확인 시각", value: snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
            if let resetAt = snapshot.resetAt {
                LabeledContent("다음 리셋", value: resetAt.formatted(date: .abbreviated, time: .shortened))
            }
            if model.requiresSignIn {
                Text("마지막 확인 값입니다. 다시 로그인한 뒤 최신 사용량을 확인하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
