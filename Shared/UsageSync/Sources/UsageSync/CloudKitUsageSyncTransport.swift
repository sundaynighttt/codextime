import CloudKit
import CryptoKit
import Foundation

/// Uses only fixed records in the signed-in user's private database.
/// No queries, public/shared database, account metadata, or raw error logging.
@MainActor final class CloudKitUsageSyncTransport: UsageSyncTransport {
    nonisolated static let containerIdentifier = "iCloud.com.sundaynighttt.codextime"
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }
    private let recordType = "UsageSnapshotV1"

    func accountScope() async throws -> String? {
        do {
            guard try await container.accountStatus() == .available else { return nil }
            let recordID = try await container.userRecordID()
            let hash = SHA256.hash(data: Data((Self.containerIdentifier + ":" + recordID.recordName).utf8))
            return hash.map { String(format: "%02x", $0) }.joined()
        } catch { throw safeError(error) }
    }

    func fetch(expectedScope: String) async throws -> [SyncedUsage] {
        do {
            try await verify(expectedScope)
            let identifiers = SyncProvider.allCases.map { CKRecord.ID(recordName: $0.rawValue) }
            let results = try await database.records(for: identifiers, desiredKeys: ["payload"])
            var readings: [SyncedUsage] = []
            for provider in SyncProvider.allCases {
                guard let result = results[CKRecord.ID(recordName: provider.rawValue)] else { throw UsageSyncError.invalidPayload }
                switch result {
                case .success(let record):
                    guard record.recordType == recordType,
                          let payload = record.encryptedValues["payload"] as? Data,
                          payload.count <= 4_096 else { throw UsageSyncError.invalidPayload }
                    let reading = try JSONDecoder().decode(SyncedUsage.self, from: payload)
                    guard reading.provider == provider else { throw UsageSyncError.invalidPayload }
                    readings.append(reading)
                case .failure(let error):
                    if (error as? CKError)?.code != .unknownItem { throw safeError(error) }
                }
            }
            try await verify(expectedScope)
            return readings
        } catch { throw safeError(error) }
    }

    func save(_ readings: [SyncedUsage], expectedScope: String) async throws {
        do {
            try await verify(expectedScope)
            guard Set(readings.map(\.provider)).count == readings.count else { throw UsageSyncError.invalidPayload }
            let records = try readings.map { reading -> CKRecord in
                let record = CKRecord(recordType: recordType, recordID: .init(recordName: reading.provider.rawValue))
                record.encryptedValues["payload"] = try JSONEncoder().encode(reading)
                return record
            }
            try Task.checkCancellation()
            let results = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            for result in results.saveResults.values { _ = try result.get() }
            try await verify(expectedScope)
        } catch { throw safeError(error) }
    }

    func deleteAll(expectedScope: String) async throws {
        do {
            try await verify(expectedScope)
            try Task.checkCancellation()
            let identifiers = SyncProvider.allCases.map { CKRecord.ID(recordName: $0.rawValue) }
            let results = try await database.modifyRecords(saving: [], deleting: identifiers, atomically: false)
            for result in results.deleteResults.values {
                if case .failure(let error) = result, (error as? CKError)?.code != .unknownItem { throw error }
            }
            try await verify(expectedScope)
        } catch { throw safeError(error) }
    }

    private func verify(_ expectedScope: String) async throws {
        try Task.checkCancellation()
        guard let current = try await accountScope() else { throw UsageSyncError.signedOut }
        guard current == expectedScope else { throw UsageSyncError.accountChanged }
        try Task.checkCancellation()
    }

    private func safeError(_ error: Error) -> Error {
        if error is CancellationError || error is UsageSyncError { return error }
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated: return UsageSyncError.signedOut
            case .badContainer, .badDatabase, .missingEntitlement, .permissionFailure: return UsageSyncError.notConfigured
            default: return UsageSyncError.network
            }
        }
        return UsageSyncError.network
    }
}
