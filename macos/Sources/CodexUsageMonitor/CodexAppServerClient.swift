import Foundation

struct CodexAppServerClient: Sendable {
    private let explicitPath: String?

    init(explicitPath: String? = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]) {
        self.explicitPath = explicitPath
    }

    func fetchRateLimits() async throws -> UsageReport {
        try await Task.detached(priority: .utility) {
            try fetchRateLimitsBlocking()
        }.value
    }

    private func fetchRateLimitsBlocking() throws -> UsageReport {
        let executable = try resolveCodexPath()
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw MonitorError.launchFailed(error.localizedDescription)
        }

        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: timeout)

        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try writeRequests(to: input.fileHandleForWriting)
        let reader = JSONLineReader(handle: output.fileHandleForReading)

        while let line = try reader.nextLine() {
            if let report = try RateLimitParser.parse(line: line) {
                return report
            }
        }

        if process.terminationReason == .uncaughtSignal {
            throw MonitorError.timeout
        }
        throw MonitorError.invalidResponse
    }

    private func resolveCodexPath() throws -> String {
        let environmentPath = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            environmentPath,
            "/Applications/ChatGPT.app/Contents/Resources/codex",
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

    private func writeRequests(to handle: FileHandle) throws {
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

        for request in requests {
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
    }
}

private final class JSONLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func nextLine() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                return Data(line)
            }

            guard let chunk = try handle.read(upToCount: 4_096), !chunk.isEmpty else {
                if buffer.isEmpty { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(chunk)
        }
    }
}
