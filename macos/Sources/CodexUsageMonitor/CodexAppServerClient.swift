import Darwin
import Foundation

struct CodexAppServerClient: Sendable {
    private let explicitPath: String?
    private let timeout: TimeInterval

    init(
        explicitPath: String? = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
        timeout: TimeInterval = 12
    ) {
        self.explicitPath = explicitPath
        self.timeout = timeout
    }

    func fetchRateLimits() async throws -> UsageReport {
        let task = Task.detached(priority: .utility) {
            try fetchRateLimitsBlocking()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func fetchRateLimitsBlocking() throws -> UsageReport {
        let executable = try resolveCodexPath()
        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(min(max(timeout, 0.001), 3_600) * 1_000_000_000)
        try checkRequestDeadline(deadline)
        let process = try OwnedAppServer.launch(executable: executable)
        let result = Result {
            try process.write(requestData(), deadline: deadline)
            let reader = JSONLineReader(descriptor: process.outputDescriptor, deadline: deadline)
            while let line = try reader.nextLine() {
                if let report = try RateLimitParser.parse(line: line) {
                    return report
                }
            }
            throw MonitorError.invalidResponse
        }
        // Cleanup runs even after cancellation and before a new refresh is allowed.
        guard process.finish() else {
            throw MonitorError.server("사용량 조회 프로세스 종료를 확인하지 못했습니다. 다음 조회 전에 다시 확인합니다.")
        }
        try Task.checkCancellation()
        return try result.get()
    }

    private func resolveCodexPath() throws -> String {
        let environmentPath = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            environmentPath,
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].compactMap { $0 }

        if let match = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return match
        }
        throw MonitorError.codexNotFound
    }

    private func requestData() throws -> Data {
        let requests: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-usage-monitor-macos",
                        "version": "0.1.0"
                    ]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read"]
        ]

        var data = Data()
        for request in requests {
            data.append(try JSONSerialization.data(withJSONObject: request))
            data.append(0x0A)
        }
        return data
    }
}

private final class JSONLineReader {
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
            try checkRequestDeadline(deadline)
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                return Data(line)
            }

            try waitForDescriptor(descriptor, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw MonitorError.invalidResponse
            }
            guard count > 0 else {
                if buffer.isEmpty { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= Self.maximumLineBytes else {
                throw MonitorError.invalidResponse
            }
        }
    }
}

private func checkRequestDeadline(_ deadline: UInt64) throws {
    try Task.checkCancellation()
    if DispatchTime.now().uptimeNanoseconds >= deadline {
        throw MonitorError.timeout
    }
}

private func waitForDescriptor(_ descriptor: Int32, events: Int16, deadline: UInt64) throws {
    while true {
        try checkRequestDeadline(deadline)
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { throw MonitorError.timeout }
        let remaining = deadline - now
        var item = pollfd(fd: descriptor, events: events, revents: 0)
        let milliseconds = Int32(min(max(remaining / 1_000_000, 1), 50))
        let ready = poll(&item, 1, milliseconds)
        if ready < 0 {
            if errno == EINTR { continue }
            throw MonitorError.invalidResponse
        }
        if ready > 0 {
            try checkRequestDeadline(deadline)
            if item.revents & Int16(POLLNVAL) != 0 { throw MonitorError.invalidResponse }
            // HUP still permits draining buffered bytes, followed by read == 0.
            return
        }
    }
}

/// Owns only the PID/group and descriptors created by this launch. In particular,
/// it never reaps the leader before the last group signal, so its PID cannot be
/// reused between a liveness check and SIGKILL.
private final class OwnedAppServer {
    private static let pendingLock = NSLock()
    private static var pendingChildren: [pid_t] = []
    private var pid: pid_t?
    private var inputDescriptor: Int32
    private(set) var outputDescriptor: Int32

    private init(pid: pid_t, input: Int32, output: Int32) {
        self.pid = pid
        inputDescriptor = input
        outputDescriptor = output
    }

    static func launch(executable: String) throws -> OwnedAppServer {
        // A kernel-delayed exit must not permit one new lingering child per refresh.
        pendingLock.lock()
        pendingChildren.removeAll { child in
            var status: Int32 = 0
            let result = waitpid(child, &status, WNOHANG)
            return result == child || (result < 0 && errno == ECHILD)
        }
        let cleanupPending = !pendingChildren.isEmpty
        pendingLock.unlock()
        guard !cleanupPending else {
            throw MonitorError.server("이전 사용량 조회 프로세스가 아직 종료되지 않았습니다.")
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
            guard code == 0 else { throw MonitorError.launchFailed(String(cString: strerror(code))) }
        }
        guard pipe(&input) == 0, pipe(&output) == 0 else {
            throw MonitorError.launchFailed(String(cString: strerror(errno)))
        }
        nullDescriptor = Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC)
        guard nullDescriptor >= 0 else { throw MonitorError.launchFailed(String(cString: strerror(errno))) }
        // Keep all sources above stdio so dup2 actions cannot overwrite a later
        // source, even if the launching process started with a closed stdio FD.
        func moveAboveStdio(_ descriptor: inout Int32) throws {
            if descriptor <= STDERR_FILENO {
                let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                guard replacement >= 0 else { throw MonitorError.launchFailed(String(cString: strerror(errno))) }
                Darwin.close(descriptor)
                descriptor = replacement
            }
        }
        for index in input.indices { try moveAboveStdio(&input[index]) }
        for index in output.indices { try moveAboveStdio(&output[index]) }
        try moveAboveStdio(&nullDescriptor)
        for descriptor in input + output {
            guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                throw MonitorError.launchFailed(String(cString: strerror(errno)))
            }
        }
        for descriptor in [input[1], output[0]] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw MonitorError.launchFailed(String(cString: strerror(errno)))
            }
        }
        guard fcntl(input[1], F_SETNOSIGPIPE, 1) == 0 else {
            throw MonitorError.launchFailed(String(cString: strerror(errno)))
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
        var arguments = [strdup(executable), strdup("app-server"), nil]
        defer { arguments.forEach { free($0) } }
        var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { environment.forEach { free($0) } }
        guard arguments.dropLast().allSatisfy({ $0 != nil }), environment.allSatisfy({ $0 != nil }) else {
            throw MonitorError.launchFailed(String(cString: strerror(ENOMEM)))
        }
        environment.append(nil)
        var child: pid_t = 0
        try requireSuccess(posix_spawn(&child, executable, &actions, &attributes, &arguments, &environment))
        let process = OwnedAppServer(pid: child, input: input[1], output: output[0])
        input[1] = -1
        output[0] = -1
        return process
    }

    func write(_ data: Data, deadline: UInt64) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try waitForDescriptor(inputDescriptor, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(inputDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw MonitorError.invalidResponse
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
        Self.pendingChildren.append(child)
        Self.pendingLock.unlock()
        pid = nil
        return false
    }
}
