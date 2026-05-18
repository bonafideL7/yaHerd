import Foundation
import SwiftData

@Model
final class AnimalTag {
    var publicID: UUID = UUID()
    var number: String = ""
    var colorID: UUID?
    var isPrimary: Bool = false
    var isActive: Bool = true
    var assignedAt: Date = Date.now
    var removedAt: Date?

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    init(
        publicID: UUID = UUID(),
        number: String,
        colorID: UUID? = nil,
        isPrimary: Bool = false,
        isActive: Bool = true,
        assignedAt: Date = Date.now,
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
