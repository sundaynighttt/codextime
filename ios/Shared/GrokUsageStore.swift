import Foundation

struct GrokUsageState: Codable, Sendable {
    let connectionID: UUID
    var snapshot: GrokUsageSnapshot?
}

protocol GrokUsageStoring: Sendable {
    func readState() throws -> GrokUsageState?
    func writeState(_ state: GrokUsageState) throws
}

/// Bounded atomic App Group JSON contains numbers and an opaque connection generation only.
/// All mutations are performed by GrokAccountClient while holding GrokAuthLock.
struct GrokUsageStore: GrokUsageStoring, Sendable {
    private let fileURL: URL?

    init(directoryURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: CodexConfiguration.appGroupID)) {
        fileURL = directoryURL?.appendingPathComponent("grok-direct-usage-v1.json")
    }

    func load(now: Date = Date()) -> GrokUsageSnapshot? {
        guard let snapshot = try? readState()?.snapshot, snapshot.isValid(at: now) else { return nil }
        return snapshot
    }

    func readState() throws -> GrokUsageState? {
        guard let fileURL else { throw GrokClientError.secureStorageUnavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 4_096 else { throw GrokClientError.invalidResponse }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 4_096 else { throw GrokClientError.invalidResponse }
            return try JSONDecoder().decode(GrokUsageState.self, from: data)
        } catch let error as GrokClientError { throw error }
        catch { throw GrokClientError.secureStorageUnavailable }
    }

    func writeState(_ state: GrokUsageState) throws {
        guard let fileURL else { throw GrokClientError.secureStorageUnavailable }
        do {
            let data = try JSONEncoder().encode(state)
            guard data.count <= 4_096 else { throw GrokClientError.invalidResponse }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as GrokClientError { throw error }
        catch { throw GrokClientError.secureStorageUnavailable }
    }
}
