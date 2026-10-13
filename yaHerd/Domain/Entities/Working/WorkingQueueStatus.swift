import Foundation

/// Queue item lifecycle persisted as a raw status string in Core Data.
enum WorkingQueueStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case inProgress
    case done
    case skipped
}
