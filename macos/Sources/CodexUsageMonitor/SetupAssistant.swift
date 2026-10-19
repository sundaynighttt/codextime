import Darwin
import Foundation

/// Login is performed by the provider's own CLI. The monitor never parses its
/// output, handles an OAuth callback, or stores an additional credential.
enum SetupCLI {
    static func resolve(_ id: ProviderID, explicitPath: String? = nil,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        let name = id == .codex ? "codex" : "claude"
        var paths = [explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines)]
        if id == .codex {
            paths += ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                      "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                      "/Applications/ChatGPT.app/Contents/Resources/codex",
                      "/Applications/Codex.app/Contents/Resources/codex"]
        }
        paths += [home.appendingPathComponent(".local/bin/\(name)").path,
                  "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        // Finder-launched apps do not inherit a shell's nvm configuration.
        let versions = home.appendingPathComponent(".nvm/versions/node")
        let nodes = (try? FileManager.default.contentsOfDirectory(at: versions,
            includingPropertiesForKeys: nil)) ?? []
        paths += nodes.sorted { $0.lastPathComponent.compare($1.lastPathComponent,
            options: .numeric) == .orderedDescending }.map { $0.appendingPathComponent("bin/\(name)").path }
        guard id != .grok, let path = paths.compactMap({ $0 }).first(where: {
            !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw ProviderUsageFailure.notInstalled }
        return path
    }

    static func loginArguments(for id: ProviderID) -> [String] {
        id == .claude ? ["auth", "login", "--claudeai"] : ["login"]
    }
}

enum SetupConsent {
    static func isGranted(_ id: ProviderID, in defaults: UserDefaults = .standard) -> Bool {
        if id == .codex { return true }
        if let granted = defaults.object(forKey: key(id)) as? Bool { return granted }
        // Successful connections in older releases already included this consent.
        let legacy = id == .claude ? "claudeUsageConnectionEnabled" : "grokCursorUsageVerified"
        return defaults.bool(forKey: legacy)
    }

    static func setGranted(_ granted: Bool, for id: ProviderID, in defaults: UserDefaults = .standard) {
        defaults.set(granted, forKey: key(id))
    }

    private static func key(_ id: ProviderID) -> String { "usageConnectionConsent.\(id.rawValue)" }
}

struct SetupRowPresentation {
    let connected: Bool
    let guidance: String
    let loginTitle: String
    let showLogin: Bool
    let connectTitle: String

    init(state: ProviderUsageState, awaitingGrokConfirmation: Bool, dependencyInstalled: Bool = true) {
        connected = state.snapshot != nil && state.failure == nil
            && !state.connectionIsPending && !awaitingGrokConfirmation
        showLogin = !connected && !awaitingGrokConfirmation
        loginTitle = !dependencyInstalled || state.failure == .notInstalled ? "설치 안내" : "로그인하기"
        connectTitle = connected ? "새로고침" : "기존 계정 연결"
        if awaitingGrokConfirmation {
            guidance = "웹의 사용률과 리셋 시각을 확인한 뒤 아래 버튼을 눌러 완료하세요. 정수 표시 방식 때문에 1% 차이가 날 수 있습니다."
        } else if connected {
            guidance = "연결 완료 · 10분마다 자동 갱신합니다. 이 Mac에서는 다음 실행에도 설정이 유지됩니다."
        } else if !dependencyInstalled {
            guidance = "공식 앱 또는 CLI 설치가 필요합니다. ‘설치 안내’를 눌러 설치한 뒤 ‘기존 계정 연결’을 눌러 주세요."
        } else if state.failure == .authenticationRequired {
            guidance = "로그인이 없거나 만료됐습니다. ‘로그인하기’를 누르면 공식 로그인 절차가 열리고, 완료 후 연결을 다시 확인합니다."
        } else if state.failure == .notInstalled {
            guidance = "공식 앱 또는 CLI 설치가 필요합니다. 설치 안내에 따라 설치한 뒤 ‘기존 계정 연결’을 눌러 주세요."
        } else if state.failure == .permissionDenied || state.failure == .permissionRequired {
            guidance = "‘기존 계정 연결’을 누른 뒤 macOS 권한창에서 접근을 허용해 주세요."
        } else if let error = state.error, state.failure != .notConnected {
            guidance = error + " ‘기존 계정 연결’로 다시 확인할 수 있습니다."
        } else {
            guidance = state.id == .grok
                ? "Cursor의 기존 계정을 연결합니다. 처음 한 번 Grok 웹 사용량과 대조하면 설정이 끝납니다."
                : "이미 로그인했다면 ‘기존 계정 연결’을 누르세요. 처음이라면 ‘로그인하기’부터 시작하세요."
        }
    }
}

enum SetupLoginFailure: Error {
    case failed, cancelled, timedOut

    var message: String {
        switch self {
        case .failed: return "로그인이 완료되지 않았습니다. 다시 시도하거나 공식 설치 안내를 확인해 주세요."
        case .cancelled: return "로그인을 취소했습니다. 필요할 때 다시 시작할 수 있습니다."
        case .timedOut: return "로그인 대기 시간이 지났습니다. ‘로그인하기’를 눌러 다시 시작해 주세요."
        }
    }
}

/// Owns one bounded login child. No shell interpolation, console capture, or
/// automatic credential renewal is involved. Only an explicit login click starts it.
@MainActor
final class SetupLoginController {
    private var process: Process?
    private var timer: Task<Void, Never>?
    private var completion: ((Result<Void, SetupLoginFailure>) -> Void)?
    private var forcedFailure: SetupLoginFailure?
    var isRunning: Bool { process != nil }

    func start(executable: String, arguments: [String], timeout: TimeInterval = 600,
               completion: @escaping (Result<Void, SetupLoginFailure>) -> Void) throws {
        guard process == nil else { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        environment["PATH"] = [directory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
            environment["PATH"] ?? ""].joined(separator: ":")
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in self?.finish(child) }
        }
        process = child
        self.completion = completion
        forcedFailure = nil
        do { try child.run() } catch {
            child.terminationHandler = nil
            process = nil
            self.completion = nil
            throw error
        }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(max(timeout, 0.01), 600) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop(with: .timedOut)
        }
    }

    func cancel() { stop(with: .cancelled) }

    func shutdown() async {
        cancel()
        while process != nil { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    private func stop(with failure: SetupLoginFailure) {
        guard let child = process else { return }
        forcedFailure = failure
        guard child.isRunning else { return }
        child.terminate()
        // Some CLIs ignore SIGTERM while waiting for browser authorization.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.process === child, child.isRunning else { return }
            kill(child.processIdentifier, SIGKILL)
        }
    }

    private func finish(_ child: Process) {
        guard process === child else { return }
        timer?.cancel()
        timer = nil
        process = nil
        let callback = completion
        completion = nil
        let failure = forcedFailure
        forcedFailure = nil
        if let failure { callback?(.failure(failure)) }
        else if child.terminationReason == .exit && child.terminationStatus == 0 { callback?(.success(())) }
        else { callback?(.failure(.failed)) }
    }
}
