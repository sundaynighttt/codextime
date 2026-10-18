import Darwin
import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite(.serialized)
struct AppServerLifecycleTests {
    @Test func parsesShortResponseBeforeWriterCloses() async throws {
        let fixture = try AppServerFixture(body: """
            printf '%s\\n' '\(AppServerFixture.response)'
            /bin/sleep 4
            """)
        defer { fixture.remove() }

        let started = DispatchTime.now().uptimeNanoseconds
        let report = try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000

        #expect(report.main?.remainingPercent == 93)
        #expect(elapsed < 2, "A complete short JSON line must not wait for stdout EOF; elapsed=\(elapsed)")
        try fixture.expectReaped()
    }

    @Test func acceptsFinalResponseWithoutNewlineAtEOF() async throws {
        let fixture = try AppServerFixture(body: "printf '%s' '\(AppServerFixture.response)'")
        defer { fixture.remove() }
        let report = try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
        #expect(report.main?.remainingPercent == 93)
        try fixture.expectReaped()
    }

    @Test func rejectsEOFWithoutResponse() async throws {
        let fixture = try AppServerFixture(body: "exit 0")
        defer { fixture.remove() }
        await #expect(throws: MonitorError.invalidResponse) {
            try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
        }
        try fixture.expectReaped()
    }

    @Test func deadlineDoesNotDependOnNewlineOrEOF() async throws {
        let fixture = try AppServerFixture(body: """
            printf '{"id":2,'
            exec /bin/sleep 20
            """)
        defer { fixture.remove() }
        let started = DispatchTime.now().uptimeNanoseconds
        await #expect(throws: MonitorError.timeout) {
            try await CodexAppServerClient(explicitPath: fixture.executable.path, timeout: 0.4).fetchRateLimits()
        }
        #expect(Self.elapsed(since: started) < 1.5)
        try fixture.expectReaped()
    }

    @Test func escalatesWhenOwnedChildIgnoresSIGTERM() async throws {
        let fixture = try AppServerFixture(body: """
            trap '' TERM
            exec /bin/sleep 20
            """)
        defer { fixture.remove() }
        let started = DispatchTime.now().uptimeNanoseconds
        await #expect(throws: MonitorError.timeout) {
            try await CodexAppServerClient(explicitPath: fixture.executable.path, timeout: 0.4).fetchRateLimits()
        }
        #expect(Self.elapsed(since: started) < 1.5)
        try fixture.expectReaped()
    }

    @Test func cancellationCleansUpOwnedChild() async throws {
        let fixture = try AppServerFixture(body: "trap '' TERM\nexec /bin/sleep 20")
        defer { fixture.remove() }
        let task = Task {
            try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
        }
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: fixture.pidFile.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try fixture.expectReaped()
    }

    @Test func rejectsUnboundedLineBeforeDeadline() async throws {
        let fixture = try AppServerFixture(body: """
            /usr/bin/head -c 1052672 /dev/zero | /usr/bin/tr '\\000' x
            exec /bin/sleep 20
            """)
        defer { fixture.remove() }
        let started = DispatchTime.now().uptimeNanoseconds
        await #expect(throws: MonitorError.invalidResponse) {
            try await CodexAppServerClient(explicitPath: fixture.executable.path, timeout: 5).fetchRateLimits()
        }
        #expect(Self.elapsed(since: started) < 3)
        try fixture.expectReaped()
    }

    @Test func spawnFailureClosesDescriptors() async throws {
        let fixture = try AppServerFixture(body: "exit 0")
        defer { fixture.remove() }
        try "#!/this-interpreter-does-not-exist\n".write(to: fixture.executable, atomically: false, encoding: .utf8)
        let before = try Self.descriptorCount()
        for _ in 0..<8 {
            do {
                _ = try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
                Issue.record("Expected launch failure")
            } catch MonitorError.launchFailed { }
        }
        #expect(try Self.descriptorCount() <= before)
    }

    @Test func repeatedSuccessAndFailureLeaveNoOwnedChildOrDescriptors() async throws {
        let before = try Self.descriptorCount()
        for index in 0..<12 {
            let body = index.isMultiple(of: 2)
                ? "printf '%s\\n' '\(AppServerFixture.response)'\n/bin/sleep 0.1"
                : "exit 0"
            let fixture = try AppServerFixture(body: body)
            defer { fixture.remove() }
            do {
                _ = try await CodexAppServerClient(explicitPath: fixture.executable.path).fetchRateLimits()
                #expect(index.isMultiple(of: 2))
            } catch MonitorError.invalidResponse {
                #expect(!index.isMultiple(of: 2))
            }
            try fixture.expectReaped()
        }
        #expect(try Self.descriptorCount() <= before)
    }

    private static func elapsed(since start: UInt64) -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    private static func descriptorCount() throws -> Int {
        // /dev/fd lists only this test process's descriptors, not other processes.
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }
}

private struct AppServerFixture {
    static let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":1788283270},"secondary":null}}}"#
    let directory: URL
    let executable: URL
    let pidFile: URL

    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codextime-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        executable = directory.appendingPathComponent("fake-codex")
        pidFile = directory.appendingPathComponent("pid")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$$" > '\(pidFile.path)'
        IFS= read -r first
        IFS= read -r second
        IFS= read -r third
        \(body)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() {
        // Failure cleanup may signal only this fixture's still-unreaped child.
        if let value = try? String(contentsOf: pidFile, encoding: .utf8),
           let child = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            var status: Int32 = 0
            if waitpid(child, &status, WNOHANG) == 0 {
                _ = kill(-child, SIGKILL)
                let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
                while waitpid(child, &status, WNOHANG) == 0, DispatchTime.now().uptimeNanoseconds < deadline {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func expectReaped() throws {
        let value = try String(contentsOf: pidFile, encoding: .utf8)
        let child = try #require(pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)))
        var status: Int32 = 0
        let result = waitpid(child, &status, WNOHANG)
        let error = errno
        #expect(result == -1 && error == ECHILD, "Client must have reaped its fixture PID \(child)")
    }
}
