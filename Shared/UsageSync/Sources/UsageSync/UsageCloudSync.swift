import CloudKit
import Combine
import CoreFoundation
import Foundation

enum CloudSyncConfiguration {
    /// Xcode substitutes build settings into plist strings as exact YES/NO values.
    /// Accept only a real plist Boolean true or the explicit enabled string.
    static func isEnabled(container: Any?, flag: Any?) -> Bool {
        guard container as? String == CloudKitUsageSyncTransport.containerIdentifier else { return false }
        if let string = flag as? String { return string == "YES" }
        guard let number = flag as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
}

@MainActor public protocol UsageSyncTransport: AnyObject {
    /// A one-way, locally stored scope. Never included in a synced payload.
    func accountScope() async throws -> String?
    func fetch(expectedScope: String) async throws -> [SyncedUsage]
    func save(_ readings: [SyncedUsage], expectedScope: String) async throws
    func deleteAll(expectedScope: String) async throws
}

public enum UsageSyncCache {
    static let enabledKey = "codextime.icloud.enabled.v1"
    static let sessionKey = "codextime.icloud.session.v1"
    static let scopeKey = "codextime.icloud.scope.v1"
    static let cacheKey = "codextime.icloud.readings.v1"
    static let deletionKey = "codextime.icloud.pendingDeletionScope.v1"

    public static func isRequestedEnabled(preferences: UserDefaults = .standard) -> Bool {
        preferences.bool(forKey: enabledKey)
    }

    /// Call only after verifying the current iCloud account scope with the transport.
    public static func readings(preferences: UserDefaults = .standard, verifiedScope: String) -> [SyncProvider: SyncedUsage] {
        guard isRequestedEnabled(preferences: preferences),
              preferences.string(forKey: scopeKey) == verifiedScope,
              let data = preferences.data(forKey: cacheKey), data.count <= 8_192,
              let values = try? JSONDecoder().decode([SyncedUsage].self, from: data),
              Set(values.map(\.provider)).count == values.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.provider, $0) })
    }

    static func store(_ values: [SyncProvider: SyncedUsage], scope: String, preferences: UserDefaults) {
        guard let data = try? JSONEncoder().encode(SyncProvider.allCases.compactMap { values[$0] }) else { return }
        preferences.set(scope, forKey: scopeKey)
        preferences.set(data, forKey: cacheKey)
    }

    static func clear(preferences: UserDefaults) {
        preferences.removeObject(forKey: cacheKey)
        preferences.removeObject(forKey: scopeKey)
    }
}

@MainActor public final class UsageCloudSync: ObservableObject {
    @Published public private(set) var isEnabled = false
    @Published public private(set) var readings: [SyncProvider: SyncedUsage] = [:]
    @Published public private(set) var state: CloudSyncState = .disabled

    private let preferences: UserDefaults
    private let transport: UsageSyncTransport?
    private var activeScope: String?
    private var activeSession: String?
    private var writeRevision: UInt64 = 0
    private var generation: UInt64 = 0
    private var notificationObserver: NSObjectProtocol?
    private var preferencesObserver: NSObjectProtocol?
    private var mutationTail: Task<Void, Never>?
    private var mutations: [UUID: Task<Void, Error>] = [:]

