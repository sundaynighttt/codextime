import Foundation
import UsageSync

extension CloudSyncState {
    var hasCloudReadError: Bool {
        switch self {
        case .networkError, .deletionPending, .notConfigured: return true
        default: return false
        }
    }
}
