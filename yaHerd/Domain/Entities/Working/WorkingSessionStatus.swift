import Foundation

/// Session lifecycle persisted as a raw status string in Core Data.
enum WorkingSessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case finished
    case cancelled
}
