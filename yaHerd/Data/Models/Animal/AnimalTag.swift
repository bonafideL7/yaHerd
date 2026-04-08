import Foundation
import SwiftData

@Model
final class AnimalTag {
    @Attribute(.unique) var publicID: UUID
    var number: String
    var colorID: UUID?
    var isPrimary: Bool
    var isActive: Bool
    var assignedAt: Date
    var removedAt: Date?

    var animal: Animal?

    init(
        publicID: UUID = UUID(),
        number: String,
        colorID: UUID? = nil,
        isPrimary: Bool = false,
        isActive: Bool = true,
        assignedAt: Date = .now,
        removedAt: Date? = nil,
        animal: Animal? = nil
    ) {
        self.publicID = publicID
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