    public init(preferences: UserDefaults = .standard, transport: UsageSyncTransport? = nil) {
        self.preferences = preferences
        if let transport {
            self.transport = transport
        } else if CloudSyncConfiguration.isEnabled(
            container: Bundle.main.object(forInfoDictionaryKey: "CodexTimeCloudContainer"),
            flag: Bundle.main.object(forInfoDictionaryKey: "CodexTimeCloudSyncConfigured")) {
            self.transport = CloudKitUsageSyncTransport()
        } else {
            // An unsigned SwiftPM test executable has no entitled application bundle.
            // Do not instantiate CKContainer in that environment.
            self.transport = nil
        }
        if preferences.string(forKey: UsageSyncCache.deletionKey) != nil { state = .deletionPending }
        preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = self.activeSession else { return }
                if !self.persistedSessionMatches(session) { self.deactivateLocal() }
            }
        }
        notificationObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.accountDidChange() }
        }
    }

    deinit {
        if let notificationObserver { NotificationCenter.default.removeObserver(notificationObserver) }
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        for task in mutations.values { task.cancel() }
    }

    public func enable() async {
        guard transport != nil else { state = .notConfigured; return }
        if preferences.string(forKey: UsageSyncCache.deletionKey) != nil {
            await retryPendingDeletion()
            guard preferences.string(forKey: UsageSyncCache.deletionKey) == nil else { return }
        }
        let currentGeneration = generation
        let session = UUID().uuidString
        preferences.set(session, forKey: UsageSyncCache.sessionKey)
        preferences.set(true, forKey: UsageSyncCache.enabledKey)
        do {
            let accountScope = try await transport?.accountScope()
            guard generation == currentGeneration else { return }
            guard persistedSessionMatches(session) else { deactivateLocal(); return }
            guard let scope = accountScope else { signedOut(); return }
            if activeScope != scope {
                readings = [:]
                if preferences.string(forKey: UsageSyncCache.scopeKey) != scope {
                    UsageSyncCache.clear(preferences: preferences)
                }
                activeScope = scope
            }
            activeSession = session
            isEnabled = true
            readings = UsageSyncCache.readings(preferences: preferences, verifiedScope: scope)
            await refresh()
        } catch { handle(error, generation: currentGeneration) }
    }

    /// Also resumes a previous opt-in, but loads no cache until the account is verified.
    public func refresh() async {
        guard let session = requestedSession() else { deactivateLocal(); return }
        guard let transport else { state = .notConfigured; return }
        let currentGeneration = generation
        let fetchWriteRevision = writeRevision
        do {
            guard let scope = try await verifiedScope(generation: currentGeneration, session: session) else { return }
            guard generation == currentGeneration else { return }
            guard persistedSessionMatches(session) else { deactivateLocal(); return }
            activeSession = session
            isEnabled = true
            if readings.isEmpty { readings = UsageSyncCache.readings(preferences: preferences, verifiedScope: scope) }
            state = .syncing
            let values = try await transport.fetch(expectedScope: scope)
            guard isCurrent(generation: currentGeneration, scope: scope, session: session),
                  writeRevision == fetchWriteRevision else { return }
            guard Set(values.map(\.provider)).count == values.count else { throw UsageSyncError.invalidPayload }
            readings = Dictionary(uniqueKeysWithValues: values.map { ($0.provider, $0) })
            UsageSyncCache.store(readings, scope: scope, preferences: preferences)
            state = .ready
        } catch { handle(error, generation: currentGeneration) }
    }

    /// Publishes only the allowlisted model. Provider credentials never reach this API.
    public func publish(_ values: [SyncedUsage]) async {
        guard isEnabled, let session = activeSession, let transport else { return }
        guard persistedSessionMatches(session) else { deactivateLocal(); return }
        let currentGeneration = generation
        writeRevision &+= 1
        do {
            guard Set(values.map(\.provider)).count == values.count else { throw UsageSyncError.invalidPayload }
            guard let scope = try await verifiedScope(generation: currentGeneration, session: session) else { return }
            state = .syncing
            try await mutate(generation: currentGeneration) { [weak self] in
                guard let self, self.isCurrent(generation: currentGeneration, scope: scope, session: session) else { throw CancellationError() }
                try await transport.save(values, expectedScope: scope)
                self.writeRevision &+= 1
            }
            guard isCurrent(generation: currentGeneration, scope: scope, session: session) else { return }
            readings = Dictionary(uniqueKeysWithValues: values.map { ($0.provider, $0) })
            UsageSyncCache.store(readings, scope: scope, preferences: preferences)
            state = .ready
        } catch { handle(error, generation: currentGeneration) }
    }

    /// Stops local receiving immediately, then deletes only this account's two records.
    /// Failed deletion remains retryable; it never silently re-enables sync.
    public func disableAndDelete() async {
        let knownScope = preferences.string(forKey: UsageSyncCache.deletionKey)
            ?? activeScope ?? preferences.string(forKey: UsageSyncCache.scopeKey)
        stopReceiving()
        let currentGeneration = generation
        if let knownScope {
            preferences.set(knownScope, forKey: UsageSyncCache.deletionKey)
        } else {
            // An explicit delete remains usable after local-only receiving was stopped.
            // Resolve only the current private account; never guess a former scope.
            guard let transport else { state = .notConfigured; return }
            do {
                let scope = try await transport.accountScope()
                guard generation == currentGeneration else { return }
                guard let scope else { state = .signedOut; return }
                preferences.set(scope, forKey: UsageSyncCache.deletionKey)
            } catch { handle(error, generation: currentGeneration); return }
        }
        await retryPendingDeletion()
    }

    public func stopReceiving() {
        invalidateOperations()
        isEnabled = false
        readings = [:]
        activeScope = nil
        activeSession = nil
        preferences.set(false, forKey: UsageSyncCache.enabledKey)
        preferences.removeObject(forKey: UsageSyncCache.sessionKey)
        UsageSyncCache.clear(preferences: preferences)
        state = preferences.string(forKey: UsageSyncCache.deletionKey) == nil ? .disabled : .deletionPending
    }

    public func retryPendingDeletion() async {
        guard let expectedScope = preferences.string(forKey: UsageSyncCache.deletionKey) else { return }
        state = .deletionPending
        guard let transport else { return }
        let currentGeneration = generation
        do {
            guard try await transport.accountScope() == expectedScope else { return }
            try await mutate(generation: currentGeneration) {
                try await transport.deleteAll(expectedScope: expectedScope)
            }
            guard generation == currentGeneration,
                  preferences.string(forKey: UsageSyncCache.deletionKey) == expectedScope else { return }
            preferences.removeObject(forKey: UsageSyncCache.deletionKey)
            state = .disabled
        } catch {
            guard generation == currentGeneration else { return }
            state = .deletionPending
        }
    }

    private func verifiedScope(generation expectedGeneration: UInt64, session: String) async throws -> String? {
        guard let transport else { throw UsageSyncError.notConfigured }
        let accountScope = try await transport.accountScope()
        guard generation == expectedGeneration else { return nil }
        guard persistedSessionMatches(session) else { deactivateLocal(); return nil }
        guard let scope = accountScope else { signedOut(); return nil }
        let previousScope = activeScope ?? preferences.string(forKey: UsageSyncCache.scopeKey)
        if let previousScope, previousScope != scope {
            accountDidChange()
            return nil
        }
        activeScope = scope
        return scope
    }

    private func requestedSession() -> String? {
        guard UsageSyncCache.isRequestedEnabled(preferences: preferences) else { return nil }
        if let session = preferences.string(forKey: UsageSyncCache.sessionKey) { return session }
        let session = UUID().uuidString
        preferences.set(session, forKey: UsageSyncCache.sessionKey)
        return session
    }

    private func persistedSessionMatches(_ session: String) -> Bool {
        UsageSyncCache.isRequestedEnabled(preferences: preferences)
            && preferences.string(forKey: UsageSyncCache.sessionKey) == session
    }

    private func isCurrent(generation expectedGeneration: UInt64, scope: String, session: String) -> Bool {
        guard generation == expectedGeneration else { return false }
        guard persistedSessionMatches(session) else { deactivateLocal(); return false }
        return isEnabled && activeScope == scope && activeSession == session
    }

    /// Another app-group process may have stopped or replaced this session.
    /// Do not erase its newer consent or cache when retiring this instance.
    private func deactivateLocal() {
        invalidateOperations()
        isEnabled = false
        readings = [:]
        activeScope = nil
        activeSession = nil
        state = preferences.string(forKey: UsageSyncCache.deletionKey) == nil ? .disabled : .deletionPending
    }

    private func accountDidChange() {
        stopReceiving()
        state = .signedOut
    }

    private func signedOut() {
        accountDidChange()
    }

    private func invalidateOperations() {
        generation &+= 1
        for task in mutations.values { task.cancel() }
    }

    /// A single mutation queue prevents a late save from overtaking disable/delete.
    private func mutate(generation expectedGeneration: UInt64, body: @escaping @MainActor () async throws -> Void) async throws {
        let identifier = UUID()
        let previous = mutationTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            try Task.checkCancellation()
            guard let self, self.generation == expectedGeneration else { throw CancellationError() }
            try await body()
        }
        mutations[identifier] = task
        mutationTail = Task { _ = try? await task.value }
        defer { mutations.removeValue(forKey: identifier) }
        try await task.value
    }

    private func handle(_ error: Error, generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration, !(error is CancellationError) else { return }
        if let session = activeSession, !persistedSessionMatches(session) { deactivateLocal(); return }
        switch error as? UsageSyncError {
        case .signedOut, .accountChanged: signedOut()
        case .notConfigured: state = .notConfigured
        default: state = .networkError
        }
    }
}
