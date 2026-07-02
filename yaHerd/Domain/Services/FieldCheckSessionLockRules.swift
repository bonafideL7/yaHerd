import Foundation

enum FieldCheckSessionLockRules {
    static func isEditable(completedAt: Date?) -> Bool {
        completedAt == nil
    }
}
