import Foundation
import SwiftData

struct AnimalMovementService {

    @discardableResult
    static func move(
        _ animal: Animal,
        to pasture: Pasture?,
        in context: ModelContext,
        fromPastureName: String? = nil,
        date: Date = .now,
        save: Bool = true
    ) -> Bool {
        let previousName = fromPastureName ?? animal.pasture?.name
        let newName = pasture?.name

        guard previousName != newName else { return false }

        animal.pasture = pasture
        animal.location = .pasture
        animal.activeWorkingSession = nil

        let movement = MovementRecord(
            date: date,
            fromPasture: previousName,
            toPasture: newName,
            animal: animal
        )
        context.insert(movement)

        if save {
            try? context.save()
        }

        return true
    }

    static func move(
        _ animals: [Animal],
        to pasture: Pasture?,
        in context: ModelContext,
        date: Date = .now,
        save: Bool = true
    ) {
        var changedAny = false

        for animal in animals {
            let changed = move(animal, to: pasture, in: context, date: date, save: false)
            changedAny = changedAny || changed
        }

        if save, changedAny {
            try? context.save()
        }
    }
}
