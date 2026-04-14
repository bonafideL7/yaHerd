import Foundation

struct AnimalMovementChange: Hashable {
    var animalID: UUID
    var fromPastureName: String?
    var toPastureName: String?
    var date: Date

    var changed: Bool {
        fromPastureName != toPastureName
    }
}

struct AnimalMovementService {
    static func movementChange(
        animalID: UUID,
        fromPastureName: String?,
        toPastureName: String?,
        date: Date = .now
    ) -> AnimalMovementChange {
        AnimalMovementChange(
            animalID: animalID,
            fromPastureName: fromPastureName,
            toPastureName: toPastureName,
            date: date
        )
    }
}
