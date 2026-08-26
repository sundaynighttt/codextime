import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var report: UsageReport?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var now = Date()

    private let client: CodexAppServerClient
    private var clockTimer: Timer?
    private var refreshTimer: Timer?

    init(client: CodexAppServerClient = CodexAppServerClient()) {
        self.client = client
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func menuTitle(showResetTime: Bool) -> String {
        UsageFormatter.compactTitle(for: report?.main, now: now, showResetTime: showResetTime)
    }

    func start() {
        guard clockTimer == nil else { return }
        refresh()

        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            do {
                report = try await client.fetchRateLimits()
                lastUpdated = Date()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }
}
