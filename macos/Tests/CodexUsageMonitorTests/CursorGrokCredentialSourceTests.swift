import Darwin
import Foundation
import SQLite3
import Testing
@testable import CodexUsageMonitor

private let cursorFixtureToken = "e30.eyJleHAiOjQxMDI0NDQ4MDB9.cursor-fixture-only"

@Test func cursorSourceReadsOnlyApprovedAccessTokenWithoutChangingDatabase() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.execute("INSERT INTO ItemTable VALUES ('cursorAuth/refreshToken', 'unapproved-fixture');")
    try fixture.insertToken(cursorFixtureToken)
    let before = try Data(contentsOf: fixture.url)
    let source = CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url)
    let authorization = try source.readAuthorization()
    #expect(authorization.accessToken == cursorFixtureToken)
    #expect(authorization.selectedTeamID == nil)
    #expect(try Data(contentsOf: fixture.url) == before)
    #expect(!FileManager.default.fileExists(atPath: fixture.url.path + "-wal"))
    #expect(!FileManager.default.fileExists(atPath: fixture.url.path + "-shm"))
    #expect(String(describing: authorization) == "GrokBotAuthorization(<redacted>)")
    #expect(!String(reflecting: authorization).contains(cursorFixtureToken))
    #expect(CursorGrokCredentialSource.query == "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1")
}

@Test func cursorSourceDoesNotUseOtherKeysWhenApprovedTokenIsMissing() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.execute("INSERT INTO ItemTable VALUES ('cursorAuth/refreshToken', 'other-fixture');")
    #expect(throws: ProviderUsageFailure.authenticationRequired) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
    }
}

@Test func cursorSourceRejectsInvalidTokenTypesEncodingAndHeaderCharacters() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    for value in ["''", "'has space'", "'line' || char(10) || 'break'", "'nul' || char(0) || 'byte'",
                  "CAST(x'ff' AS TEXT)", "x'66697874757265'", "42", "NULL",
                  "'\(String(repeating: "a", count: CursorGrokCredentialSource.tokenByteLimit + 1))'"] {
        try fixture.execute("DELETE FROM ItemTable;")
        try fixture.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', \(value));")
        #expect(throws: ProviderUsageFailure.authenticationRequired) {
            try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
        }
    }
}

@Test func cursorSourceMissingCorruptAndOversizedFilesFailWithoutRawMessages() throws {
    let directory = try CursorCredentialFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.vscdb")
    #expect(throws: ProviderUsageFailure.authenticationRequired) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: url).readAuthorization()
    }
    try Data("fixture-private-invalid-database".utf8).write(to: url)
    do {
        _ = try CursorGrokCredentialSource(fixtureDatabaseURL: url).readAuthorization()
        Issue.record("Expected corrupt synthetic database to fail")
    } catch {
        #expect(error is ProviderUsageFailure)
        #expect(!error.localizedDescription.contains("fixture-private"))
        #expect(!error.localizedDescription.contains(url.path))
    }
    let file = try FileHandle(forWritingTo: url)
    try file.truncate(atOffset: UInt64(CursorGrokCredentialSource.maximumDatabaseBytes + 1))
    try file.close()
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: url).readAuthorization()
    }
}

@Test func cursorSourceRejectsSymlinkAndNonRegularPaths() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.insertToken(cursorFixtureToken)
    let linked = fixture.directory.appendingPathComponent("linked.vscdb")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: fixture.url)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: linked).readAuthorization()
    }
    let pipe = fixture.directory.appendingPathComponent("pipe.vscdb")
    #expect(mkfifo(pipe.path, S_IRUSR | S_IWUSR) == 0)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: pipe).readAuthorization()
    }
    let linkedDirectory = fixture.directory.appendingPathComponent("linked-directory")
    try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: fixture.directory)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(
            fixtureDatabaseURL: linkedDirectory.appendingPathComponent("state.vscdb")).readAuthorization()
    }
}

@Test func cursorSourceRejectsSidecarSymlinksAndPartialWalBeforeSQLiteOpen() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.insertToken(cursorFixtureToken)
    let wal = URL(fileURLWithPath: fixture.url.path + "-wal")
    let shm = URL(fileURLWithPath: fixture.url.path + "-shm")
    try FileManager.default.createSymbolicLink(at: wal, withDestinationURL: fixture.url)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
    }
    try FileManager.default.removeItem(at: wal)
    try Data("fixture-wal".utf8).write(to: wal)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
    }
    #expect(!FileManager.default.fileExists(atPath: shm.path))
}

