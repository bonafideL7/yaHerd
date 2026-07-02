import Foundation

enum FieldCheckSessionLockRules {
    static func canEditSessionData(completedAt: Date?) -> Bool {
        completedAt == nil
    }

    static func canUpdateFindingStatus(completedAt _: Date?) -> Bool {
        true
    }
}
