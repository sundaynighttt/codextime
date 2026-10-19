import CoreFoundation
import Darwin
import Foundation

/// Credential access stays in this app under the user-approved provider scope.
/// Browser storage and conversation history are never used.
enum ProductionUsageProviders {
    static let clients: [any UsageProviderClient] = [
        CodexUsageProviderClient(), GrokSubscriptionUsageProviderClient(), ClaudeSubscriptionUsageProviderClient()
    ]

    static func interactiveClient(for id: ProviderID) -> any UsageProviderClient {
        switch id {
        case .codex: return CodexUsageProviderClient()
        case .grok: return GrokSubscriptionUsageProviderClient(requiresVerification: false)
        case .claude: return ClaudeSubscriptionUsageProviderClient()
        }
    }
}

enum ProviderConnectionGuidance {
    static let claudeRestrictionMessage = "Claude 구독 인증정보의 타사 앱 이용 제한으로 자동 조회가 중지되었습니다. 공식 사용량 페이지에서 확인해 주세요."
    static let claudePolicyURL = "https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use"
    static let claudeUsageURL = "https://claude.ai/settings/usage"

    static func detail(for provider: ProviderID) -> String? {
        switch provider {
        case .codex: return nil
        case .grok:
            return "승인된 Cursor 로그인 항목으로 사용량을 확인합니다. 웹 값 대조 후 자동 갱신이 시작됩니다."
        case .claude:
            return claudeRestrictionMessage
        }
    }
}

/// Uses only the approved Cursor credential source with the existing quota RPC.
/// Automatic access stays off until the quota/reset have been checked on the web.
/// The legacy Grok Bot credential source is never selected by this wrapper.
struct GrokSubscriptionUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .grok
    private let client: GrokBotUsageProviderClient
    private let requiresVerification: Bool
    private let isVerified: @Sendable () -> Bool

    init(
        credentials: any GrokBotCredentialSource = CursorGrokCredentialSource(),
        transport: any GrokBotUsageTransport = GrokBotURLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        requiresVerification: Bool = true,
        isVerified: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "grokCursorUsageVerified")
        }
    ) {
        self.client = GrokBotUsageProviderClient(credentials: credentials, transport: transport, now: now)
        self.requiresVerification = requiresVerification
        self.isVerified = isVerified
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        try Task.checkCancellation()
        guard !requiresVerification || isVerified() else {
            throw ProviderUsageFailure.notConnected
        }
        return try await client.fetchUsage()
    }
}

/// Production access is blocked independently of any legacy consent preference.
/// Provider policy does not permit this app to intermediate Claude.ai credentials.
/// The injectable signature is retained so a regression test can prove no source
/// or transport is touched, including after a previous installation opted in.
struct ClaudeSubscriptionUsageProviderClient: UsageProviderClient {
    static let connectionEnabledKey = "claudeUsageConnectionEnabled"
    let id: ProviderID = .claude

    init(
        credentials: any ClaudeUsageCredentialSource = ClaudeUsageKeychainSource(),
        transport: any ClaudeUsageTransport = ClaudeUsageEphemeralTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        isConnectionEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "claudeUsageConnectionEnabled")
        }
    ) {}

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        try Task.checkCancellation()
        throw ProviderUsageFailure.unsupported
    }
}

struct ClaudeUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .claude
    private let explicitPath: String?
    private let timeout: TimeInterval

    init(explicitPath: String? = nil, timeout: TimeInterval = 6) {
        self.explicitPath = explicitPath
        self.timeout = timeout
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let executable = try ProviderExecutable.resolve(explicitPath: explicitPath, candidates: [
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        ])
        let data = try await ProviderCLITransport.capture(
            executable: executable, arguments: ["auth", "status", "--json"], timeout: timeout)
        try ClaudeAuthenticationParser.requireSupportedQuotaConnection(data: data)
        // Intentionally unreachable: authentication status is never quota evidence.
        throw ProviderUsageFailure.unsupported
    }
}

