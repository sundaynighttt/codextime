import Foundation
import Darwin

protocol GrokAuthLease: Sendable {
    func release()
}

protocol GrokAuthLocking: Sendable {
    func acquire() async throws -> any GrokAuthLease
}

/// An empty, private App Group lock file serializes token rotation in app and widget.
/// No credentials or account identifiers are written to this file.
struct GrokAuthLock: GrokAuthLocking, Sendable {
    let directoryURL: URL?

    init(directoryURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: CodexConfiguration.appGroupID)) {
        self.directoryURL = directoryURL
    }

    func acquire() async throws -> any GrokAuthLease {
        guard let directoryURL else { throw GrokClientError.secureStorageUnavailable }
        let url = directoryURL.appendingPathComponent("grok-auth.lock")
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw GrokClientError.secureStorageUnavailable }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG, status.st_uid == geteuid(),
              fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            Darwin.close(descriptor)
            throw GrokClientError.secureStorageUnavailable
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        do {
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN else {
                    throw GrokClientError.secureStorageUnavailable
                }
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw GrokClientError.busy }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            try Task.checkCancellation()
            return FileGrokAuthLease(descriptor: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }
}

private final class FileGrokAuthLease: GrokAuthLease, @unchecked Sendable {
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
