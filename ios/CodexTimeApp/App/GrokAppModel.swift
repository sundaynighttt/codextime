import Foundation
import Observation
import WidgetKit

protocol GrokAccountServicing: Sendable {
    func isAuthenticated() async -> Bool
    func requestDeviceAuthorization() async throws -> GrokDeviceAuthorization
    func completeDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws -> GrokUsageSnapshot
    func cancelDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws
    func fetchUsage(force: Bool) async throws -> GrokUsageSnapshot
    func signOut() async throws
}

extension GrokAccountClient: GrokAccountServicing {}

/// App-owned state survives sheets and temporary moves to the official sign-in page.
/// All errors shown here come from a fixed enum; provider response text is never displayed.
@MainActor
@Observable
final class GrokAppModel {
    private(set) var snapshot: GrokUsageSnapshot?
    private(set) var authorization: GrokDeviceAuthorization?
    private(set) var isConnected = false
    private(set) var isAuthenticating = false
    private(set) var isRefreshing = false
    private(set) var isDisconnecting = false
    private(set) var requiresSignIn = false
    private(set) var error: GrokClientError?

    @ObservationIgnored private let client: any GrokAccountServicing
    @ObservationIgnored private let cachedSnapshot: @Sendable () -> GrokUsageSnapshot?
    @ObservationIgnored private let isDemoEnabled: @Sendable () -> Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextAutomaticAttemptAt: Date?

