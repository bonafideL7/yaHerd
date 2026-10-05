import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataWorkingRepositoryContractTests: XCTestCase {
    func testWorkingCoreDataReadAndValidationContracts() async throws {
        try await run { try await WorkingRepositoryContract.assertSessionStartAndReadProjections(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertStartAllEligibleAnimalsAndValidation(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertSessionListOrderingPersists(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertMissingIdentifiersAndEligibilityErrorsRemainStable(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertSessionStartRejectsInvalidPlanBeforeMutation(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertMissingIdentifiersAcrossMutationSurfaceRemainStable(using: $0.fixture) }
    }

    func testWorkingCoreDataWorkDataContracts() async throws {
        try await run { try await WorkingRepositoryContract.assertQueueWorkDataReplacementAndReset(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertQueueWorkDataValidationDoesNotPartiallyReplaceState(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCastrationGeneratedHealthRecordCanBeRecordedAndCleared(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertQueueEditsCanClearDestinationAndPregnancyCheck(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertQueueEditsRejectInvalidReferencesWithoutPartialReplacement(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertWorkingPregnancyCheckSurvivesSireDeletion(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertDirectQueueCompletionValidationDoesNotMutateQueuedState(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertQueueWorkDataMutationsRemainScopedToTargetAnimal(using: $0.fixture) }
    }

    func testWorkingCoreDataLifecycleContracts() async throws {
        try await run { try await WorkingRepositoryContract.assertAdditionalCollectionPersistsQueueAndAnimalOwnership(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertSessionCompletionMovesAnimalsAndReopenPreservesCompletedState(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertDeletingActiveSessionRestoresAnimalsAndRemovesSessionWorkData(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertInvalidCompletionDestinationDoesNotMoveAnyAnimal(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertDeletingFinishedSessionLeavesReturnedAnimalsAtDestination(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertFinishedSessionLocksWorkingMutationsUntilReopened(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCollectionRejectsStaleBatchWithoutPartialMutation(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertStaleSessionCannotStealAnimalFromNewerWorkingSession(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCompletionUsesCurrentPastureWhenAnimalWasReleasedFromWorkingOwnership(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertFinishPersistsMissingAnimalQueueHistory(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertFinishAllowsUnworkedAnimalsAndPreservesQueueStatus(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertAnimalStateChangesDoNotImplicitlyEndWorkingOwnership(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertDeletingStaleSessionDoesNotUndoExternalAnimalMovement(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertPersistedCancelledAndSkippedStatusesRemainReadableAndLocked(using: $0.fixture) }
        try await run {
            try await WorkingRepositoryContract.assertAnimalHardDeletionPreservesSessionOwnedTreatmentRows(
                using: $0.fixture,
                historicalInspection: $0.historicalInspection
            )
        }
    }

    func testWorkingCoreDataPlanTagTemplateAndHistoryContracts() async throws {
        try await run { try await WorkingRepositoryContract.assertSessionTreatmentPlanAndPrimaryTagReplacementPersist(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertTreatmentTemplateCRUDAndOrdering(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertTemplateChangesDoNotRewriteExistingSessionSnapshot(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertSessionPlanChangesDoNotDeleteRecordedTreatmentHistory(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCompletedQueueHistorySurvivesLiveAnimalDeletion(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertTreatmentTemplatePlanValidationDoesNotPartiallyWrite(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCompletedQueueHistoryIgnoresLaterAnimalDisplayChanges(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertCompletedQueueHistoryIgnoresLaterPastureRenames(using: $0.fixture) }
    }

    func testWorkingCoreDataReadsAndMutationsStayWithinSelectedHerd() async throws {
        let environment = try await CoreDataWorkingContractEnvironment.make()
        let primaryPasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Primary Working Herd Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let primaryAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Primary Working Cow",
                tagNumber: "WH-PRIMARY",
                pastureID: primaryPasture.id
            )
        )
        let primaryWorking = environment.makeWorkingRepository()
        let primarySessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 200_000),
                sourcePastureID: primaryPasture.id,
                treatmentTemplateName: "Primary Working Session",
                plannedTreatments: [],
                animalIDs: [primaryAnimal.id]
            )
        )
        let primaryTemplateID = try primaryWorking.createTemplate(
            name: "Primary Working Template",
            items: []
        )

        let otherHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: otherHerdID,
            name: "Other Working Contract Herd"
        )
        let otherSelection = CoreDataWorkingContractSelection()
        otherSelection.currentHerdID = otherHerdID
        let otherPastures = CoreDataPastureRepository(
            selection: otherSelection,
            assembly: environment.assembly
        )
        let otherAnimals = CoreDataAnimalRepository(
            selection: otherSelection,
            assembly: environment.assembly
        )
        let otherWorking = CoreDataWorkingContractAdapter(
            working: CoreDataWorkingRepository(
                selection: otherSelection,
                assembly: environment.assembly
            ),
            templates: CoreDataWorkingTreatmentTemplateRepository(
                selection: otherSelection,
                assembly: environment.assembly
            )
        )
        let otherPasture = try otherPastures.create(
            input: PastureInput(
                name: "Other Working Herd Pasture",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.75
            )
        )
        let otherAnimal = try otherAnimals.create(
            input: Self.animalInput(
                name: "Other Working Cow",
                tagNumber: "WH-OTHER",
                pastureID: otherPasture.id
            )
        )
        let otherSessionID = try await otherWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 201_000),
                sourcePastureID: otherPasture.id,
                treatmentTemplateName: "Other Working Session",
                plannedTreatments: [],
                animalIDs: [otherAnimal.id]
            )
        )
        let otherTemplateID = try otherWorking.createTemplate(
            name: "Other Working Template",
            items: []
        )
        let otherBefore = try XCTUnwrap(
            otherWorking.fetchSessionDetail(id: otherSessionID)
        )

        XCTAssertEqual(Set(try primaryWorking.fetchSessions().map(\.id)), Set([primarySessionID]))
        XCTAssertNil(try primaryWorking.fetchSessionDetail(id: otherSessionID))
        XCTAssertNil(
            try primaryWorking.fetchQueueItemEditor(
                sessionID: otherSessionID,
                queueItemID: try XCTUnwrap(otherBefore.queueItems.first?.id)
            )
        )
        XCTAssertEqual(Set(try primaryWorking.fetchTemplates().map(\.id)), Set([primaryTemplateID]))
        XCTAssertNil(try primaryWorking.fetchTemplateDetail(id: otherTemplateID))

        await XCTAssertThrowsErrorAsync(
            try await primaryWorking.updateSessionTreatments(
                id: otherSessionID,
                plannedTreatments: []
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionNotFound)
        }
        await XCTAssertThrowsErrorAsync(
            try await primaryWorking.deleteSession(id: otherSessionID)
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionNotFound)
        }

        XCTAssertEqual(
            try otherWorking.fetchSessionDetail(id: otherSessionID),
            otherBefore
        )
        XCTAssertEqual(Set(try otherWorking.fetchSessions().map(\.id)), Set([otherSessionID]))
        XCTAssertEqual(Set(try otherWorking.fetchTemplates().map(\.id)), Set([otherTemplateID]))
        XCTAssertNil(try otherWorking.fetchSessionDetail(id: primarySessionID))
        XCTAssertNil(try otherWorking.fetchTemplateDetail(id: primaryTemplateID))
    }

    func testWorkingCoreDataRollbackContracts() async throws {
        try await run {
            try await WorkingRepositoryContract.assertSessionStartFailureRollsBackAllStagedState(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertAdditionalCollectionFailureRollsBackAllStagedState(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertInitialQueueItemCompletionFailureRollsBackAllStagedState(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertWorkDataReplacementFailureRollsBackAllStagedState(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertDeleteWorkDataFailureRollsBackResetAndChildren(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertPrimaryTagReplacementFailureRollsBackAnimalAndQueueSnapshot(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertTemplateBatchDeletionFailureRollsBackEveryTemplate(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertSessionCompletionFailureRollsBackMovementsAndDestinations(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
        try await run {
            try await WorkingRepositoryContract.assertSessionDeletionFailureRollsBackRestorationAndCleanup(
                using: $0.fixture,
                failureInjection: $0.failureInjection
            )
        }
    }

    private static func animalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSinceReferenceDate: 100_000),
            status: .active,
            pastureID: pastureID,
            sireID: nil,
            damID: nil,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }

    private func run(
        _ body: @MainActor (CoreDataWorkingContractEnvironment) async throws -> Void
    ) async throws {
        let environment = try await CoreDataWorkingContractEnvironment.make()
        try await body(environment)
    }
}

@MainActor
private final class CoreDataWorkingContractEnvironment {
    let assembly: CoreDataPersistenceAssembly
    let selection: CoreDataWorkingContractSelection
    let herdID: UUID

    static func make() async throws -> CoreDataWorkingContractEnvironment {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        return try CoreDataWorkingContractEnvironment(assembly: assembly)
    }

    init(assembly: CoreDataPersistenceAssembly) throws {
        self.assembly = assembly
        self.selection = CoreDataWorkingContractSelection()
        self.herdID = UUID()
        self.selection.currentHerdID = herdID
        try seedHerd()
    }

    var fixture: WorkingRepositoryContractFixture {
        WorkingRepositoryContractFixture(
            makeWorkingRepository: { self.makeWorkingRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makePastureRepository: { self.makePastureRepository() },
            makeTagColorRepository: { self.makeTagColorRepository() }
        )
    }

    var historicalInspection: WorkingHistoricalPersistenceInspection {
        WorkingHistoricalPersistenceInspection(
            persistedWorkDataIDs: { sessionID, animalID in
                try self.persistedWorkDataIDs(sessionID: sessionID, animalID: animalID)
            }
        )
    }

    var failureInjection: WorkingRollbackFailureInjection {
        WorkingRollbackFailureInjection(
            startSessionFailingAfterQueueStaged: { input in
                _ = try await self.makeCoreWorkingRepository().startSession(
                    input: input,
                    beforeSave: { context in
                        let session = try Self.singleInsertedWorkingSession(in: context)
                        let queueIDs = Set(
                            context.insertedObjects.compactMap { object -> UUID? in
                                guard let item = object as? CDWorkingQueueItem,
                                      item.session.objectID == session.objectID else {
                                    return nil
                                }
                                return item.id
                            }
                        )
                        guard !queueIDs.isEmpty else {
                            throw CoreDataWorkingContractTestError.missingStagedQueueItem
                        }
                        throw WorkingRollbackInjectedError.afterSessionStartStaged(
                            sessionID: session.id,
                            queueItemIDs: queueIDs
                        )
                    }
                )
            },
            collectAnimalsFailingAfterQueueStaged: { sessionID, animalIDs in
                try await self.makeCoreWorkingRepository().collectAnimals(
                    sessionID: sessionID,
                    animalIDs: animalIDs,
                    beforeSave: { context in
                        let queueIDs = Set(
                            context.insertedObjects.compactMap { ($0 as? CDWorkingQueueItem)?.id }
                        )
                        guard !queueIDs.isEmpty else {
                            throw CoreDataWorkingContractTestError.missingStagedQueueItem
                        }
                        throw WorkingRollbackInjectedError.afterCollectionStaged(
                            sessionID: sessionID,
                            queueItemIDs: queueIDs
                        )
                    }
                )
            },
            completeQueueItemFailingAfterMutationStaged: {
                sessionID,
                queueItemID,
                treatmentEntries,
                pregnancyCheck,
                markCastrated,
                observationNotes in
                try await self.makeCoreWorkingRepository().complete(
                    queueItemID: queueItemID,
                    inSessionID: sessionID,
                    treatmentEntries: treatmentEntries,
                    pregnancyCheck: pregnancyCheck,
                    markCastrated: markCastrated,
                    observationNotes: observationNotes,
                    beforeSave: { _ in
                        throw WorkingRollbackInjectedError.afterQueueItemCompletionStaged(
                            sessionID: sessionID,
                            queueItemID: queueItemID
                        )
                    }
                )
            },
            replaceWorkDataFailingAfterMutationStaged: { sessionID, queueItemID, input in
                try await self.makeCoreWorkingRepository().saveEdits(
                    forQueueItemID: queueItemID,
                    inSessionID: sessionID,
                    input: input,
                    beforeSave: { _ in
                        throw WorkingRollbackInjectedError.afterWorkDataReplacementStaged(
                            sessionID: sessionID,
                            queueItemID: queueItemID
                        )
                    }
                )
            },
            replacePrimaryTagFailingAfterMutationStaged: { sessionID, queueItemID, input in
                try await self.makeCoreWorkingRepository().replacePrimaryTag(
                    forQueueItemID: queueItemID,
                    inSessionID: sessionID,
                    input: input,
                    beforeSave: { context in
                        guard let replacement = context.insertedObjects
                            .compactMap({ $0 as? CDAnimalTag })
                            .first(where: { $0.isActive && $0.isPrimary }) else {
                            throw CoreDataWorkingContractTestError.missingStagedReplacementTag
                        }
                        throw WorkingRollbackInjectedError.afterPrimaryTagReplacementStaged(
                            sessionID: sessionID,
                            queueItemID: queueItemID,
                            replacementTagID: replacement.id
                        )
                    }
                )
            },
            deleteWorkDataFailingAfterCleanupStaged: { sessionID, queueItemID in
                try await self.makeCoreWorkingRepository().deleteWorkData(
                    forQueueItemID: queueItemID,
                    inSessionID: sessionID,
                    beforeSave: { _ in
                        throw WorkingRollbackInjectedError.afterWorkDataDeletionStaged(
                            sessionID: sessionID,
                            queueItemID: queueItemID
                        )
                    }
                )
            },
            completeSessionFailingAfterMovementStaged: { sessionID, assignments in
                try await self.makeCoreWorkingRepository().completeSession(
                    id: sessionID,
                    assignments: assignments,
                    beforeSave: { context in
                        guard let movement = context.insertedObjects
                            .compactMap({ $0 as? CDMovementRecord })
                            .first else {
                            throw CoreDataWorkingContractTestError.missingStagedMovement
                        }
                        let request = NSFetchRequest<CDWorkingQueueItem>(
                            entityName: CDWorkingQueueItem.coreDataEntityName
                        )
                        request.predicate = NSPredicate(
                            format: "session.id == %@",
                            sessionID as NSUUID
                        )
                        let queueIDs = Set(
                            try context.fetch(request)
                                .filter { $0.destinationPastureIDSnapshot != nil }
                                .map(\.id)
                        )
                        guard !queueIDs.isEmpty else {
                            throw CoreDataWorkingContractTestError.missingStagedDestination
                        }
                        throw WorkingRollbackInjectedError.afterSessionCompletionStaged(
                            sessionID: sessionID,
                            movedAnimalID: movement.animal.id,
                            destinationQueueItemIDs: queueIDs
                        )
                    }
                )
            },
            deleteSessionFailingAfterCleanupStaged: { sessionID in
                try await self.makeCoreWorkingRepository().deleteSession(
                    id: sessionID,
                    beforeSave: { context in
                        guard context.deletedObjects.contains(where: {
                            ($0 as? CDWorkingSession)?.id == sessionID
                        }) else {
                            throw CoreDataWorkingContractTestError.missingStagedSessionDeletion
                        }
                        guard let restoredAnimal = context.updatedObjects
                            .compactMap({ $0 as? CDAnimal })
                            .first(where: {
                                $0.activeWorkingSession == nil
                                    && $0.currentPasture != nil
                            }) else {
                            throw CoreDataWorkingContractTestError.missingStagedRestoredAnimal
                        }
                        throw WorkingRollbackInjectedError.afterSessionDeletionStaged(
                            sessionID: sessionID,
                            restoredAnimalID: restoredAnimal.id
                        )
                    }
                )
            },
            deleteTemplatesFailingAfterDeletionStaged: { templateIDs in
                try self.makeTemplateRepository().deleteTemplates(
                    ids: templateIDs,
                    beforeSave: { context in
                        let deleted = Set(
                            context.deletedObjects.compactMap {
                                ($0 as? CDWorkingTreatmentTemplate)?.id
                            }
                        )
                        guard !deleted.isEmpty else {
                            throw CoreDataWorkingContractTestError.missingStagedTemplateDeletion
                        }
                        throw WorkingRollbackInjectedError.afterTemplateDeletionStaged(
                            templateIDs: deleted
                        )
                    }
                )
            },
            persistedQueueItemIDs: {
                try self.persistedQueueItemIDs()
            },
            persistedWorkDataIDs: { sessionID, animalID in
                try self.persistedWorkDataIDs(
                    sessionID: sessionID,
                    animalID: animalID
                )
            },
            persistedMovementRecordIDs: { animalIDs in
                try self.persistedMovementRecordIDs(animalIDs: animalIDs)
            },
            persistedAnimalTagIDs: { animalID in
                try self.persistedAnimalTagIDs(animalID: animalID)
            },
            persistedTemplateIDs: {
                try self.persistedTemplateIDs()
            }
        )
    }

    func makeWorkingRepository() -> CoreDataWorkingContractAdapter {
        CoreDataWorkingContractAdapter(
            working: makeCoreWorkingRepository(),
            templates: makeTemplateRepository()
        )
    }

    func makeCoreWorkingRepository() -> CoreDataWorkingRepository {
        CoreDataWorkingRepository(
            selection: selection,
            assembly: assembly
        )
    }

    func makeTemplateRepository() -> CoreDataWorkingTreatmentTemplateRepository {
        CoreDataWorkingTreatmentTemplateRepository(
            selection: selection,
            assembly: assembly
        )
    }

    func makeAnimalRepository() -> CoreDataAnimalRepository {
        CoreDataAnimalRepository(
            selection: selection,
            assembly: assembly
        )
    }

    func makePastureRepository() -> CoreDataPastureRepository {
        CoreDataPastureRepository(
            selection: selection,
            assembly: assembly
        )
    }

    func makeTagColorRepository() -> CoreDataTagColorRepository {
        CoreDataTagColorRepository(
            selection: selection,
            assembly: assembly
        )
    }

    func seedAdditionalHerd(
        id: UUID,
        name: String
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = id
            herd.name = name
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 2_000)
            herd.updatedAt = herd.createdAt
            try context.save()
        }
    }

    private func seedHerd() throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Working Contract Herd"
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
            herd.updatedAt = herd.createdAt
            try context.save()
        }
    }

    private func persistedQueueItemIDs() throws -> Set<UUID> {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDWorkingQueueItem>(
                entityName: CDWorkingQueueItem.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return Set(try context.fetch(request).map(\.id))
        }
    }

    private func persistedWorkDataIDs(
        sessionID: UUID,
        animalID: UUID
    ) throws -> WorkingPersistedWorkDataIDs {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let treatmentRequest = NSFetchRequest<CDWorkingTreatmentRecord>(
                entityName: CDWorkingTreatmentRecord.coreDataEntityName
            )
            treatmentRequest.predicate = NSPredicate(
                format: "herd.id == %@ AND session.id == %@ AND animalIDSnapshot == %@",
                herdID as NSUUID,
                sessionID as NSUUID,
                animalID as NSUUID
            )

            let pregnancyRequest = NSFetchRequest<CDPregnancyCheck>(
                entityName: CDPregnancyCheck.coreDataEntityName
            )
            pregnancyRequest.predicate = NSPredicate(
                format: "herd.id == %@ AND workingSession.id == %@ AND animal.id == %@",
                herdID as NSUUID,
                sessionID as NSUUID,
                animalID as NSUUID
            )

            let healthRequest = NSFetchRequest<CDHealthRecord>(
                entityName: CDHealthRecord.coreDataEntityName
            )
            healthRequest.predicate = NSPredicate(
                format: "herd.id == %@ AND workingSession.id == %@ AND animal.id == %@",
                herdID as NSUUID,
                sessionID as NSUUID,
                animalID as NSUUID
            )

            return WorkingPersistedWorkDataIDs(
                treatmentRecordIDs: Set(try context.fetch(treatmentRequest).map(\.id)),
                pregnancyCheckIDs: Set(try context.fetch(pregnancyRequest).map(\.id)),
                healthRecordIDs: Set(try context.fetch(healthRequest).map(\.id))
            )
        }
    }

    private func persistedMovementRecordIDs(
        animalIDs: [UUID]
    ) throws -> Set<UUID> {
        let animalIDs = Set(animalIDs)
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDMovementRecord>(
                entityName: CDMovementRecord.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return Set(
                try context.fetch(request)
                    .filter { animalIDs.contains($0.animal.id) }
                    .map(\.id)
            )
        }
    }

    private func persistedAnimalTagIDs(
        animalID: UUID
    ) throws -> Set<UUID> {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDAnimalTag>(
                entityName: CDAnimalTag.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND animal.id == %@",
                herdID as NSUUID,
                animalID as NSUUID
            )
            return Set(try context.fetch(request).map(\.id))
        }
    }

    private func persistedTemplateIDs() throws -> Set<UUID> {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return Set(try context.fetch(request).map(\.id))
        }
    }

    private nonisolated static func singleInsertedWorkingSession(
        in context: NSManagedObjectContext
    ) throws -> CDWorkingSession {
        let sessions = context.insertedObjects.compactMap {
            $0 as? CDWorkingSession
        }
        guard sessions.count == 1, let session = sessions.first else {
            throw CoreDataWorkingContractTestError.missingStagedSession
        }
        return session
    }
}

@MainActor
private final class CoreDataWorkingContractAdapter: WorkingContractRepository {
    private let working: CoreDataWorkingRepository
    private let templates: CoreDataWorkingTreatmentTemplateRepository

    init(
        working: CoreDataWorkingRepository,
        templates: CoreDataWorkingTreatmentTemplateRepository
    ) {
        self.working = working
        self.templates = templates
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        try working.fetchSessions()
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        try working.fetchSessionDetail(id: id)
    }

    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        try working.fetchQueueItemEditor(
            sessionID: sessionID,
            queueItemID: queueItemID
        )
    }

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        try templates.fetchTemplates()
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        try templates.fetchTemplateDetail(id: id)
    }

    func createTemplate(
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) throws -> UUID {
        try templates.createTemplate(name: name, items: items)
    }

    func updateTemplate(
        id: UUID,
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) throws {
        try templates.updateTemplate(id: id, name: name, items: items)
    }

    func deleteTemplates(ids: [UUID]) throws {
        try templates.deleteTemplates(ids: ids)
    }

    func startSession(input: WorkingSessionStartInput) async throws -> UUID {
        try await working.startSession(input: input)
    }

    func collectAnimals(
        sessionID: UUID,
        animalIDs: [UUID]
    ) async throws {
        try await working.collectAnimals(
            sessionID: sessionID,
            animalIDs: animalIDs
        )
    }

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) async throws {
        try await working.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: treatmentEntries,
            pregnancyCheck: pregnancyCheck,
            markCastrated: markCastrated,
            observationNotes: observationNotes
        )
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) async throws {
        try await working.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: input
        )
    }

    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) async throws {
        try await working.updateSessionTreatments(
            id: id,
            plannedTreatments: plannedTreatments
        )
    }

    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) async throws -> WorkingQueueItemEditorSnapshot {
        try await working.replacePrimaryTag(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: input
        )
        guard let editor = try working.fetchQueueItemEditor(
            sessionID: sessionID,
            queueItemID: queueItemID
        ) else {
            throw WorkingRepositoryError.queueItemNotFound
        }
        return editor
    }

    func deleteWorkData(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID
    ) async throws {
        try await working.deleteWorkData(
            forQueueItemID: queueItemID,
            inSessionID: sessionID
        )
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) async throws {
        try await working.completeSession(
            id: id,
            assignments: assignments
        )
    }

    func reopenSession(id: UUID) async throws {
        try await working.reopenSession(id: id)
    }

    func deleteSession(id: UUID) async throws {
        try await working.deleteSession(id: id)
    }
}

@MainActor
private final class CoreDataWorkingContractSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

extension CoreDataPastureRepository: WorkingContractPastureRepository {}

private enum CoreDataWorkingContractTestError: Error {
    case missingStagedSession
    case missingStagedQueueItem
    case missingStagedReplacementTag
    case missingStagedMovement
    case missingStagedDestination
    case missingStagedSessionDeletion
    case missingStagedRestoredAnimal
    case missingStagedTemplateDeletion
}