enum ClaudeAuthenticationParser {
    static func requireSupportedQuotaConnection(data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object["loggedIn"] as? NSNumber,
              CFGetTypeID(loggedIn) == CFBooleanGetTypeID()
        else { throw ProviderUsageFailure.invalidResponse }
        guard loggedIn.boolValue else { throw ProviderUsageFailure.authenticationRequired }
        // There is no documented noninteractive quota subcommand. Do not turn
        // /usage into a print-mode model request, import OAuth, or start a TUI.
        throw ProviderUsageFailure.unsupported
    }
}

/// Official Grok Build CLI only. Grok Bot's desktop subscription is a different
/// product and is not inferred from this CLI or from API monetary spending.
struct GrokUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .grok
    private let explicitPath: String?
    private let timeout: TimeInterval
    private let allowGrokBuildCLI: Bool

    init(explicitPath: String? = nil, timeout: TimeInterval = 12, allowGrokBuildCLI: Bool = false) {
        self.explicitPath = explicitPath
        self.timeout = timeout
        self.allowGrokBuildCLI = allowGrokBuildCLI
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        // Grok Bot's meter depends on the account's plan. Discovering a Build
        // CLI does not verify that its pool matches this desktop subscription.
        // Opt-in is code-level only; no environment variable silently enables it.
        guard allowGrokBuildCLI else { throw ProviderUsageFailure.notConnected }
        let executable: String
        do {
            executable = try ProviderExecutable.resolve(explicitPath: explicitPath, candidates: [
                "/opt/homebrew/bin/grok", "/usr/local/bin/grok",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/grok").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bin/grok").path
            ])
        } catch ProviderUsageFailure.notInstalled {
            // An installed Grok Bot app does not imply a Grok Build CLI login.
            throw ProviderUsageFailure.notConnected
        }
        return try await ProviderCLITransport.grokBilling(executable: executable, timeout: timeout)
    }
}

enum ProviderExecutable {
    static func resolve(explicitPath: String?, candidates: [String]) throws -> String {
        if let explicitPath {
            guard !explicitPath.isEmpty, FileManager.default.isExecutableFile(atPath: explicitPath) else {
                throw ProviderUsageFailure.notInstalled
            }
            return explicitPath
        }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ProviderUsageFailure.notInstalled
        }
        return path
    }
}

