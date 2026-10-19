import SwiftUI
import UIKit
import WebKit

@MainActor
struct ProviderWebUsageView: View {
    @ObservedObject var model: ProviderWebUsageModel
    @Environment(\.dismiss) private var dismiss
    @State private var presentedPanel: Panel?
    @State private var isKeyboardVisible = false
    @State private var didAttemptRead = false

    private enum Panel: String, Identifiable {
        case reading, help
        var id: String { rawValue }
    }

    init(model: ProviderWebUsageModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            webContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isKeyboardVisible { compactControls }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(model.provider.name).font(.headline)
                            Text(model.pageHost)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .accessibilityIdentifier("grok-trial-page-host")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if isKeyboardVisible {
                            Button("키보드 닫기", systemImage: "keyboard.chevron.compact.down") {
                                endEditing()
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("web-usage-hide-keyboard")
                        } else {
                            Menu {
                                Button("사용량 화면 열기") { model.openUsagePage() }
                                    .disabled(model.webView == nil)
                                Button("읽기 설정", systemImage: "slider.horizontal.3") { openPanel(.reading) }
                                Button("도움말", systemImage: "questionmark.circle") { openPanel(.help) }
                                Divider()
                                Button("연결 해제·기록 삭제", role: .destructive) { model.disconnect() }
                                    .accessibilityIdentifier("web-usage-disconnect")
                            } label: {
                                Label("더 보기", systemImage: "ellipsis.circle")
                            }
                            .accessibilityIdentifier("web-usage-menu")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("완료") {
                            endEditing()
                            dismiss()
                        }
                        .accessibilityIdentifier("grok-trial-close")
                    }
                }
                .sheet(item: $presentedPanel) { panel in
                    switch panel {
                    case .reading: readingPanel
                    case .help: helpPanel
                    }
                }
        }
        .onAppear { model.open() }
        .onDisappear { model.cancelPointRead(clearMessage: model.isPointReadArmed || model.isReading) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    @ViewBuilder
    private var webContent: some View {
        if let webView = model.webView {
            GrokTrialWebContent(webView: webView)
                .accessibilityIdentifier("grok-trial-webview")
        } else {
            VStack(spacing: 12) {
                ContentUnavailableView("웹 세션 종료", systemImage: "xmark.circle",
                                       description: Text("다시 연결하면 새 메모리 세션을 엽니다."))
                Button("웹 세션 다시 열기") { model.open() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("grok-trial-reopen")
            }
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Button("사용량 열기") { model.openUsagePage() }
                    .disabled(model.webView == nil)
                    .accessibilityIdentifier("grok-trial-open-usage")
                Spacer(minLength: 4)
                if model.isAtUsagePage {
                    Button("읽기 설정", systemImage: "slider.horizontal.3") { openPanel(.reading) }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("web-usage-read-settings")
                    Button(model.isPointReadArmed ? "취소" : "숫자 읽기") {
                        didAttemptRead = true
                        if model.isPointReadArmed { model.cancelPointRead() }
                        else { model.armPointRead() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canReadVisibleUsage && !model.isPointReadArmed)
                    .accessibilityIdentifier("grok-trial-read-usage")
                } else {
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Text("로그인 후 사용량을 여세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            if didAttemptRead {
                Button { openPanel(.reading) } label: {
                    Text(model.readMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("grok-trial-read-status")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var readingPanel: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("사용량 숫자가 화면에 보입니다", isOn: $model.userConfirmedUsageVisible)
                        .disabled(!model.isAtUsagePage)
                        .accessibilityIdentifier("grok-trial-confirm-usage")
                    Picker("숫자 의미", selection: $model.valueKind) {
                        Text("사용함").tag(WebUsageValueKind.used)
                        Text("남음").tag(WebUsageValueKind.remaining)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("web-usage-value-kind")
                    if model.provider == .claude {
                        Picker("읽는 한도", selection: $model.metric) {
                            Text("현재 세션").tag(WebUsageMetric.claudeSession)
                            Text("주간").tag(WebUsageMetric.claudeWeekly)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("web-usage-metric")
                    } else {
                        LabeledContent("읽는 한도", value: "주간")
                    }
                } footer: {
                    Text("설정을 마친 뒤 ‘숫자 읽기’를 누르고 웹 화면의 %를 한 번 탭하세요.")
                }
                Section("최근 결과") { Text(model.readMessage).font(.footnote) }
            }
            .navigationTitle("읽기 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { presentedPanel = nil }
                        .accessibilityIdentifier("web-usage-settings-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var helpPanel: some View {
        NavigationStack {
            Form {
                Section("계정 연결") {
                    Text("공식 웹에서 본인 계정으로 로그인한 뒤 ‘사용량 열기’를 누르세요.")
                    Text("로그인은 앱 실행 중에만 유지됩니다. 화면을 닫아도 유지되지만 앱 종료·연결 해제 후에는 다시 로그인해야 합니다.")
                }
                Section("사용량 확인") {
                    Text("사용량 화면에서 ‘읽기 설정’을 열어 숫자 의미와 한도를 고르세요. ‘숫자 읽기’를 누르고 15초 안에 해당 %를 한 번 탭하면 잔여율로 표시합니다.")
                    Text("웹 사용량은 자동 갱신되지 않습니다. 앱과 위젯에는 마지막 수동 확인 값과 시각이 남습니다.")
                }
                Section("개인정보") {
                    Text("앱은 비밀번호·쿠키·토큰을 읽거나 전송하지 않습니다. 해당 서비스의 연결 해제는 임시 웹 세션과 저장된 사용량 숫자를 지웁니다.")
                }
                Section("현재 화면") {
                    Text(model.pageHost)
                    Text(model.navigationMessage).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("도움말")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { presentedPanel = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func endEditing() {
        model.cancelPointRead(clearMessage: model.isPointReadArmed || model.isReading)
        model.webView?.endEditing(true)
    }

    private func openPanel(_ panel: Panel) {
        endEditing()
        presentedPanel = panel
    }
}

private struct GrokTrialWebContent: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    // Hiding the sheet keeps the model's same in-memory WKWebView/session alive.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {}
}

typealias GrokWebTrialView = ProviderWebUsageView
