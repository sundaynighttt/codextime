import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppModel {
    enum State {
        case checking
        case signedOut
        case signingIn(DeviceAuthorization)
        case connected(UsageSnapshot)
        case failed(String)
    }

    private(set) var state: State = .checking
    private(set) var isRefreshing = false

    private let client: CodexAccountClient
    private let usageStore: SharedUsageStore
    private var signInTask: Task<Void, Never>?

    init(
        client: CodexAccountClient = CodexAccountClient(),
        usageStore: SharedUsageStore = SharedUsageStore()
    ) {
        self.client = client
        self.usageStore = usageStore
    }

    func load() async {
        guard await client.isAuthenticated() else {
            state = .signedOut
            return
        }

        if let cached = usageStore.load() {
            state = .connected(cached)
        }
        await refresh()
    }

    func beginSignIn() {
        signInTask?.cancel()
        state = .checking
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authorization = try await client.requestDeviceAuthorization()
                guard !Task.isCancelled else { return }
                state = .signingIn(authorization)

                let snapshot = try await client.completeDeviceAuthorization(authorization)
                guard !Task.isCancelled else { return }
                state = .connected(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
            } catch is CancellationError {
                state = .signedOut
            } catch {
                guard !Task.isCancelled else {
                    state = .signedOut
                    return
                }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func beginDemo() {
        guard case .signedOut = state else { return }
        state = .connected(usageStore.startDemo())
        WidgetCenter.shared.reloadAllTimelines()
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        state = .signedOut
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await client.fetchUsage()
            state = .connected(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch CodexClientError.notAuthenticated {
            state = .signedOut
        } catch CodexClientError.loginExpired {
            try? await client.signOut()
            state = .signedOut
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if usageStore.load() == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func signOut() async {
        signInTask?.cancel()
        do {
            try await client.signOut()
            state = .signedOut
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
