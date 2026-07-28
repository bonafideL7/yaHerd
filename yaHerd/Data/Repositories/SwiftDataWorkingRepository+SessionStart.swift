import Foundation
import SwiftData

@MainActor
extension SwiftDataWorkingRepository {
    func startSession(input: WorkingSessionStartInput) throws -> UUID {
        try WorkingTreatmentPlanRules.validate(input.plannedTreatments)

        let lookup = SwiftDataWorkingLookupStore(context: context)
        guard let sourcePasture = try lookup.fetchPasture(id: input.sourcePastureID) else {
            throw WorkingRepositoryError.pastureNotFound
        }

        let animals = try animalsForSessionStart(
            requestedIDs: input.animalIDs,
            sourcePasture: sourcePasture,
            lookup: lookup
        )
        try validateStartAnimals(animals, sourcePasture: sourcePasture)

        let templateName = input.treatmentTemplateName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let session = WorkingSession(
            date: Calendar.autoupdatingCurrent.startOfDay(for: input.date),
            status: .active,
            sourcePasture: sourcePasture,
            protocolName: templateName?.isEmpty == false ? templateName! : "Working Session",
            protocolItems: input.plannedTreatments
        )

        let idStore = SwiftDataPublicIDUniquenessStore(context: context)
        try idStore.ensureUniqueSessionPublicID(session)
        try context.insertIntoDefaultHerd(session)

        for animal in animals.sorted(by: tagOrder) {
            let collectedFromPasture = animal.pasture
            animal.pasture = nil
            animal.location = .workingPen
            animal.activeWorkingSession = session

            let queueItem = WorkingQueueItem(
                status: .queued,
                collectedFromPasture: collectedFromPasture,
                animal: animal,
                session: session
            )
            try idStore.ensureUniqueQueueItemPublicID(queueItem)
            try context.insertIntoDefaultHerd(queueItem)
            session.queueItems.append(queueItem)
        }

        try PersistenceLog.save(
            context,
            operation: "SwiftDataWorkingRepository.startSession"
        )
        return session.publicID
    }

    private func animalsForSessionStart(
        requestedIDs: [UUID]?,
        sourcePasture: Pasture,
        lookup: SwiftDataWorkingLookupStore
    ) throws -> [Animal] {
        guard let requestedIDs else {
            let animals = sourcePasture.animals.filter(isEligibleForWorkingSession)
            guard !animals.isEmpty else {
                throw WorkingRepositoryError.noEligibleAnimals
            }
            return animals
        }

        let uniqueIDs = requestedIDs.reduce(into: [UUID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
        guard !uniqueIDs.isEmpty else {
            throw WorkingRepositoryError.noEligibleAnimals
        }

        let animals = try lookup.fetchAnimals(ids: uniqueIDs)
        guard animals.count == uniqueIDs.count else {
            throw WorkingRepositoryError.animalNotFound
        }
        return animals
    }

    private func validateStartAnimals(
        _ animals: [Animal],
        sourcePasture: Pasture
    ) throws {
        guard animals.allSatisfy({ animal in
            isEligibleForWorkingSession(animal)
                && animal.pasture?.publicID == sourcePasture.publicID
        }) else {
            if animals.contains(where: { $0.activeWorkingSession != nil }) {
                throw WorkingRepositoryError.animalAlreadyInAnotherSession
            }
            throw WorkingRepositoryError.animalNotEligibleForCollection
        }
    }

    private func isEligibleForWorkingSession(_ animal: Animal) -> Bool {
        animal.isActiveInHerd
            && animal.location == .pasture
            && animal.activeWorkingSession == nil
    }

    private func tagOrder(_ lhs: Animal, _ rhs: Animal) -> Bool {
        lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
    }
}
