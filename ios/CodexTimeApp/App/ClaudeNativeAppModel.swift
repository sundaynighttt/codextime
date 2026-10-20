import Foundation
import Observation
import WidgetKit

protocol ClaudeNativeAccountServicing: Sendable {
    func isAuthenticated() async -> Bool
    func beginAuthorization() async throws -> ClaudeNativeAuthorization
    func completeAuthorization(_ authorization: ClaudeNativeAuthorization, pastedCode: String) async throws -> ClaudeNativeUsageSnapshot
    func cancelAuthorization(_ authorization: ClaudeNativeAuthorization) async throws
    func fetchUsage(force: Bool) async throws -> ClaudeNativeUsageSnapshot
    func signOut() async throws
}

extension ClaudeNativeAccountClient: ClaudeNativeAccountServicing {}

/// Phone-only compatibility state survives temporary moves to the official sign-in page.
/// All errors shown here come from a fixed enum; provider response text is never displayed.
@MainActor
@Observable
final class ClaudeNativeAppModel {
    private(set) var snapshot: ClaudeNativeUsageSnapshot?
    private(set) var authorization: ClaudeNativeAuthorization?
    private(set) var isConnected = false
    private(set) var isAuthenticating = false
    private(set) var isCompletingAuthorization = false
    private(set) var isRefreshing = false
    private(set) var isDisconnecting = false
    private(set) var requiresSignIn = false
    private(set) var error: ClaudeNativeClientError?

    @ObservationIgnored private let client: any ClaudeNativeAccountServicing
    @ObservationIgnored private let cachedSnapshot: @Sendable () -> ClaudeNativeUsageSnapshot?
    @ObservationIgnored private let isDemoEnabled: @Sendable () -> Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextAutomaticAttemptAt: Date?

    init(
        client: any ClaudeNativeAccountServicing = ClaudeNativeAccountClient.shared,
        cachedSnapshot: @escaping @Sendable () -> ClaudeNativeUsageSnapshot? = { ClaudeNativeUsageStore().load() },
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
    var canCompleteSignIn: Bool { !isDemoEnabled() && authorization != nil && isAuthenticating && !isCompletingAuthorization && !isDisconnecting }

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
            guard fresh.isValid(at: now()) else { throw ClaudeNativeClientError.invalidResponse }
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
        isCompletingAuthorization = false
        isConnected = false
        authorization = nil
        error = nil
        requiresSignIn = snapshot != nil
        nextAutomaticAttemptAt = nil
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let issued = try await self.client.beginAuthorization()
                guard self.isCurrent(requestGeneration) else {
                    let client = self.client
                    await Task { try? await client.cancelAuthorization(issued) }.value
                    return
                }
                self.authorization = issued
                // The client has replaced the persistent account generation and cache.
                self.snapshot = nil
                self.requiresSignIn = false
                self.reloadWidgets()
                self.signInTask = nil
            } catch {
                guard self.isCurrent(requestGeneration), !Task.isCancelled else { return }
                let connected = await self.client.isAuthenticated()
                guard self.isCurrent(requestGeneration) else { return }
                self.isConnected = connected
                self.record(error)
                self.isAuthenticating = false
                self.signInTask = nil
            }
        }
    }

    /// The user submits only the provider's one-time code#state result.
    /// The PKCE verifier stays in the client and is never passed to the view.
    func completeSignIn(pastedCode: String) {
        guard canCompleteSignIn, let issued = authorization else { return }
        let requestGeneration = generation
        isCompletingAuthorization = true
        error = nil
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.client.completeAuthorization(issued, pastedCode: pastedCode)
                guard self.isCurrent(requestGeneration) else { return }
                guard fresh.isValid(at: self.now()) else { throw ClaudeNativeClientError.invalidResponse }
                self.snapshot = fresh
                self.isConnected = true
                self.requiresSignIn = false
                self.error = nil
                self.reloadWidgets()
            } catch {
                if Task.isCancelled || !self.isCurrent(requestGeneration) {
                    let client = self.client
                    Task { try? await client.cancelAuthorization(issued) }
                }
                guard self.isCurrent(requestGeneration), !Task.isCancelled else { return }
                if (error as? ClaudeNativeClientError) == .invalidCallback {
                    self.error = .invalidCallback
                    self.isCompletingAuthorization = false
                    self.signInTask = nil
                    return
                }
                let connected = await self.client.isAuthenticated()
                guard self.isCurrent(requestGeneration) else { return }
                self.isConnected = connected
                if connected {
                    // Credentials may be saved even when the first usage query fails.
                    // Never attach the previous account's reading to those credentials.
                    self.snapshot = nil
                }
                self.record(error)
            }
            guard self.generation == requestGeneration else { return }
            self.authorization = nil
            self.isAuthenticating = false
            self.isCompletingAuthorization = false
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
        isCompletingAuthorization = false
        error = nil
        if let issued { try? await client.cancelAuthorization(issued) }
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
        isCompletingAuthorization = false
        isRefreshing = false
        error = nil
        nextAutomaticAttemptAt = nil
        // Hide the old account immediately. A failed deletion stays visible as an error.
        snapshot = nil
        isConnected = false
        requiresSignIn = false
        if let issued { try? await client.cancelAuthorization(issued) }
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
        isCompletingAuthorization = false
        isRefreshing = false
        isConnected = false
        requiresSignIn = false
        error = nil
        snapshot = nil
        nextAutomaticAttemptAt = nil
        if let issued { try? await client.cancelAuthorization(issued) }
    }

    private func validCachedSnapshot() -> ClaudeNativeUsageSnapshot? {
        guard let cached = cachedSnapshot(), cached.isValid(at: now()) else { return nil }
        return cached
    }

    private func isCurrent(_ candidate: UUID) -> Bool {
        generation == candidate && !isDemoEnabled() && !Task.isCancelled
    }

    private func record(_ underlying: Error) {
        let failure = underlying as? ClaudeNativeClientError ?? .network
        if failure == .connectionChanged || failure == .demoMode { return }
        error = failure
        if failure.requiresSignIn { isConnected = false }
        requiresSignIn = failure.requiresSignIn || (!isConnected && snapshot != nil)
        nextAutomaticAttemptAt = now().addingTimeInterval(failure == .retryLater ? 900 : 60)
    }
}
