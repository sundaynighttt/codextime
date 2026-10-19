import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderUsageState]
    @Published private(set) var now: Date
    @Published private(set) var enabledProviders: Set<ProviderID>

    var isRefreshing: Bool { states.values.contains { enabledProviders.contains($0.id) && $0.isRefreshing } }

    private let clients: [ProviderID: any UsageProviderClient]
    private let requestTimeout: TimeInterval
    private let currentDate: @Sendable () -> Date
    private var refreshTasks: [ProviderID: Task<Void, Never>] = [:]
    private var refreshWhenIdle: Set<ProviderID> = []
    private var resettingProviders: Set<ProviderID> = []
    private var disconnectTasks: [ProviderID: Task<Void, Never>] = [:]
    private var clockTimer: Timer?
    private var refreshTimer: Timer?
    private var isShuttingDown = false

    init(
        clients: [any UsageProviderClient] = ProductionUsageProviders.clients,
        enabledProviders: Set<ProviderID> = Set(ProviderID.allCases),
        requestTimeout: TimeInterval = 15,
        automaticallyStart: Bool = true,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        var uniqueClients: [ProviderID: any UsageProviderClient] = [:]
        for client in clients where uniqueClients[client.id] == nil {
            uniqueClients[client.id] = client
        }
        self.clients = uniqueClients
        self.enabledProviders = enabledProviders
        self.requestTimeout = requestTimeout.isFinite ? min(max(requestTimeout, 0.001), 3_600) : 15
        self.currentDate = currentDate
        self.now = currentDate()
        self.states = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, ProviderUsageState(id: $0))
        })
        if automaticallyStart {
            Task { @MainActor [weak self] in self?.start() }
        }
    }

    func start() {
        guard !isShuttingDown, clockTimer == nil else { return }
        refresh()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = self.currentDate()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        for id in ProviderID.allCases { refresh(id) }
    }

    func refresh(_ id: ProviderID) {
        // Keep this slot occupied through cancellation/transport cleanup.
        guard !isShuttingDown, enabledProviders.contains(id), !resettingProviders.contains(id),
              refreshTasks[id] == nil else { return }
        guard let client = clients[id] else {
            states[id]?.failure = .notConnected
            return
        }
        beginRequest(id, using: client, requestingPermission: false)
    }

    /// Only an explicit user action may supply a client that allows an OS prompt.
    /// This shares the normal per-provider slot, but user response time is not a
    /// network deadline. The provider must still bound its actual network I/O.
    func connect(_ id: ProviderID, using client: any UsageProviderClient) {
        guard !isShuttingDown, enabledProviders.contains(id), !resettingProviders.contains(id),
              refreshTasks[id] == nil else { return }
        guard client.id == id else {
            states[id]?.failure = .invalidResponse
            return
        }
        beginRequest(id, using: client, requestingPermission: true)
    }

    /// Hiding keeps the last successful value but cancels owned work. A rapid
    /// re-enable waits for that work's cleanup before starting exactly one refresh.
    func setEnabled(_ enabled: Bool, for id: ProviderID) {
        guard enabledProviders.contains(id) != enabled else { return }
        if enabled {
            enabledProviders.insert(id)
            if refreshTasks[id] != nil {
                refreshWhenIdle.insert(id)
            } else {
                refresh(id)
            }
        } else {
            enabledProviders.remove(id)
            refreshWhenIdle.remove(id)
            refreshTasks[id]?.cancel()
        }
    }

    /// Callers first revoke the provider's connection/verification preference.
    /// Block new requests while the current worker cleans up, then remove only
    /// this provider's cached account data. Repeated disconnects join one reset.
    func disconnect(_ id: ProviderID) async {
        if let pending = disconnectTasks[id] {
            await pending.value
            return
        }
        resettingProviders.insert(id)
        refreshWhenIdle.remove(id)
        let owned = refreshTasks[id]
        owned?.cancel()
        let reset = Task { @MainActor [weak self] in
            if let owned { await owned.value }
            guard let self else { return }
            self.states[id] = ProviderUsageState(id: id)
            self.resettingProviders.remove(id)
            self.disconnectTasks[id] = nil
            self.now = self.currentDate()
        }
        disconnectTasks[id] = reset
        await reset.value
    }

    private func beginRequest(
        _ id: ProviderID,
        using client: any UsageProviderClient,
        requestingPermission: Bool
    ) {
        states[id]?.isRefreshing = true
        states[id]?.connectionIsPending = requestingPermission
        states[id]?.lastAttempt = currentDate()
        let timeout = requestTimeout
        refreshTasks[id] = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let snapshot: ProviderUsageSnapshot
                if requestingPermission {
                    snapshot = try await client.fetchUsage()
                } else {
                    snapshot = try await fetchUsageWithTimeout(client: client, timeout: timeout)
                }
                try Task.checkCancellation()
                guard snapshot.provider == id else { throw ProviderUsageFailure.invalidResponse }
                guard let self else { return }
                self.states[id]?.snapshot = snapshot
                self.states[id]?.lastSuccess = self.currentDate()
                self.states[id]?.failure = nil
            } catch {
                guard let self else { return }
                // Never publish raw CLI/server error text.
                if !self.isShuttingDown, !Task.isCancelled, self.enabledProviders.contains(id),
                   !self.resettingProviders.contains(id) {
                    self.states[id]?.failure = (error as? ProviderUsageFailure) ?? .queryFailed
                }
            }
            guard let self else { return }
            self.states[id]?.isRefreshing = false
            self.states[id]?.connectionIsPending = false
            self.now = self.currentDate()
            self.refreshTasks[id] = nil
            if self.refreshWhenIdle.remove(id) != nil { self.refresh(id) }
        }
    }

    /// Application termination waits for provider cleanup before exiting. An OS
    /// authorization dialog may need the user to resolve it before it can return.
    func shutdown() async {
        isShuttingDown = true
        refreshWhenIdle.removeAll()
        clockTimer?.invalidate()
        refreshTimer?.invalidate()
        clockTimer = nil
        refreshTimer = nil
        let pending = Array(refreshTasks.values)
        let resets = Array(disconnectTasks.values)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
        for task in resets { await task.value }
    }

    /// The same path is used by tests and explicit refresh actions. Requests that
    /// are already running are joined instead of duplicated.
    func refreshAndWait(_ id: ProviderID? = nil) async {
        let ids = id.map { [$0] } ?? ProviderID.allCases
        for id in ids { refresh(id) }
        // A show action may have queued one refresh after cancellation cleanup.
        // Join that successor too without issuing a second request ourselves.
        while true {
            let pending = ids.compactMap { refreshTasks[$0] }
            guard !pending.isEmpty else { return }
            for task in pending { await task.value }
        }
    }
}

private func fetchUsageWithTimeout(
    client: any UsageProviderClient,
    timeout: TimeInterval
) async throws -> ProviderUsageSnapshot {
    try await withThrowingTaskGroup(of: ProviderUsageSnapshot.self) { group in
        group.addTask { try await client.fetchUsage() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw ProviderUsageFailure.timeout
        }
        defer { group.cancelAll() }
        // Structured cancellation waits for the client's bounded cleanup. It does
        // not leave a detached request behind that could overlap the next refresh.
        guard let snapshot = try await group.next() else { throw ProviderUsageFailure.invalidResponse }
        return snapshot
    }
}
