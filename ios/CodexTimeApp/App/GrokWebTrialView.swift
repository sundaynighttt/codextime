import SwiftUI
import WebKit

@MainActor
struct ProviderWebUsageView: View {
    @ObservedObject var model: ProviderWebUsageModel
    @Environment(\.dismiss) private var dismiss

    init(model: ProviderWebUsageModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.provider.name) 공식 웹에서 직접 로그인하세요")
                        .font(.subheadline.weight(.semibold))
                    Text("로그인은 이 앱이 실행되는 동안 메모리에만 유지합니다. 완료로 화면을 닫아도 유지되며, 연결 해제·앱 종료 후에는 다시 로그인해야 합니다. 비밀번호·쿠키·토큰을 앱이 읽거나 전송하지 않습니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.pageHost)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("grok-trial-page-host")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                if let webView = model.webView {
                    GrokTrialWebContent(webView: webView)
                        .accessibilityIdentifier("grok-trial-webview")
                } else {
                    ContentUnavailableView("웹 세션 종료", systemImage: "xmark.circle",
                                           description: Text("다시 연결하면 새 메모리 세션을 엽니다."))
                    Button("웹 세션 다시 열기") { model.open() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("grok-trial-reopen")
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        if model.isLoading { ProgressView() }
                        Text(model.navigationMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("사용량 화면 열기") { model.openUsagePage() }
                            .font(.caption)
                            .disabled(model.webView == nil)
                            .accessibilityIdentifier("grok-trial-open-usage")
                    }
                    Toggle("공식 사용량 숫자가 화면에 보입니다", isOn: $model.userConfirmedUsageVisible)
                        .font(.caption)
                        .disabled(!model.isAtUsagePage)
                        .accessibilityIdentifier("grok-trial-confirm-usage")
                    HStack {
                        Text("숫자 의미").font(.caption)
                        Picker("숫자 의미", selection: $model.valueKind) {
                            Text("사용함").tag(WebUsageValueKind.used)
                            Text("남음").tag(WebUsageValueKind.remaining)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("web-usage-value-kind")
                    }
                    if model.provider == .claude {
                        Picker("읽는 한도", selection: $model.metric) {
                            Text("현재 세션").tag(WebUsageMetric.claudeSession)
                            Text("주간").tag(WebUsageMetric.claudeWeekly)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("web-usage-metric")
                    } else {
                        Text("주간 한도").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button(model.isPointReadArmed ? "숫자 위치 읽기 취소" : "숫자 위치 지정해서 읽기") {
                        if model.isPointReadArmed { model.cancelPointRead() }
                        else { model.armPointRead() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canReadVisibleUsage && !model.isPointReadArmed)
                    .accessibilityIdentifier("grok-trial-read-usage")
                    Text(model.readMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("grok-trial-read-status")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("\(model.provider.name) 웹 사용량")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("연결 해제", role: .destructive) { model.disconnect() }
                        .accessibilityIdentifier("web-usage-disconnect")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        model.cancelPointRead()
                        dismiss()
                    }
                    .accessibilityIdentifier("grok-trial-close")
                }
            }
        }
        .onAppear { model.open() }
        .onDisappear { model.cancelPointRead() }
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
