import Foundation

struct AnimalTagSnapshot: Identifiable, Hashable {
    let id: UUID
    let number: String
    let colorID: UUID?
    let isPrimary: Bool
    let isActive: Bool
    let assignedAt: Date
    let removedAt: Date?

    var normalizedNumber: String {
        number.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
