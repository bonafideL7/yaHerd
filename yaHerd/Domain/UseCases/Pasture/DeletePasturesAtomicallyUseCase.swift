import Foundation

/// User-facing atomic deletion command. The production app composes this with the
/// Core Data transaction writer instead of making separate move/archive/delete calls.
@MainActor
protocol PastureDeletionPerforming {
    func deletePastures(ids: [UUID], archivedAt: Date) async throws
}

@MainActor
struct DeletePasturesAtomicallyUseCase: PastureDeletionPerforming {
    let pastureReader: any PastureExistenceChecking & PastureResidentAnimalReader
    let transactionWriter: any PastureDeletionTransactionWriting

    func deletePastures(ids: [UUID], archivedAt: Date = .now) async throws {
        guard !ids.isEmpty else { return }
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }

        try pastureReader.validatePastureIDsExist(ids)

        var expectedStates: [PastureDeletionExpectedState] = []
        var operations: [PastureDeletionOperation] = []

        for pastureID in ids {
            let residentIDs = Set(
                try pastureReader.fetchResidentAnimals(pastureID: pastureID).map(\.id)
            )
            expectedStates.append(
                PastureDeletionExpectedState(
                    pastureID: pastureID,
                    residentAnimalIDs: residentIDs
                )
            )
            if !residentIDs.isEmpty {
                operations.append(
                    .moveAnimals(
                        animalIDs: residentIDs.sorted { $0.uuidString < $1.uuidString },
                        fromPastureID: pastureID,
                        toPastureID: nil
                    )
                )
            }
        }

        operations.append(.archiveFieldChecks(pastureIDs: ids, archivedAt: archivedAt))
        operations.append(.deletePastures(ids: ids))

        try await transactionWriter.deletePastures(
            DeletePasturesTransactionPlan(
                expectedStates: expectedStates,
                operations: operations
            )
        )
    }
}
