import Foundation
import Darwin

protocol ClaudeNativeAuthLease: Sendable {
    func release()
}

protocol ClaudeNativeAuthLocking: Sendable {
    func acquire() async throws -> any ClaudeNativeAuthLease
}

/// An empty, private App Group lock file serializes token rotation in app and widget.
/// No credentials or account identifiers are written to this file.
struct ClaudeNativeAuthLock: ClaudeNativeAuthLocking, Sendable {
    let directoryURL: URL?

    init(directoryURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: CodexConfiguration.appGroupID)) {
        self.directoryURL = directoryURL
    }

    func acquire() async throws -> any ClaudeNativeAuthLease {
        guard let directoryURL else { throw ClaudeNativeClientError.secureStorageUnavailable }
        let url = directoryURL.appendingPathComponent("claude-native-auth.lock")
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ClaudeNativeClientError.secureStorageUnavailable }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG, status.st_uid == geteuid(),
              fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            Darwin.close(descriptor)
            throw ClaudeNativeClientError.secureStorageUnavailable
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        do {
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN else {
                    throw ClaudeNativeClientError.secureStorageUnavailable
                }
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw ClaudeNativeClientError.busy }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            try Task.checkCancellation()
            return FileClaudeNativeAuthLease(descriptor: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }
}

private final class FileClaudeNativeAuthLease: ClaudeNativeAuthLease, @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?

    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { release() }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor else { return }
        self.descriptor = nil
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
