import Foundation
import Testing
@testable import CodexUsageMonitor

@Test func setupExplainsExpiredLoginAndOffersRecovery() {
    var state = ProviderUsageState(id: .claude)
    state.failure = .authenticationRequired
    let row = SetupRowPresentation(state: state, awaitingGrokConfirmation: false)
    #expect(!row.connected)
    #expect(row.showLogin)
    #expect(row.loginTitle == "로그인하기")
    #expect(row.guidance.contains("만료"))
    #expect(row.guidance.contains("완료 후"))
}

@Test func codexLoginErrorsOfferRecoveryWithoutDisplayingServerText() {
    for message in ["Authentication required", "Not logged in. Please log in.", "Unauthorized"] {
        #expect(CodexUsageProviderClient.failure(for: .server(message)) == .authenticationRequired)
    }
    #expect(CodexUsageProviderClient.failure(for: .server("private server detail")) == .queryFailed)
    #expect(CodexUsageProviderClient.failure(for: .timeout) == .timeout)
}

@Test func connectedSetupDoesNotTellUserToReinstallOrLogInDuringRefresh() {
    var state = ProviderUsageState(id: .claude)
    state.snapshot = ProviderUsageSnapshot(provider: .claude,
        windows: [ProviderUsageWindow(id: "short", label: "단기", remainingPercent: 52)])
    state.isRefreshing = true
    let row = SetupRowPresentation(state: state, awaitingGrokConfirmation: false)
    #expect(row.connected)
    #expect(!row.showLogin)
    #expect(row.connectTitle == "새로고침")
    #expect(row.guidance.contains("다음 실행에도"))
    #expect(!row.guidance.contains("설치"))
}

@Test func grokSetupIsIncompleteUntilWebComparison() {
    var state = ProviderUsageState(id: .grok)
    state.snapshot = ProviderUsageSnapshot(provider: .grok,
        windows: [ProviderUsageWindow(id: "weekly", label: "주간", remainingPercent: 51.9)])
    let pending = SetupRowPresentation(state: state, awaitingGrokConfirmation: true)
    #expect(!pending.connected)
    #expect(!pending.showLogin)
    #expect(pending.guidance.contains("리셋"))
    state.isRefreshing = true
    #expect(!SetupRowPresentation(state: state, awaitingGrokConfirmation: true).connected)
    #expect(SetupRowPresentation(state: state, awaitingGrokConfirmation: false).connected)
}

@Test func setupDetectsMissingToolsBeforeOfferingLogin() {
    let row = SetupRowPresentation(state: ProviderUsageState(id: .claude),
        awaitingGrokConfirmation: false, dependencyInstalled: false)
    #expect(row.showLogin)
    #expect(row.loginTitle == "설치 안내")
    #expect(row.guidance.contains("설치가 필요"))
}

@Test func setupConsentMigratesAndCanBeExplicitlyRevoked() throws {
    let suite = "CodexTimeSetupTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!SetupConsent.isGranted(.claude, in: defaults))
    defaults.set(true, forKey: "claudeUsageConnectionEnabled")
    #expect(SetupConsent.isGranted(.claude, in: defaults))
    SetupConsent.setGranted(true, for: .claude, in: defaults)
    defaults.set(false, forKey: "claudeUsageConnectionEnabled")
    #expect(SetupConsent.isGranted(.claude, in: defaults))
    defaults.set(true, forKey: "claudeUsageConnectionEnabled")
    SetupConsent.setGranted(false, for: .claude, in: defaults)
    #expect(!SetupConsent.isGranted(.claude, in: defaults))
    #expect(!SetupConsent.isGranted(.grok, in: defaults))
}

@Test @MainActor func setupLoginUsesExactArgumentsWithoutShellInterpolation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("setup test ' $(false) \(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("login")
    try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.args\"\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    #expect(try SetupCLI.resolve(.claude, explicitPath: executable.path) == executable.path)
    let controller = SetupLoginController()
    let result: Result<Void, SetupLoginFailure> = await withCheckedContinuation { continuation in
        do {
            try controller.start(executable: executable.path, arguments: SetupCLI.loginArguments(for: .claude)) {
                continuation.resume(returning: $0)
            }
        } catch { continuation.resume(returning: .failure(.failed)) }
    }
    try result.get()
    #expect(!controller.isRunning)
    #expect(try String(contentsOfFile: executable.path + ".args", encoding: .utf8) == "auth\nlogin\n--claudeai\n")
    #expect(SetupCLI.loginArguments(for: .codex) == ["login"])
}

@Test @MainActor func setupLoginCancellationReleasesItsOwnedProcess() async throws {
    let controller = SetupLoginController()
    let result: Result<Void, SetupLoginFailure> = await withCheckedContinuation { continuation in
        do {
            try controller.start(executable: "/bin/sleep", arguments: ["30"]) {
                continuation.resume(returning: $0)
            }
            controller.cancel()
        } catch { continuation.resume(returning: .failure(.failed)) }
    }
    guard case .failure(.cancelled) = result else { Issue.record("Expected cancellation"); return }
    #expect(!controller.isRunning)
}

@Test @MainActor func setupLoginTimeoutReapsTERMResistantChild() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("setup-timeout-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("login")
    try Data("#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let controller = SetupLoginController()
    let start = Date()
    let result: Result<Void, SetupLoginFailure> = await withCheckedContinuation { continuation in
        do {
            try controller.start(executable: executable.path, arguments: [], timeout: 0.1) {
                continuation.resume(returning: $0)
            }
        } catch { continuation.resume(returning: .failure(.failed)) }
    }
    guard case .failure(.timedOut) = result else { Issue.record("Expected timeout"); return }
    #expect(!controller.isRunning)
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test @MainActor func setupLoginLaunchFailureAllowsRetry() async throws {
    let controller = SetupLoginController()
    do {
        try controller.start(executable: "/nonexistent/\(UUID())", arguments: []) { _ in }
        Issue.record("Missing login executable must fail")
    } catch {}
    #expect(!controller.isRunning)
    let result: Result<Void, SetupLoginFailure> = await withCheckedContinuation { continuation in
        do {
            try controller.start(executable: "/usr/bin/false", arguments: []) {
                continuation.resume(returning: $0)
            }
        } catch { continuation.resume(returning: .failure(.cancelled)) }
    }
    guard case .failure(.failed) = result else { Issue.record("Expected a sanitized login failure"); return }
    #expect(!controller.isRunning)
}
