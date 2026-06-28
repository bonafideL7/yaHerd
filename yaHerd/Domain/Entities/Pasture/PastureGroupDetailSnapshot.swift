import Foundation

struct PastureGroupDetailSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let grazeDays: Int
    let restDays: Int
    let pastures: [PastureSummary]
}