    init(
        client: any GrokAccountServicing = GrokAccountClient.shared,
        cachedSnapshot: @escaping @Sendable () -> GrokUsageSnapshot? = { GrokUsageStore().load() },
        isDemoEnabled: @escaping @Sendable () -> Bool = { SharedUsageStore().isDemoEnabled },
        now: @escaping @Sendable () -> Date = { Date() },
        reloadWidgets: @escaping @MainActor () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexTimeWidget")
        }
    ) {
        self.client = client
        self.cachedSnapshot = cachedSnapshot
        self.isDemoEnabled = isDemoEnabled
        self.now = now
        self.reloadWidgets = reloadWidgets
    }

    var message: String? { error?.errorDescription }
    var canRefresh: Bool { isConnected && !isAuthenticating && !isRefreshing && !isDisconnecting }
    var canBeginSignIn: Bool { !isDemoEnabled() && !isAuthenticating && !isRefreshing && !isDisconnecting }

    func load() async {
        guard !isDemoEnabled() else {
            await suspendForDemo()
            return
        }
        guard !isAuthenticating, !isDisconnecting else { return }
        let requestGeneration = generation
        snapshot = validCachedSnapshot()
        let connected = await client.isAuthenticated()
        guard isCurrent(requestGeneration) else { return }
        isConnected = connected
        requiresSignIn = !connected && snapshot != nil
        if connected { await refreshIfNeeded() }
    }

    func refreshIfNeeded() async {
        guard !isDemoEnabled(), isConnected, !isAuthenticating, !isDisconnecting else { return }
        let date = now()
        if let nextAutomaticAttemptAt, date < nextAutomaticAttemptAt { return }
        if let snapshot, !snapshot.isStale(at: date, maxAge: 600) { return }
        await refresh(force: false)
    }

    func refresh(force: Bool = true) async {
        guard !isDemoEnabled(), isConnected, !isAuthenticating, !isRefreshing, !isDisconnecting else { return }
        let requestGeneration = generation
        isRefreshing = true
        defer {
            if generation == requestGeneration { isRefreshing = false }
        }
        do {
            let fresh = try await client.fetchUsage(force: force)
            guard isCurrent(requestGeneration) else { return }
            guard fresh.isValid(at: now()) else { throw GrokClientError.invalidResponse }
            snapshot = fresh
            error = nil
            requiresSignIn = false
            nextAutomaticAttemptAt = nil
            reloadWidgets()
        } catch {
            guard isCurrent(requestGeneration), !Task.isCancelled else { return }
            record(error)
        }
    }

    func beginSignIn() {
        guard canBeginSignIn else { return }
        let requestGeneration = UUID()
        generation = requestGeneration
        isAuthenticating = true
        // A new device flow replaces the previous credential in the client.
        isConnected = false
        authorization = nil
        error = nil
        requiresSignIn = snapshot != nil
        nextAutomaticAttemptAt = nil
        signInTask = Task { [weak self] in
            guard let self else { return }
            var issuedAuthorization: GrokDeviceAuthorization?
            do {
                let issued = try await self.client.requestDeviceAuthorization()
                issuedAuthorization = issued
                guard self.isCurrent(requestGeneration) else {
                    let client = self.client
                    await Task { try? await client.cancelDeviceAuthorization(issued) }.value
                    return
                }
                self.authorization = issued
                // The client has replaced the persistent account generation and cache.
                self.snapshot = nil
                self.requiresSignIn = false
                self.reloadWidgets()
                let fresh = try await self.client.completeDeviceAuthorization(issued)
                guard self.isCurrent(requestGeneration) else { return }
                guard fresh.isValid(at: self.now()) else { throw GrokClientError.invalidResponse }
                self.snapshot = fresh
                self.isConnected = true
                self.requiresSignIn = false
                self.error = nil
                self.reloadWidgets()
            } catch {
                if let issuedAuthorization, Task.isCancelled || !self.isCurrent(requestGeneration) {
                    // A new task is not cancelled along with the outgoing sign-in flow.
                    let client = self.client
                    Task { try? await client.cancelDeviceAuthorization(issuedAuthorization) }
                }
                guard self.isCurrent(requestGeneration), !Task.isCancelled else { return }
                let connected = await self.client.isAuthenticated()
                guard self.isCurrent(requestGeneration) else { return }
                self.isConnected = connected
                if issuedAuthorization != nil, connected {
                    // The new credential may be saved before its first usage request fails.
                    // A reading from the previous account must not follow that credential.
                    self.snapshot = nil
                }
                self.record(error)
            }
            guard self.generation == requestGeneration else { return }
            self.authorization = nil
            self.isAuthenticating = false
            self.signInTask = nil
        }
    }

    func cancelSignIn() async {
        guard isAuthenticating || authorization != nil || signInTask != nil else { return }
        let issued = authorization
        generation = UUID()
        signInTask?.cancel()
        signInTask = nil
        authorization = nil
        isAuthenticating = false
        error = nil
        if let issued { try? await client.cancelDeviceAuthorization(issued) }
    }

    func disconnect() async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        let issued = authorization
        generation = UUID()
        let disconnectGeneration = generation
        signInTask?.cancel()
        signInTask = nil
        authorization = nil
        isAuthenticating = false
        isRefreshing = false
        error = nil
        nextAutomaticAttemptAt = nil
        // Hide the old account immediately. A failed deletion stays visible as an error.
        snapshot = nil
        isConnected = false
        requiresSignIn = false
        if let issued { try? await client.cancelDeviceAuthorization(issued) }
        do {
            try await client.signOut()
            guard generation == disconnectGeneration else { return }
            reloadWidgets()
        } catch {
            guard generation == disconnectGeneration else { return }
            self.error = .secureStorageUnavailable
        }
    }

    /// The persistent demo flag is authoritative, including when a request was already in flight.
    func synchronizeDemoState() async {
        if isDemoEnabled() { await suspendForDemo() }
        else { await load() }
    }

    private func suspendForDemo() async {
        let issued = authorization
        generation = UUID()
        signInTask?.cancel()
        signInTask = nil
        authorization = nil
        isAuthenticating = false
        isRefreshing = false
        isConnected = false
        requiresSignIn = false
        error = nil
        snapshot = nil
        nextAutomaticAttemptAt = nil
        if let issued { try? await client.cancelDeviceAuthorization(issued) }
    }

    private func validCachedSnapshot() -> GrokUsageSnapshot? {
        guard let cached = cachedSnapshot(), cached.isValid(at: now()) else { return nil }
        return cached
    }

    private func isCurrent(_ candidate: UUID) -> Bool {
        generation == candidate && !isDemoEnabled() && !Task.isCancelled
    }

    private func record(_ underlying: Error) {
        let failure = underlying as? GrokClientError ?? .network
        if failure == .connectionChanged || failure == .demoMode { return }
        error = failure
        if failure.requiresSignIn { isConnected = false }
        requiresSignIn = failure.requiresSignIn || (!isConnected && snapshot != nil)
        nextAutomaticAttemptAt = now().addingTimeInterval(failure == .retryLater ? 900 : 60)
    }
}
