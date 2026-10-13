import Foundation

/// Shared pregnancy result used by Animal health and Working workflows.
/// Keep these raw values compatible with existing Core Data records.
enum PregnancyResult: String, Codable, CaseIterable, Sendable {
    case open
    case pregnant
    case unknown
}