@Test func cursorSourceUsesABoundedBusyBudget() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.insertToken(cursorFixtureToken)
    var writer: OpaquePointer?
    #expect(sqlite3_open(fixture.url.path, &writer) == SQLITE_OK)
    guard let writer else { throw CursorFixtureFailure.operationFailed }
    defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil); sqlite3_close(writer) }
    #expect(sqlite3_exec(writer, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
    let start = DispatchTime.now().uptimeNanoseconds
    #expect(throws: ProviderUsageFailure.timeout) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url, timeout: 0.05).readAuthorization()
    }
    #expect(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 < 2)
}

@Test func cursorSourceRejectsViewsInsteadOfReadingAnotherTable() throws {
    let fixture = try CursorCredentialFixture()
    defer { fixture.remove() }
    try fixture.execute("DROP TABLE ItemTable; CREATE TABLE OtherTable (key TEXT, value TEXT);")
    try fixture.execute("INSERT INTO OtherTable VALUES ('cursorAuth/accessToken', 'other-fixture');")
    try fixture.execute("CREATE VIEW ItemTable AS SELECT key, value FROM OtherTable;")
    #expect(throws: ProviderUsageFailure.invalidResponse) {
        try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
    }
}

@Test func cursorSourceReadsCommittedWalWithoutChangingDatabaseOrSharedMemory() throws {
    // A separate process is essential: same-process SQLite connections can share
    // an already-writable WAL-index mapping and would not test readonly_shm.
    let fixture = try CursorWalCredentialFixture()
    defer { fixture.remove() }
    let paths = [fixture.url, URL(fileURLWithPath: fixture.url.path + "-wal"),
                 URL(fileURLWithPath: fixture.url.path + "-shm")]
    let before = try paths.map { try Data(contentsOf: $0) }
    let authorization = try CursorGrokCredentialSource(fixtureDatabaseURL: fixture.url).readAuthorization()
    #expect(authorization.accessToken == cursorFixtureToken)
    #expect(authorization.selectedTeamID == nil)
    let after = try paths.map { try Data(contentsOf: $0) }
    #expect(before == after)
}

private enum CursorFixtureFailure: Error { case operationFailed }

private struct CursorCredentialFixture {
    let directory: URL
    let url: URL
    init() throws {
        directory = try Self.makeDirectory()
        url = directory.appendingPathComponent("state.vscdb")
        do { try execute("CREATE TABLE ItemTable (key TEXT UNIQUE, value);") }
        catch { remove(); throw error }
    }
    static func makeDirectory() throws -> URL {
        // Foundation preserves macOS's /var alias even after resolvingSymlinksInPath.
        // Canonicalize the existing temporary directory with realpath so production's
        // strict no-symlink traversal remains enabled in every synthetic test.
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw CursorFixtureFailure.operationFailed
        }
        defer { free(canonical) }
        let directory = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("cursor-usage-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func insertToken(_ token: String) throws {
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(token)');")
    }
    func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw CursorFixtureFailure.operationFailed
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw CursorFixtureFailure.operationFailed
        }
    }
}

private final class CursorWalCredentialFixture {
    let directory: URL
    let url: URL
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    init() throws {
        directory = try CursorCredentialFixture.makeDirectory()
        url = directory.appendingPathComponent("state.vscdb")
        // Only a synthetic temporary DB is passed. Isolated Python ignores user
        // startup files/PYTHONPATH and keeps its writer open until stdin closes.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", "-c", """
        import sqlite3, sys
        db = sqlite3.connect(sys.argv[1])
        db.execute('CREATE TABLE ItemTable (key TEXT UNIQUE, value TEXT)')
        db.commit()
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA wal_autocheckpoint=0')
        db.execute('INSERT INTO ItemTable VALUES (?, ?)', ('cursorAuth/accessToken', sys.argv[2]))
        db.commit()
        sys.stdout.write('R')
        sys.stdout.flush()
        sys.stdin.buffer.read(1)
        db.close()
        """, url.path, cursorFixtureToken]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            // CI may cold-start the system Python shim; wait for its explicit ready byte.
            guard poll(&descriptor, 1, 15_000) > 0, descriptor.revents & Int16(POLLIN) != 0,
                  try output.fileHandleForReading.read(upToCount: 1) == Data("R".utf8) else {
                throw CursorFixtureFailure.operationFailed
            }
        } catch {
            remove()
            throw error
        }
    }
    func remove() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            while process.isRunning, DispatchTime.now().uptimeNanoseconds < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? output.fileHandleForReading.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
