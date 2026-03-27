import Foundation
import SwiftData

@Model
final class AnimalTag {
    var number: String
    var colorID: UUID?
    var isPrimary: Bool
    var isActive: Bool
    var assignedAt: Date
    var removedAt: Date?

    var animal: Animal?

    init(
        number: String,
        colorID: UUID? = nil,
        isPrimary: Bool = false,
        isActive: Bool = true,
        assignedAt: Date = .now,
        removedAt: Date? = nil,
        animal: Animal? = nil
    ) {
        self.number = number
        self.colorID = colorID
        self.isPrimary = isPrimary
        self.isActive = isActive
        self.assignedAt = assignedAt
        self.removedAt = removedAt
        self.animal = animal
    }

    var normalizedNumber: String {
        number.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
