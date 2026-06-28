import Foundation

struct PastureGroupSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let grazeDays: Int
    let restDays: Int
    let pastureCount: Int
}
