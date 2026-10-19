import SwiftUI

@main
struct CodexTimeApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--claude-webview-trial") {
                ProviderWebTrialEntry(provider: .claude)
            } else if ProcessInfo.processInfo.arguments.contains("--grok-webview-trial") {
                ProviderWebTrialEntry(provider: .grok)
            } else {
                CodexTimeMainAppView()
            }
            #else
            CodexTimeMainAppView()
            #endif
        }
    }
}

private struct CodexTimeMainAppView: View {
    @State private var model = AppModel()

    var body: some View {
        ContentView(model: model)
    }
}

#if DEBUG
private struct ProviderWebTrialEntry: View {
    @StateObject private var model: ProviderWebUsageModel
    init(provider: WebUsageProvider) {
        _model = StateObject(wrappedValue: ProviderWebUsageModel(provider: provider))
    }
    var body: some View { ProviderWebUsageView(model: model) }
}
#endif