/// Protocol shape checked against xai-org/grok-build's billing.rs and the
/// CodexBar Grok documentation. This is an independent parser, not copied code.
/// Only explicit included-credit quota is accepted; API spend/on-demand caps,
/// balances, session tokens and missing percentages never become a quota.
enum GrokBillingParser {
    static func parse(line: Data) throws -> ProviderUsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ProviderUsageFailure.invalidResponse
        }
        guard integer(object["id"]) == 2 else { return nil }
        if let error = object["error"] as? [String: Any] {
            throw failure(for: error)
        }
        guard let result = object["result"] as? [String: Any] else {
            throw ProviderUsageFailure.invalidResponse
        }
        let used: Double
        let period: [String: Any]?
        let label: String
        let config = result["config"] as? [String: Any]
        if let config, let percent = number(config["creditUsagePercent"]) {
            used = percent
            period = config["currentPeriod"] as? [String: Any]
            switch period?["type"] as? String {
            case "USAGE_PERIOD_TYPE_WEEKLY": label = "주간 구독 크레딧"
            case "USAGE_PERIOD_TYPE_MONTHLY": label = "월간 구독 크레딧"
            default: label = "구독 크레딧"
            }
        } else {
            guard let limit = cents(result["monthlyLimit"]), limit > 0,
                  let usage = result["usage"] as? [String: Any],
                  let includedUsed = cents(usage["includedUsed"])
            else { throw ProviderUsageFailure.invalidResponse }
            used = includedUsed / limit * 100
            period = result["billingCycle"] as? [String: Any]
            label = "월간 포함 크레딧"
        }
        guard used.isFinite, (0...100).contains(used) else {
            throw ProviderUsageFailure.invalidResponse
        }
        let start = date(period?["start"] ?? period?["billingPeriodStart"])
        let end = date(period?["end"] ?? period?["billingPeriodEnd"])
            ?? date(config?["billingPeriodEnd"])
        let duration: Int?
        if let start, let end, end > start, end.timeIntervalSince(start) < 366 * 86_400 {
            duration = Int(end.timeIntervalSince(start) / 60)
        } else { duration = nil }
        let rawPlan = result["subscription_tier"] as? String ?? result["subscriptionTier"] as? String
        let plan = ["SuperGrok", "SuperGrok Heavy"].contains(rawPlan ?? "") ? rawPlan : nil
        return ProviderUsageSnapshot(provider: .grok, windows: [
            ProviderUsageWindow(id: "included-credits", label: label, remainingPercent: 100 - used,
                                resetDate: end, durationMinutes: duration)
        ], planName: plan)
    }

    static func failure(for error: [String: Any]) -> ProviderUsageFailure {
        if integer(error["code"]) == -32601 { return .unsupported }
        // Inspect only to classify; the remote message is never returned or logged.
        let message = (error["message"] as? String)?.lowercased() ?? ""
        if message.contains("authentication required") || message.contains("not authenticated") {
            return .authenticationRequired
        }
        return .queryFailed
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.rounded() == number,
              number >= Double(Int32.min), number <= Double(Int32.max) else { return nil }
        return Int(number)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func cents(_ value: Any?) -> Double? {
        guard let value = value as? [String: Any], let number = number(value["val"]), number >= 0 else { return nil }
        return number
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

private enum ProviderCLITransport {
    static func capture(executable: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await detached {
            try run(executable: executable, arguments: arguments, timeout: timeout) { child, reader, _ in
                child.closeInput()
                var data = Data()
                while let line = try reader.nextLine() {
                    data.append(line)
                    data.append(0x0A)
                    guard data.count <= 1_048_576 else { throw ProviderUsageFailure.invalidResponse }
                }
                return data
            }
        }
    }

    static func grokBilling(executable: String, timeout: TimeInterval) async throws -> ProviderUsageSnapshot {
        try await detached {
            try run(executable: executable, arguments: ["agent", "stdio"], timeout: timeout) { child, reader, deadline in
                try child.write(request(id: 1, method: "initialize", params: [
                    "protocolVersion": "1",
                    "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false]
                ]), deadline: deadline)
                var initialized = false
                while let line = try reader.nextLine() {
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        throw ProviderUsageFailure.invalidResponse
                    }
                    if (object["id"] as? Int) == 1 {
                        if let error = object["error"] as? [String: Any] { throw GrokBillingParser.failure(for: error) }
                        guard object["result"] is [String: Any] else { throw ProviderUsageFailure.invalidResponse }
                        guard !initialized else { continue }
                        initialized = true
                        try child.write(request(id: 2, method: "x.ai/billing"), deadline: deadline)
                        continue
                    }
                    if initialized, let usage = try GrokBillingParser.parse(line: line) { return usage }
                }
                throw ProviderUsageFailure.invalidResponse
            }
        }
    }

    private static func detached<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func run<T>(executable: String, arguments: [String], timeout: TimeInterval,
                               body: (OwnedProviderCLI, ProviderJSONLineReader, UInt64) throws -> T) throws -> T {
        let bounded = timeout.isFinite ? min(max(timeout, 0.001), 3_600) : 12
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(bounded * 1_000_000_000)
        try checkProviderDeadline(deadline)
        let child = try OwnedProviderCLI.launch(executable: executable, arguments: arguments)
        let result = Result { try body(child, ProviderJSONLineReader(descriptor: child.outputDescriptor,
                                                                    deadline: deadline), deadline) }
        guard child.finish() else { throw ProviderUsageFailure.queryFailed }
        try Task.checkCancellation()
        return try result.get()
    }

    private static func request(id: Int, method: String, params: [String: Any]? = nil) throws -> Data {
        var value: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { value["params"] = params }
        // Grok's ACP method matcher requires literal '/'.
        var data = try JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

private final class ProviderJSONLineReader {
    private let descriptor: Int32
    private let deadline: UInt64
    private var buffer = Data()
    private static let maximumLineBytes = 1_048_576

    init(descriptor: Int32, deadline: UInt64) {
        self.descriptor = descriptor
        self.deadline = deadline
    }

    func nextLine() throws -> Data? {
        while true {
            try checkProviderDeadline(deadline)
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                return Data(line)
            }

            try waitForProviderDescriptor(descriptor, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw ProviderUsageFailure.invalidResponse
            }
            guard count > 0 else {
                if buffer.isEmpty { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= Self.maximumLineBytes else {
                throw ProviderUsageFailure.invalidResponse
            }
        }
    }
}

private func checkProviderDeadline(_ deadline: UInt64) throws {
    try Task.checkCancellation()
    if DispatchTime.now().uptimeNanoseconds >= deadline {
        throw ProviderUsageFailure.timeout
    }
}

private func waitForProviderDescriptor(_ descriptor: Int32, events: Int16, deadline: UInt64) throws {
    while true {
        try checkProviderDeadline(deadline)
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { throw ProviderUsageFailure.timeout }
        let remaining = deadline - now
        var item = pollfd(fd: descriptor, events: events, revents: 0)
        let milliseconds = Int32(min(max(remaining / 1_000_000, 1), 50))
        let ready = poll(&item, 1, milliseconds)
        if ready < 0 {
            if errno == EINTR { continue }
            throw ProviderUsageFailure.invalidResponse
        }
        if ready > 0 {
            try checkProviderDeadline(deadline)
            if item.revents & Int16(POLLNVAL) != 0 { throw ProviderUsageFailure.invalidResponse }
            // HUP still permits draining buffered bytes, followed by read == 0.
            return
        }
    }
}

/// Owns only the PID/group and descriptors created by this launch. In particular,
/// it never reaps the leader before the last group signal, so its PID cannot be
/// reused between a liveness check and SIGKILL.
private final class OwnedProviderCLI {
    private static let pendingLock = NSLock()
    private static var pendingChildren: [String: [pid_t]] = [:]
    private var pid: pid_t?
    private let ownerKey: String
    private var inputDescriptor: Int32
    private(set) var outputDescriptor: Int32

    private init(pid: pid_t, input: Int32, output: Int32, ownerKey: String) {
        self.pid = pid
        self.ownerKey = ownerKey
        inputDescriptor = input
        outputDescriptor = output
    }

    static func launch(executable: String, arguments: [String]) throws -> OwnedProviderCLI {
        // A kernel-delayed exit must not permit one new lingering child per refresh.
        pendingLock.lock()
        var previousChildren = pendingChildren[executable] ?? []
        previousChildren.removeAll { child in
            var status: Int32 = 0
            let result = waitpid(child, &status, WNOHANG)
            return result == child || (result < 0 && errno == ECHILD)
        }
        pendingChildren[executable] = previousChildren.isEmpty ? nil : previousChildren
        let cleanupPending = !previousChildren.isEmpty
        pendingLock.unlock()
        guard !cleanupPending else {
            throw ProviderUsageFailure.queryFailed
        }

        var input = [Int32](repeating: -1, count: 2)
        var output = [Int32](repeating: -1, count: 2)
        var nullDescriptor: Int32 = -1
        defer {
            for descriptor in input + output + [nullDescriptor] where descriptor >= 0 {
                Darwin.close(descriptor)
            }
        }
        func requireSuccess(_ code: Int32) throws {
            guard code == 0 else { throw ProviderUsageFailure.queryFailed }
        }
        guard pipe(&input) == 0, pipe(&output) == 0 else {
            throw ProviderUsageFailure.queryFailed
        }
        nullDescriptor = Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC)
        guard nullDescriptor >= 0 else { throw ProviderUsageFailure.queryFailed }
        // Keep all sources above stdio so dup2 actions cannot overwrite a later
        // source, even if the launching process started with a closed stdio FD.
        func moveAboveStdio(_ descriptor: inout Int32) throws {
            if descriptor <= STDERR_FILENO {
                let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                guard replacement >= 0 else { throw ProviderUsageFailure.queryFailed }
                Darwin.close(descriptor)
                descriptor = replacement
            }
        }
        for index in input.indices { try moveAboveStdio(&input[index]) }
        for index in output.indices { try moveAboveStdio(&output[index]) }
        try moveAboveStdio(&nullDescriptor)
        for descriptor in input + output {
            guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                throw ProviderUsageFailure.queryFailed
            }
        }
        for descriptor in [input[1], output[0]] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw ProviderUsageFailure.queryFailed
            }
        }
        guard fcntl(input[1], F_SETNOSIGPIPE, 1) == 0 else {
            throw ProviderUsageFailure.queryFailed
        }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try requireSuccess(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try requireSuccess(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try requireSuccess(posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO))
        try requireSuccess(posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO))
        try requireSuccess(posix_spawn_file_actions_adddup2(&actions, nullDescriptor, STDERR_FILENO))
        for descriptor in input + output + [nullDescriptor] where descriptor > STDERR_FILENO {
            try requireSuccess(posix_spawn_file_actions_addclose(&actions, descriptor))
        }
        try requireSuccess(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try requireSuccess(posix_spawnattr_setpgroup(&attributes, 0))
        var argv = ([executable] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { environment.forEach { free($0) } }
        guard argv.allSatisfy({ $0 != nil }), environment.allSatisfy({ $0 != nil }) else {
            throw ProviderUsageFailure.queryFailed
        }
        argv.append(nil)
        environment.append(nil)
        var child: pid_t = 0
        try requireSuccess(posix_spawn(&child, executable, &actions, &attributes, &argv, &environment))
        let process = OwnedProviderCLI(pid: child, input: input[1], output: output[0], ownerKey: executable)
        input[1] = -1
        output[0] = -1
        return process
    }

    func closeInput() {
        guard inputDescriptor >= 0 else { return }
        Darwin.close(inputDescriptor)
        inputDescriptor = -1
    }

    func write(_ data: Data, deadline: UInt64) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try waitForProviderDescriptor(inputDescriptor, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(inputDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw ProviderUsageFailure.invalidResponse
                }
                offset += count
            }
        }
    }

    func finish() -> Bool {
        for descriptor in [inputDescriptor, outputDescriptor] where descriptor >= 0 { Darwin.close(descriptor) }
        inputDescriptor = -1
        outputDescriptor = -1
        guard let child = pid else { return true }

        // No waitpid/reaping occurs until both signals are finished. WNOWAIT lets
        // a normally exiting child skip the grace period without releasing PID ownership.
        enum State { case running, exited, ownershipLost }
        func state() -> State {
            var info = siginfo_t()
            let result = waitid(P_PID, id_t(child), &info, WEXITED | WNOHANG | WNOWAIT)
            if result < 0 && errno == ECHILD { return .ownershipLost }
            return result == 0 && info.si_pid == child ? .exited : .running
        }
        guard state() != .ownershipLost else {
            pid = nil
            return false
        }
        _ = kill(-child, SIGTERM)
        let grace = DispatchTime.now().uptimeNanoseconds + 100_000_000
        while state() == .running, DispatchTime.now().uptimeNanoseconds < grace {
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard state() != .ownershipLost else {
            pid = nil
            return false
        }
        _ = kill(-child, SIGKILL)
        let reapDeadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
        repeat {
            var status: Int32 = 0
            let result = waitpid(child, &status, WNOHANG)
            if result == child || (result < 0 && errno == ECHILD) {
                pid = nil
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        } while DispatchTime.now().uptimeNanoseconds < reapDeadline

        // Do not block a utility thread forever on an uninterruptible OS wait.
        // Keep ownership and retry reaping before any later launch instead.
        Self.pendingLock.lock()
        Self.pendingChildren[ownerKey, default: []].append(child)
        Self.pendingLock.unlock()
        pid = nil
        return false
    }
}
