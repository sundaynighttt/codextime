import Foundation

struct ClaudeNativeUsageState: Codable, Sendable {
    let connectionID: UUID
    var snapshot: ClaudeNativeUsageSnapshot?
}

protocol ClaudeNativeUsageStoring: Sendable {
    func readState() throws -> ClaudeNativeUsageState?
    func writeState(_ state: ClaudeNativeUsageState) throws
}

/// Bounded atomic App Group JSON contains numbers and an opaque connection generation only.
/// All mutations are performed by ClaudeNativeAccountClient while holding ClaudeNativeAuthLock.
struct ClaudeNativeUsageStore: ClaudeNativeUsageStoring, Sendable {
    private let fileURL: URL?

    init(directoryURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: CodexConfiguration.appGroupID)) {
        fileURL = directoryURL?.appendingPathComponent("claude-native-direct-usage-v1.json")
    }

    func load(now: Date = Date()) -> ClaudeNativeUsageSnapshot? {
        guard let snapshot = try? readState()?.snapshot, snapshot.isValid(at: now) else { return nil }
        return snapshot
    }

    func readState() throws -> ClaudeNativeUsageState? {
        guard let fileURL else { throw ClaudeNativeClientError.secureStorageUnavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 4_096 else { throw ClaudeNativeClientError.invalidResponse }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 4_096 else { throw ClaudeNativeClientError.invalidResponse }
            return try JSONDecoder().decode(ClaudeNativeUsageState.self, from: data)
        } catch let error as ClaudeNativeClientError { throw error }
        catch { throw ClaudeNativeClientError.secureStorageUnavailable }
    }

    func writeState(_ state: ClaudeNativeUsageState) throws {
        guard let fileURL else { throw ClaudeNativeClientError.secureStorageUnavailable }
        do {
            let data = try JSONEncoder().encode(state)
            guard data.count <= 4_096 else { throw ClaudeNativeClientError.invalidResponse }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as ClaudeNativeClientError { throw error }
        catch { throw ClaudeNativeClientError.secureStorageUnavailable }
    }
}
