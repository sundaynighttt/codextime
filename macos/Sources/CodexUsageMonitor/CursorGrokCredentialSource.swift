import Darwin
import Foundation
import SQLite3

/// The only production path and SQL statement approved for Cursor-backed usage.
/// Construction does not touch storage. The app's owned provider worker performs
/// the read; no CLI, Keychain, cookie, refresh token, or other DB key is consulted.
struct CursorGrokCredentialSource: GrokBotCredentialSource {
    static let tokenKey = "cursorAuth/accessToken"
    static let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
    static let tokenByteLimit = 32_768
    static let maximumDatabaseBytes: Int64 = 512 * 1_024 * 1_024
    private let databaseURL: URL
    private let timeout: TimeInterval

    init() {
        databaseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        timeout = 2
    }

    /// Internal injection for synthetic databases only; production uses init().
    init(fixtureDatabaseURL: URL, timeout: TimeInterval = 2) {
        databaseURL = fixtureDatabaseURL
        self.timeout = timeout.isFinite ? min(max(timeout, 0.001), 2) : 2
    }

    func readAuthorization() throws -> GrokBotAuthorization {
        try Task.checkCancellation()
        guard databaseURL.isFileURL, !databaseURL.path.utf8.contains(0),
              sqlite3_libversion_number() >= 3_039_000, sqlite3_vfs_find("unix") != nil else {
            throw ProviderUsageFailure.unsupported
        }
        let directory = try Self.openDirectoryWithoutSymlinks(databaseURL.deletingLastPathComponent().path)
        defer { close(directory) }
        let name = databaseURL.lastPathComponent
        let database = try Self.openExistingFile(directory: directory, name: name,
            maximumBytes: Self.maximumDatabaseBytes, required: true)
        defer { if let database { close(database.descriptor) } }
        guard let database, database.size > 0 else { throw ProviderUsageFailure.authenticationRequired }
        let wal = try Self.openExistingFile(directory: directory, name: name + "-wal",
            maximumBytes: 256 * 1_024 * 1_024, required: false)
        defer { if let wal { close(wal.descriptor) } }
        let sharedMemory = try Self.openExistingFile(directory: directory, name: name + "-shm",
            maximumBytes: 8 * 1_024 * 1_024, required: false)
        defer { if let sharedMemory { close(sharedMemory.descriptor) } }
        // A partial WAL pair must fail before SQLite can create a missing sidecar.
        guard (wal == nil) == (sharedMemory == nil) else { throw ProviderUsageFailure.unsupported }

        var components = URLComponents(url: databaseURL, resolvingAgainstBaseURL: false)
        // Unix VFS's readonly_shm keeps WAL-index opens/mappings read-only too.
        // It is implementation-specific: the synthetic WAL tests must validate
        // the linked system SQLite before this integration is released. Never
        // replace it with immutable/nolock or a DB/WAL copy: those can lose WAL.
        components?.queryItems = [URLQueryItem(name: "mode", value: "ro"),
                                  URLQueryItem(name: "readonly_shm", value: "1")]
        guard let uri = components?.string else { throw ProviderUsageFailure.invalidResponse }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE
            | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_URI
        let opened = sqlite3_open_v2(uri, &handle, flags, "unix")
        guard opened == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw Self.failure(for: opened)
        }
        defer {
            sqlite3_progress_handler(handle, 0, nil, nil)
            sqlite3_busy_handler(handle, nil, nil)
            sqlite3_set_authorizer(handle, nil, nil)
            sqlite3_close(handle)
        }
        guard sqlite3_db_readonly(handle, "main") == 1 else { throw ProviderUsageFailure.unsupported }
        try Self.requireSameFile(database, directory: directory, name: name)
        if let wal { try Self.requireSameFile(wal, directory: directory, name: name + "-wal") }
        if let sharedMemory {
            try Self.requireSameFile(sharedMemory, directory: directory, name: name + "-shm")
        }
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 65_536)
        sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 1_024)
        sqlite3_limit(handle, SQLITE_LIMIT_ATTACHED, 0)
        let budget = CursorGrokQueryBudget(timeout: timeout)
        let context = Unmanaged.passUnretained(budget).toOpaque()
        defer { withExtendedLifetime(budget) {} }
        sqlite3_busy_handler(handle, { pointer, _ in
            guard let pointer else { return 0 }
            let budget = Unmanaged<CursorGrokQueryBudget>.fromOpaque(pointer).takeUnretainedValue()
            guard !budget.expired else { return 0 }
            usleep(10_000)
            return budget.expired ? 0 : 1
        }, context)
        sqlite3_progress_handler(handle, 1_000, { pointer in
            guard let pointer else { return 1 }
            return Unmanaged<CursorGrokQueryBudget>.fromOpaque(pointer).takeUnretainedValue().expired ? 1 : 0
        }, context)
        // Deny views, triggers, functions, PRAGMAs, schema/metadata queries,
        // writes and reads of any columns outside this exact SELECT's needs.
        let authorized = sqlite3_set_authorizer(handle, { _, action, first, second, schema, source in
            guard source == nil else { return SQLITE_DENY }
            if action == SQLITE_SELECT { return SQLITE_OK }
            guard action == SQLITE_READ, let first, let second, let schema,
                  String(cString: first) == "ItemTable", String(cString: schema) == "main",
                  ["key", "value"].contains(String(cString: second)) else { return SQLITE_DENY }
            return SQLITE_OK
        }, nil)
        guard authorized == SQLITE_OK else { throw ProviderUsageFailure.queryFailed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, Self.query, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw Self.failure(for: prepared) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) == 1, sqlite3_column_count(statement) == 1 else {
            throw ProviderUsageFailure.invalidResponse
        }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { throw ProviderUsageFailure.authenticationRequired }
        guard result == SQLITE_ROW else { throw Self.failure(for: result) }
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT else {
            throw ProviderUsageFailure.authenticationRequired
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, count <= Self.tokenByteLimit, let bytes = sqlite3_column_text(statement, 0),
              let token = String(data: Data(bytes: bytes, count: count), encoding: .utf8),
              token.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw ProviderUsageFailure.authenticationRequired
        }
        try Task.checkCancellation()
        try Self.requireSameFile(database, directory: directory, name: name)
        // Never infer a team from another Cursor key. The service validates this
        // token and the existing provider separately checks JWT expiry.
        return GrokBotAuthorization(accessToken: token, selectedTeamID: nil)
    }

    private struct GuardedFile {
        let descriptor: Int32
        let device: dev_t
        let inode: ino_t
        let size: Int64
    }

    private static func openDirectoryWithoutSymlinks(_ path: String) throws -> Int32 {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw ProviderUsageFailure.unsupported }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProviderUsageFailure.queryFailed }
        do {
            for part in path.split(separator: "/") {
                guard part != ".", part != ".." else { throw ProviderUsageFailure.unsupported }
                let next = openat(descriptor, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw fileFailure() }
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func openExistingFile(directory: Int32, name: String, maximumBytes: Int64,
                                         required: Bool) throws -> GuardedFile? {
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !required, errno == ENOENT { return nil }
            throw fileFailure()
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_size >= 0, info.st_size <= maximumBytes else {
            close(descriptor)
            throw ProviderUsageFailure.unsupported
        }
        return GuardedFile(descriptor: descriptor, device: info.st_dev, inode: info.st_ino, size: info.st_size)
    }

    private static func requireSameFile(_ file: GuardedFile, directory: Int32, name: String) throws {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == geteuid(),
              info.st_dev == file.device, info.st_ino == file.inode else {
            throw ProviderUsageFailure.queryFailed
        }
    }

    private static func fileFailure() -> ProviderUsageFailure {
        switch errno {
        case EACCES, EPERM: return .permissionRequired
        case ELOOP, ENOTDIR: return .unsupported
        default: return .authenticationRequired
        }
    }

    private static func failure(for result: Int32) -> ProviderUsageFailure {
        switch result & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED, SQLITE_INTERRUPT: return .timeout
        case SQLITE_TOOBIG, SQLITE_MISMATCH: return .authenticationRequired
        case SQLITE_READONLY: return .unsupported
        case SQLITE_CORRUPT, SQLITE_NOTADB, SQLITE_ERROR, SQLITE_AUTH: return .invalidResponse
        default: return .queryFailed
        }
    }
}

private final class CursorGrokQueryBudget {
    private let deadline: UInt64
    init(timeout: TimeInterval) { deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000) }
    var expired: Bool { Task.isCancelled || DispatchTime.now().uptimeNanoseconds >= deadline }
}
