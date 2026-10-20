import SwiftUI

@MainActor
struct ClaudeNativeConnectionView: View {
    let model: ClaudeNativeAppModel
    let manualWebModel: ProviderWebUsageModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pastedCode = ""
    @State private var panel: Panel?

    private enum Panel: String, Identifiable {
        case manualWeb
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("iPhone 단독 연결 · 호환 방식") {
                    Text("Anthropic은 구독 OAuth의 타사 앱 사용을 제한합니다. CodexTime의 사용 허용은 확인되지 않았으며, 이 비공식 호환 연결은 지원이 중단되거나 거부될 수 있습니다.")
                        .font(.footnote)
                    Link("Anthropic 공식 인증 지침", destination: URL(string: "https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use")!)
                        .font(.footnote)
                    Text("CodexTime은 발급된 인증정보를 사용량 조회에만 사용하며 대화를 읽거나 모델을 호출하지 않습니다.")
                        .font(.footnote)
                }
                if model.isAuthenticating {
                    authorizationSection
                } else {
                    connectionSection
                }
                if let snapshot = model.snapshot {
                    usageSection(snapshot)
                }
                Section("자동 갱신") {
                    Text("연결에 성공하면 세션·주간 사용량을 함께 읽습니다. 앱을 사용하는 동안 약 10분마다 조회하고, 다시 열면 오래된 값을 확인합니다. 위젯 갱신 시각은 iOS가 결정합니다.")
                        .font(.footnote)
                    Text("일반 조회가 실패하면 마지막 값과 확인 시각을 유지합니다. 다른 계정으로 다시 연결한 경우 이전 계정의 숫자를 사용하지 않습니다.")
                        .font(.footnote)
                }
                Section {
                    Button("웹에서 직접 확인", systemImage: "safari") {
                        panel = .manualWeb
                    }
                    .disabled(model.isAuthenticating || model.isDisconnecting)
                    .accessibilityIdentifier("claude-native-open-manual-web")
                } header: {
                    Text("공식 웹 사용량")
                } footer: {
                    Text("호환 연결이 지원되지 않으면 기존 웹 화면에서 ‘사용량 읽기’를 누르세요. 웹 숫자는 수동 기록이며 직접 연결의 자동 조회와 구분합니다.")
                }
            }
            .navigationTitle("Claude 계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        pastedCode = ""
                        dismiss()
                        Task { await model.cancelSignIn() }
                    }
                    .accessibilityIdentifier("claude-native-close")
                }
            }
            .sheet(item: $panel) { _ in
                ProviderWebUsageView(model: manualWebModel)
            }
        }
        .onDisappear {
            pastedCode = ""
            Task { await model.cancelSignIn() }
        }
        .onChange(of: model.authorization?.id) { _, _ in pastedCode = "" }
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
            message
            Button(model.isConnected || model.requiresSignIn ? "Claude 다시 로그인" : "호환 방식으로 연결") {
                guard model.canBeginSignIn else { return }
                pastedCode = ""
                manualWebModel.disconnect()
                model.beginSignIn()
            }
            .disabled(!model.canBeginSignIn)
            .accessibilityIdentifier("claude-native-signin")
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
                .accessibilityIdentifier("claude-native-refresh")
            }
            if model.isConnected || model.snapshot != nil {
                Button("연결 해제·기록 삭제", role: .destructive) {
                    pastedCode = ""
                    Task {
                        await model.disconnect()
                        manualWebModel.disconnect()
                    }
                }
                .accessibilityIdentifier("claude-native-disconnect")
            }
        } header: {
            Text("계정 연결")
        } footer: {
            Text("연결을 시작하면 이전 Claude 웹 확인 기록을 초기화합니다. 본인의 공식 Claude 승인 페이지에서 연결하세요.")
        }
    }

    private var authorizationSection: some View {
        Section("Claude에서 승인") {
            if let authorization = model.authorization {
                Button("1. Claude 승인 페이지 열기", systemImage: "arrow.up.right.square") {
                    openURL(authorization.authorizationURL)
                }
                .disabled(model.isCompletingAuthorization)
                .accessibilityIdentifier("claude-native-open-approval")
                Text("2. 승인 화면의 인증 결과 전체를 복사한 뒤 이 앱으로 돌아와 붙여넣으세요. code#state 형식만 지원합니다.")
                    .font(.footnote)
                SecureField("code#state 붙여넣기", text: $pastedCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .disabled(model.isCompletingAuthorization)
                    .accessibilityIdentifier("claude-native-pasted-code")
                Button("연결 완료") {
                    let submitted = pastedCode
                    pastedCode = ""
                    model.completeSignIn(pastedCode: submitted)
                }
                .disabled(!model.canCompleteSignIn || pastedCode.isEmpty || pastedCode.utf8.count > 8_192)
                .accessibilityIdentifier("claude-native-submit-code")
                if model.isCompletingAuthorization {
                    HStack {
                        ProgressView()
                        Text("인증과 사용량을 확인하는 중…")
                    }
                }
                Text("인증 결과의 유효 시간은 약 10분입니다. 형식이 다르거나 승인이 거부되면 연결을 취소하고 웹에서 직접 확인하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    ProgressView()
                    Text("연결을 준비하는 중…")
                }
            }
            message
            Button("연결 취소", role: .cancel) {
                pastedCode = ""
                Task { await model.cancelSignIn() }
            }
            .accessibilityIdentifier("claude-native-cancel-signin")
        }
    }

    @ViewBuilder
    private var message: some View {
        if let message = model.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("claude-native-message")
        }
    }

    private func usageSection(_ snapshot: ClaudeNativeUsageSnapshot) -> some View {
        Section("마지막 사용량") {
            LabeledContent("세션 잔여량", value: WebUsageReading.percentText(snapshot.fiveHour.remainingPercent))
            LabeledContent("주간 잔여량", value: WebUsageReading.percentText(snapshot.sevenDay.remainingPercent))
            LabeledContent("확인 시각", value: snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
            if let resetAt = snapshot.fiveHour.resetAt {
                LabeledContent("세션 리셋", value: resetAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let resetAt = snapshot.sevenDay.resetAt {
                LabeledContent("주간 리셋", value: resetAt.formatted(date: .abbreviated, time: .shortened))
            }
            if model.requiresSignIn {
                Text("마지막 확인 값입니다. 다시 로그인한 뒤 최신 사용량을 확인하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
