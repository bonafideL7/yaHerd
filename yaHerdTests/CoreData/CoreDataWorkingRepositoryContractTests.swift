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
        try await run { try await WorkingRepositoryContract.assertPersistedCancelledAndSkippedStatusesRemainReadableAndLocked(using: $0.fixture, historicalStatusInjection: $0.historicalStatusInjection) }
        try await run {
            try await WorkingRepositoryContract.assertAnimalHardDeletionPreservesSessionOwnedTreatmentRows(
                using: $0.fixture,
                historicalInspection: $0.historicalInspection
            )
        }
    }

    func testWorkingCoreDataPlanTagTemplateAndHistoryContracts() async throws {
        try await run { try await WorkingRepositoryContract.assertSessionTreatmentPlanAndPrimaryTagReplacementPersist(using: $0.fixture) }
        try await run { try await WorkingRepositoryContract.assertPrimaryTagReplacementPreservesHiddenReferencedColor(using: $0.fixture) }
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

    func testDashboardWorkingGraphMatchesDirectReaderAfterSQLiteReopen() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = try CoreDataWorkingContractEnvironment(assembly: assembly)
        let primaryWorking = environment.makeWorkingRepository()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Dashboard Working Graph Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Dashboard Working Graph Cow",
                tagNumber: "DWG-PRIMARY",
                pastureID: pasture.id
            )
        )
        let sessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 440_000),
                sourcePastureID: pasture.id,
                treatmentTemplateName: "Dashboard Graph Session",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )

        let controlAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Dashboard Working Graph Control Cow",
                tagNumber: "DWG-CONTROL",
                pastureID: pasture.id
            )
        )
        let controlSessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 526_400),
                sourcePastureID: pasture.id,
                treatmentTemplateName: "Healthy Dashboard Graph Control",
                plannedTreatments: [],
                animalIDs: [controlAnimal.id]
            )
        )

        // An unrelated Herd remains independently readable, even after a
        // selected-Herd session graph fails validation.
        let otherHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: otherHerdID,
            name: "Independent Dashboard Graph Herd"
        )
        let otherSelection = CoreDataWorkingContractSelection()
        otherSelection.currentHerdID = otherHerdID
        let otherPasture = try CoreDataPastureRepository(
            selection: otherSelection,
            assembly: assembly
        ).create(input: PastureInput(
            name: "Independent Dashboard Graph Pasture",
            acreage: 24,
            usableAcreage: 22,
            targetAcresPerHead: 1.5
        ))
        let otherAnimal = try CoreDataAnimalRepository(
            selection: otherSelection,
            assembly: assembly
        ).create(input: Self.animalInput(
            name: "Independent Dashboard Graph Cow",
            tagNumber: "DWG-OTHER",
            pastureID: otherPasture.id
        ))
        let otherWorking = CoreDataWorkingRepository(
            selection: otherSelection,
            assembly: assembly
        )
        let otherSessionID = try await otherWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 441_000),
                sourcePastureID: otherPasture.id,
                treatmentTemplateName: "Independent Dashboard Graph Session",
                plannedTreatments: [],
                animalIDs: [otherAnimal.id]
            )
        )

        func dashboard(
            in assembly: CoreDataPersistenceAssembly,
            selection: CoreDataWorkingContractSelection
        ) -> CoreDataReadModelActor {
            CoreDataReadModelActor(
                contextFactory: assembly.contextFactory,
                lookup: assembly.lookup,
                currentHerdID: { selection.currentHerdID }
            )
        }

        let primaryDashboard = dashboard(in: assembly, selection: environment.selection)
        let otherDashboard = dashboard(in: assembly, selection: otherSelection)
        let healthyPrimaryDashboard = try await primaryDashboard.fetchDashboardRecords()
        XCTAssertEqual(
            healthyPrimaryDashboard.workingSessions.map(\.id),
            [controlSessionID, sessionID]
        )
        let healthyOtherDashboard = try await otherDashboard.fetchDashboardRecords()
        XCTAssertEqual(healthyOtherDashboard.workingSessions.map(\.id), [otherSessionID])
        XCTAssertNotNil(try primaryWorking.fetchSessionDetail(id: sessionID))

        // Deliberately corrupt the persisted snapshot/relationship agreement,
        // which direct Working always rejects but Dashboard previously skipped.
        let incorrectPastureID = UUID()
        let writeContext = try assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND id == %@",
                environment.herdID as NSUUID,
                sessionID as NSUUID
            )
            let session = try XCTUnwrap(writeContext.fetch(request).first)
            XCTAssertEqual(session.sourcePasture?.id, pasture.id)
            session.sourcePastureIDSnapshot = incorrectPastureID
            try writeContext.save()
        }

        func physicalSnapshots(
            in assembly: CoreDataPersistenceAssembly
        ) throws -> [String] {
            let context = assembly.contextFactory.makeReadContext()
            return try context.performAndWait {
                let request = NSFetchRequest<CDWorkingSession>(
                    entityName: CDWorkingSession.coreDataEntityName
                )
                return try context.fetch(request).map {
                    [
                        $0.herd.id.uuidString,
                        $0.id.uuidString,
                        $0.sourcePasture?.id.uuidString ?? "nil",
                        $0.sourcePastureIDSnapshot.uuidString,
                        $0.statusRawValue
                    ].joined(separator: "|")
                }.sorted()
            }
        }

        let baseline = try physicalSnapshots(in: assembly)
        let expectedError = CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
            relationship: "WorkingSession.sourcePasture",
            expectedID: incorrectPastureID,
            actualID: pasture.id
        )
        await XCTAssertThrowsErrorAsync(
            try await primaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingRepositoryError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataWorkingRepositoryError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: sessionID)) {
            XCTAssertEqual($0 as? CoreDataWorkingRepositoryError, expectedError)
        }
        // Targeted direct reads still expose an intact session; Dashboard is
        // an all-or-nothing combined read and must reject the corrupt one.
        XCTAssertNotNil(try primaryWorking.fetchSessionDetail(id: controlSessionID))
        XCTAssertEqual(try physicalSnapshots(in: assembly), baseline)
        let unchangedOtherDashboard = try await otherDashboard.fetchDashboardRecords()
        XCTAssertEqual(unchangedOtherDashboard.workingSessions.map(\.id), [otherSessionID])

        let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let reopenedPrimary = dashboard(in: readOnlyAssembly, selection: environment.selection)
        await XCTAssertThrowsErrorAsync(
            try await reopenedPrimary.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingRepositoryError, expectedError)
        }
        let reopenedOther = dashboard(in: readOnlyAssembly, selection: otherSelection)
        let reopenedOtherDashboard = try await reopenedOther.fetchDashboardRecords()
        XCTAssertEqual(reopenedOtherDashboard.workingSessions.map(\.id), [otherSessionID])
        XCTAssertEqual(try physicalSnapshots(in: readOnlyAssembly), baseline)
    }

    func testDashboardRejectsWorkingSessionIDCollisionOutsideActiveProjection() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = try CoreDataWorkingContractEnvironment(assembly: assembly)
        let primaryWorking = environment.makeWorkingRepository()

        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Dashboard Session Identity Pasture",
                acreage: 25,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )
        let animals = try (0..<3).map { index in
            try environment.makeAnimalRepository().create(
                input: Self.animalInput(
                    name: "Dashboard Session Identity Cow \(index)",
                    tagNumber: "DSI-\(index)",
                    pastureID: pasture.id
                )
            )
        }
        var sessionIDs: [UUID] = []
        for (index, animal) in animals.enumerated() {
            sessionIDs.append(
                try await primaryWorking.startSession(
                    input: WorkingSessionStartInput(
                        date: Date(timeIntervalSinceReferenceDate: 410_000 + Double(index)),
                        sourcePastureID: pasture.id,
                        treatmentTemplateName: "Dashboard Session \(index)",
                        plannedTreatments: [],
                        animalIDs: [animal.id]
                    )
                )
            )
        }
        let activeSessionID = sessionIDs[0]
        let finishedSessionID = sessionIDs[1]
        let controlSessionID = sessionIDs[2]

        let finishedQueueID = try XCTUnwrap(
            primaryWorking.fetchSessionDetail(id: finishedSessionID)?.queueItems.first?.id
        )
        try await primaryWorking.completeSession(
            id: finishedSessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: finishedQueueID,
                    destinationPastureID: nil
                )
            ]
        )

        let foreignHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: foreignHerdID,
            name: "Independent Dashboard Session Identity Herd"
        )
        let foreignSelection = CoreDataWorkingContractSelection()
        foreignSelection.currentHerdID = foreignHerdID
        let foreignPasture = try CoreDataPastureRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: PastureInput(
            name: "Foreign Dashboard Session Pasture",
            acreage: 20,
            usableAcreage: 18,
            targetAcresPerHead: 1.5
        ))
        let foreignAnimal = try CoreDataAnimalRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: Self.animalInput(
            name: "Foreign Dashboard Session Cow",
            tagNumber: "DSI-FOREIGN",
            pastureID: foreignPasture.id
        ))
        let foreignWorking = CoreDataWorkingRepository(
            selection: foreignSelection,
            assembly: assembly
        )
        let foreignSessionID = try await foreignWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 420_000),
                sourcePastureID: foreignPasture.id,
                treatmentTemplateName: "Foreign Dashboard Session",
                plannedTreatments: [],
                animalIDs: [foreignAnimal.id]
            )
        )

        // Cross-Herd reuse is valid; finished sessions must remain outside the
        // active Dashboard projection without leaving the identity scope.
        let writeContext = try assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND id == %@",
                foreignHerdID as NSUUID,
                foreignSessionID as NSUUID
            )
            let foreignSession = try XCTUnwrap(writeContext.fetch(request).first)
            foreignSession.id = activeSessionID
            try writeContext.save()
        }

        func dashboard(
            in assembly: CoreDataPersistenceAssembly,
            selection: CoreDataWorkingContractSelection
        ) -> CoreDataReadModelActor {
            CoreDataReadModelActor(
                contextFactory: assembly.contextFactory,
                lookup: assembly.lookup,
                currentHerdID: { selection.currentHerdID }
            )
        }

        let primaryDashboard = dashboard(in: assembly, selection: environment.selection)
        let foreignDashboard = dashboard(in: assembly, selection: foreignSelection)
        let healthyPrimary = try await primaryDashboard.fetchDashboardRecords()
        XCTAssertEqual(
            Set(healthyPrimary.workingSessions.map(\.id)),
            Set([activeSessionID, controlSessionID])
        )
        let healthyForeign = try await foreignDashboard.fetchDashboardRecords()
        XCTAssertEqual(healthyForeign.workingSessions.map(\.id), [activeSessionID])

        // The finished session shares the active session's application UUID,
        // but remains a distinct persisted Core Data row outside the 25-active
        // session fetch. The direct Working library must reject the same store.
        try writeContext.performAndWait {
            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND id == %@",
                environment.herdID as NSUUID,
                finishedSessionID as NSUUID
            )
            let finishedSession = try XCTUnwrap(writeContext.fetch(request).first)
            XCTAssertEqual(finishedSession.statusRawValue, WorkingSessionStatus.finished.rawValue)
            finishedSession.id = activeSessionID
            try writeContext.save()
        }

        func physicalSessions(
            in assembly: CoreDataPersistenceAssembly
        ) throws -> [String] {
            let context = assembly.contextFactory.makeReadContext()
            return try context.performAndWait {
                let request = NSFetchRequest<CDWorkingSession>(
                    entityName: CDWorkingSession.coreDataEntityName
                )
                return try context.fetch(request).map {
                    [
                        $0.herd.id.uuidString,
                        $0.id.uuidString,
                        $0.statusRawValue,
                        $0.treatmentTemplateNameSnapshot
                    ].joined(separator: "|")
                }.sorted()
            }
        }

        let baseline = try physicalSessions(in: assembly)
        XCTAssertEqual(baseline.count, 4)
        XCTAssertEqual(
            baseline.filter {
                $0.hasPrefix(environment.herdID.uuidString + "|" + activeSessionID.uuidString + "|")
            }.count,
            2
        )

        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDWorkingSession.coreDataEntityName,
            id: activeSessionID,
            herdID: environment.herdID
        )
        await XCTAssertThrowsErrorAsync(
            try await primaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertEqual(try physicalSessions(in: assembly), baseline)

        let unaffectedForeign = try await foreignDashboard.fetchDashboardRecords()
        XCTAssertEqual(unaffectedForeign.workingSessions.map(\.id), [activeSessionID])
        XCTAssertEqual(try foreignWorking.fetchSessions().map(\.id), [activeSessionID])

        let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let readOnlyPrimaryDashboard = dashboard(
            in: readOnlyAssembly,
            selection: environment.selection
        )
        await XCTAssertThrowsErrorAsync(
            try await readOnlyPrimaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        let readOnlyForeignDashboard = dashboard(
            in: readOnlyAssembly,
            selection: foreignSelection
        )
        let reopenedForeign = try await readOnlyForeignDashboard.fetchDashboardRecords()
        XCTAssertEqual(reopenedForeign.workingSessions.map(\.id), [activeSessionID])
        XCTAssertEqual(try physicalSessions(in: readOnlyAssembly), baseline)
    }

    func testWorkingQueueApplicationIDsMustBeUniqueAcrossSessionsInSelectedHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = try CoreDataWorkingContractEnvironment(assembly: assembly)
        let primaryWorking = environment.makeWorkingRepository()

        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Working Queue Identity Pasture",
                acreage: 22,
                usableAcreage: 19,
                targetAcresPerHead: 1.5
            )
        )
        let firstAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Queue Identity First Cow",
                tagNumber: "QI-1",
                pastureID: pasture.id
            )
        )
        let secondAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Queue Identity Second Cow",
                tagNumber: "QI-2",
                pastureID: pasture.id
            )
        )
        let controlAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Queue Identity Control Cow",
                tagNumber: "QI-3",
                pastureID: pasture.id
            )
        )
        let firstSessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 310_000),
                sourcePastureID: pasture.id,
                treatmentTemplateName: "First Queue Session",
                plannedTreatments: [],
                animalIDs: [firstAnimal.id]
            )
        )
        let secondSessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 320_000),
                sourcePastureID: pasture.id,
                treatmentTemplateName: "Second Queue Session",
                plannedTreatments: [],
                animalIDs: [secondAnimal.id]
            )
        )
        let controlSessionID = try await primaryWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 325_000),
                sourcePastureID: pasture.id,
                treatmentTemplateName: "Healthy Control Session",
                plannedTreatments: [],
                animalIDs: [controlAnimal.id]
            )
        )
        let duplicateID = try XCTUnwrap(
            primaryWorking.fetchSessionDetail(id: firstSessionID)?.queueItems.first?.id
        )
        let secondOriginalQueueID = try XCTUnwrap(
            primaryWorking.fetchSessionDetail(id: secondSessionID)?.queueItems.first?.id
        )
        let healthyQueueID = try XCTUnwrap(
            primaryWorking.fetchSessionDetail(id: controlSessionID)?
                .queueItems.first(where: { $0.animalID == controlAnimal.id })?.id
        )

        let foreignHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: foreignHerdID,
            name: "Independent Queue Identity Herd"
        )
        let foreignSelection = CoreDataWorkingContractSelection()
        foreignSelection.currentHerdID = foreignHerdID
        let foreignPasture = try CoreDataPastureRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: PastureInput(
            name: "Foreign Queue Identity Pasture",
            acreage: 20,
            usableAcreage: 18,
            targetAcresPerHead: 1.5
        ))
        let foreignAnimal = try CoreDataAnimalRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: Self.animalInput(
            name: "Foreign Queue Identity Cow",
            tagNumber: "QI-FOREIGN",
            pastureID: foreignPasture.id
        ))
        let foreignWorking = CoreDataWorkingRepository(
            selection: foreignSelection,
            assembly: assembly
        )
        let foreignSessionID = try await foreignWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 330_000),
                sourcePastureID: foreignPasture.id,
                treatmentTemplateName: "Foreign Queue Session",
                plannedTreatments: [],
                animalIDs: [foreignAnimal.id]
            )
        )

        let primaryDashboard = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        let foreignDashboard = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: { foreignSelection.currentHerdID }
        )
        let healthyDashboard = try await primaryDashboard.fetchDashboardRecords()
        XCTAssertEqual(
            Set(healthyDashboard.workingSessions.map(\.id)),
            Set([firstSessionID, secondSessionID, controlSessionID])
        )
        let healthyForeignDashboard = try await foreignDashboard.fetchDashboardRecords()
        XCTAssertEqual(healthyForeignDashboard.workingSessions.map(\.id), [foreignSessionID])

        // Physically duplicate one UUID across two different sessions in the
        // selected Herd. Reusing that UUID in another Herd must remain valid.
        let writeContext = try assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            func queueItems(in sessionID: UUID) throws -> [CDWorkingQueueItem] {
                let request = NSFetchRequest<CDWorkingQueueItem>(
                    entityName: CDWorkingQueueItem.coreDataEntityName
                )
                request.predicate = NSPredicate(
                    format: "session.id == %@",
                    sessionID as NSUUID
                )
                return try writeContext.fetch(request)
            }

            XCTAssertEqual(try queueItems(in: firstSessionID).count, 1)
            let collidingQueue = try XCTUnwrap(
                queueItems(in: secondSessionID).first {
                    $0.animalIDSnapshot == secondAnimal.id
                }
            )
            let foreignQueue = try XCTUnwrap(queueItems(in: foreignSessionID).first)
            collidingQueue.id = duplicateID
            foreignQueue.id = duplicateID
            try writeContext.save()
        }

        func physicalQueueState(in assembly: CoreDataPersistenceAssembly) throws -> [String] {
            let context = assembly.contextFactory.makeReadContext()
            return try context.performAndWait {
                let request = NSFetchRequest<CDWorkingQueueItem>(
                    entityName: CDWorkingQueueItem.coreDataEntityName
                )
                return try context.fetch(request).map {
                    [
                        $0.herd.id.uuidString,
                        $0.session.id.uuidString,
                        $0.id.uuidString,
                        $0.animalIDSnapshot.uuidString,
                        $0.statusRawValue
                    ].joined(separator: "|")
                }.sorted()
            }
        }

        let baseline = try physicalQueueState(in: assembly)
        XCTAssertEqual(baseline.count, 4)
        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDWorkingQueueItem.coreDataEntityName,
            id: duplicateID,
            herdID: environment.herdID
        )

        await XCTAssertThrowsErrorAsync(
            try await primaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }

        XCTAssertThrowsError(try primaryWorking.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: firstSessionID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: secondSessionID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: controlSessionID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        // The requested queue has a healthy UUID: the editor must still fail
        // if some other session in its selected Herd has ambiguous identities.
        XCTAssertThrowsError(
            try primaryWorking.fetchQueueItemEditor(
                sessionID: controlSessionID,
                queueItemID: healthyQueueID
            )
        ) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertEqual(try physicalQueueState(in: assembly), baseline)

        let foreignDetail = try XCTUnwrap(
            foreignWorking.fetchSessionDetail(id: foreignSessionID)
        )
        XCTAssertEqual(foreignDetail.queueItems.map(\.id), [duplicateID])
        XCTAssertEqual(try foreignWorking.fetchSessions().map(\.id), [foreignSessionID])
        let unaffectedForeignDashboard = try await foreignDashboard.fetchDashboardRecords()
        XCTAssertEqual(unaffectedForeignDashboard.workingSessions.map(\.id), [foreignSessionID])

        let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let readOnlyPrimary = CoreDataWorkingRepository(
            selection: environment.selection,
            assembly: readOnlyAssembly
        )
        let readOnlyPrimaryDashboard = CoreDataReadModelActor(
            contextFactory: readOnlyAssembly.contextFactory,
            lookup: readOnlyAssembly.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await readOnlyPrimaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try readOnlyPrimary.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try readOnlyPrimary.fetchSessionDetail(id: firstSessionID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        let readOnlyForeign = CoreDataWorkingRepository(
            selection: foreignSelection,
            assembly: readOnlyAssembly
        )
        XCTAssertEqual(
            try readOnlyForeign.fetchSessionDetail(id: foreignSessionID),
            foreignDetail
        )
        let readOnlyForeignDashboard = CoreDataReadModelActor(
            contextFactory: readOnlyAssembly.contextFactory,
            lookup: readOnlyAssembly.lookup,
            currentHerdID: { foreignSelection.currentHerdID }
        )
        let reopenedForeignDashboard = try await readOnlyForeignDashboard.fetchDashboardRecords()
        XCTAssertEqual(reopenedForeignDashboard.workingSessions.map(\.id), [foreignSessionID])
        XCTAssertEqual(try physicalQueueState(in: readOnlyAssembly), baseline)

        // The earlier collision was between two displayed active sessions.
        // A finished session is not included in Dashboard's 25 active rows,
        // but its queue UUID remains part of the same selected-Herd identity.
        // Restore the original UUID before finishing via the real write path.
        func updateSecondQueueID(_ id: UUID) throws {
            try writeContext.performAndWait {
                let request = NSFetchRequest<CDWorkingQueueItem>(
                    entityName: CDWorkingQueueItem.coreDataEntityName
                )
                request.predicate = NSPredicate(
                    format: "session.id == %@",
                    secondSessionID as NSUUID
                )
                let item = try XCTUnwrap(writeContext.fetch(request).first)
                item.id = id
                try writeContext.save()
            }
        }
        try updateSecondQueueID(secondOriginalQueueID)
        try await primaryWorking.completeSession(
            id: secondSessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: secondOriginalQueueID,
                    destinationPastureID: nil
                )
            ]
        )

        let completedHealthyDashboard = try await primaryDashboard.fetchDashboardRecords()
        XCTAssertEqual(
            Set(completedHealthyDashboard.workingSessions.map(\.id)),
            Set([firstSessionID, controlSessionID])
        )
        XCTAssertEqual(
            Set(try primaryWorking.fetchSessions().map(\.id)),
            Set([firstSessionID, secondSessionID, controlSessionID])
        )

        // Reintroduce the *same* physical collision, now in a finished session
        // outside the Dashboard active-session predicate. The direct Working
        // library still refuses it; independently projected Dashboard/Home
        // must also fail rather than displaying the healthy active session.
        try updateSecondQueueID(duplicateID)
        let finishedCollisionState = try physicalQueueState(in: assembly)
        XCTAssertEqual(finishedCollisionState.count, 4)
        await XCTAssertThrowsErrorAsync(
            try await primaryDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try primaryWorking.fetchSessions()) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertEqual(try physicalQueueState(in: assembly), finishedCollisionState)
        let stillHealthyForeignDashboard = try await foreignDashboard.fetchDashboardRecords()
        XCTAssertEqual(stillHealthyForeignDashboard.workingSessions.map(\.id), [foreignSessionID])

        let finishedReadOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let finishedReadOnlyDashboard = CoreDataReadModelActor(
            contextFactory: finishedReadOnlyAssembly.contextFactory,
            lookup: finishedReadOnlyAssembly.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await finishedReadOnlyDashboard.fetchDashboardRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertEqual(
            try physicalQueueState(in: finishedReadOnlyAssembly),
            finishedCollisionState
        )
    }

    func testWorkingTreatmentRecordApplicationIDsMustBeUniqueAcrossSessionsInSelectedHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = try CoreDataWorkingContractEnvironment(assembly: assembly)
        let primaryWorking = environment.makeWorkingRepository()

        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Treatment Identity Pasture",
                acreage: 22,
                usableAcreage: 19,
                targetAcresPerHead: 1.5
            )
        )
        let firstAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Treatment Identity First Cow",
                tagNumber: "TI-1",
                pastureID: pasture.id
            )
        )
        let secondAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Treatment Identity Second Cow",
                tagNumber: "TI-2",
                pastureID: pasture.id
            )
        )
        let controlAnimal = try environment.makeAnimalRepository().create(
            input: Self.animalInput(
                name: "Treatment Identity Healthy Cow",
                tagNumber: "TI-3",
                pastureID: pasture.id
            )
        )

        func startSession(
            animalID: UUID,
            date: Date,
            name: String
        ) async throws -> (sessionID: UUID, queueID: UUID) {
            let sessionID = try await primaryWorking.startSession(
                input: WorkingSessionStartInput(
                    date: date,
                    sourcePastureID: pasture.id,
                    treatmentTemplateName: name,
                    plannedTreatments: [],
                    animalIDs: [animalID]
                )
            )
            let queueID = try XCTUnwrap(
                primaryWorking.fetchSessionDetail(id: sessionID)?.queueItems.first?.id
            )
            return (sessionID, queueID)
        }

        let first = try await startSession(
            animalID: firstAnimal.id,
            date: Date(timeIntervalSinceReferenceDate: 340_000),
            name: "First Treatment Session"
        )
        let second = try await startSession(
            animalID: secondAnimal.id,
            date: Date(timeIntervalSinceReferenceDate: 350_000),
            name: "Second Treatment Session"
        )
        let control = try await startSession(
            animalID: controlAnimal.id,
            date: Date(timeIntervalSinceReferenceDate: 355_000),
            name: "Untouched Treatment Session"
        )

        let foreignHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: foreignHerdID,
            name: "Independent Treatment Identity Herd"
        )
        let foreignSelection = CoreDataWorkingContractSelection()
        foreignSelection.currentHerdID = foreignHerdID
        let foreignPasture = try CoreDataPastureRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: PastureInput(
            name: "Independent Treatment Pasture",
            acreage: 20,
            usableAcreage: 18,
            targetAcresPerHead: 1.5
        ))
        let foreignAnimal = try CoreDataAnimalRepository(
            selection: foreignSelection,
            assembly: assembly
        ).create(input: Self.animalInput(
            name: "Independent Treatment Cow",
            tagNumber: "TI-FOREIGN",
            pastureID: foreignPasture.id
        ))
        let foreignWorking = CoreDataWorkingRepository(
            selection: foreignSelection,
            assembly: assembly
        )
        let foreignSessionID = try await foreignWorking.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSinceReferenceDate: 360_000),
                sourcePastureID: foreignPasture.id,
                treatmentTemplateName: "Independent Treatment Session",
                plannedTreatments: [],
                animalIDs: [foreignAnimal.id]
            )
        )
        let foreignQueueID = try XCTUnwrap(
            foreignWorking.fetchSessionDetail(id: foreignSessionID)?.queueItems.first?.id
        )

        func entry(at date: Date) -> WorkingTreatmentEntryInput {
            WorkingTreatmentEntryInput(
                date: date,
                treatmentItemID: UUID(),
                itemName: "One-off Treatment",
                given: true,
                dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
            )
        }
        try await primaryWorking.complete(
            queueItemID: first.queueID,
            inSessionID: first.sessionID,
            treatmentEntries: [entry(at: Date(timeIntervalSinceReferenceDate: 341_000))],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        try await primaryWorking.complete(
            queueItemID: second.queueID,
            inSessionID: second.sessionID,
            treatmentEntries: [entry(at: Date(timeIntervalSinceReferenceDate: 351_000))],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        try await foreignWorking.complete(
            queueItemID: foreignQueueID,
            inSessionID: foreignSessionID,
            treatmentEntries: [entry(at: Date(timeIntervalSinceReferenceDate: 361_000))],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        let duplicateID = try XCTUnwrap(
            primaryWorking.fetchQueueItemEditor(
                sessionID: first.sessionID,
                queueItemID: first.queueID
            )?.treatmentRecords.first?.id
        )
        XCTAssertEqual(
            try primaryWorking.fetchQueueItemEditor(
                sessionID: second.sessionID,
                queueItemID: second.queueID
            )?.treatmentRecords.count,
            1
        )
        XCTAssertEqual(
            try primaryWorking.fetchSessions().count,
            3
        )

        let writeContext = try assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            func treatment(in sessionID: UUID) throws -> CDWorkingTreatmentRecord {
                let request = NSFetchRequest<CDWorkingTreatmentRecord>(
                    entityName: CDWorkingTreatmentRecord.coreDataEntityName
                )
                request.predicate = NSPredicate(
                    format: "session.id == %@",
                    sessionID as NSUUID
                )
                let records = try writeContext.fetch(request)
                XCTAssertEqual(records.count, 1)
                return try XCTUnwrap(records.first)
            }

            let collidingTreatment = try treatment(in: second.sessionID)
            let foreignTreatment = try treatment(in: foreignSessionID)
            collidingTreatment.id = duplicateID
            foreignTreatment.id = duplicateID
            try writeContext.save()
        }

        func physicalTreatmentRows(in assembly: CoreDataPersistenceAssembly) throws -> [String] {
            let context = assembly.contextFactory.makeReadContext()
            return try context.performAndWait {
                let request = NSFetchRequest<CDWorkingTreatmentRecord>(
                    entityName: CDWorkingTreatmentRecord.coreDataEntityName
                )
                return try context.fetch(request).map {
                    [
                        $0.herd.id.uuidString,
                        $0.session.id.uuidString,
                        $0.animalIDSnapshot.uuidString,
                        $0.id.uuidString,
                        $0.treatmentItemID.uuidString,
                        $0.itemNameSnapshot,
                        String($0.given),
                        String($0.date.timeIntervalSinceReferenceDate)
                    ].joined(separator: "|")
                }.sorted()
            }
        }

        let baseline = try physicalTreatmentRows(in: assembly)
        XCTAssertEqual(baseline.count, 3)
        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDWorkingTreatmentRecord.coreDataEntityName,
            id: duplicateID,
            herdID: environment.herdID
        )

        XCTAssertThrowsError(try primaryWorking.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        for sessionID in [first.sessionID, second.sessionID, control.sessionID] {
            XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: sessionID)) {
                XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
            }
        }
        for target in [first, second, control] {
            XCTAssertThrowsError(
                try primaryWorking.fetchQueueItemEditor(
                    sessionID: target.sessionID,
                    queueItemID: target.queueID
                )
            ) {
                XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
            }
        }
        XCTAssertEqual(try physicalTreatmentRows(in: assembly), baseline)

        let foreignDetail = try XCTUnwrap(
            foreignWorking.fetchSessionDetail(id: foreignSessionID)
        )
        XCTAssertEqual(try foreignWorking.fetchSessions().map(\.id), [foreignSessionID])
        XCTAssertEqual(
            try foreignWorking.fetchQueueItemEditor(
                sessionID: foreignSessionID,
                queueItemID: foreignQueueID
            )?.treatmentRecords.map(\.id),
            [duplicateID]
        )

        let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let readOnlyPrimary = CoreDataWorkingRepository(
            selection: environment.selection,
            assembly: readOnlyAssembly
        )
        XCTAssertThrowsError(try readOnlyPrimary.fetchSessions()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try readOnlyPrimary.fetchSessionDetail(id: control.sessionID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(
            try readOnlyPrimary.fetchQueueItemEditor(
                sessionID: control.sessionID,
                queueItemID: control.queueID
            )
        ) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        let readOnlyForeign = CoreDataWorkingRepository(
            selection: foreignSelection,
            assembly: readOnlyAssembly
        )
        XCTAssertEqual(
            try readOnlyForeign.fetchSessionDetail(id: foreignSessionID),
            foreignDetail
        )
        XCTAssertEqual(
            try readOnlyForeign.fetchQueueItemEditor(
                sessionID: foreignSessionID,
                queueItemID: foreignQueueID
            )?.treatmentRecords.map(\.id),
            [duplicateID]
        )
        XCTAssertEqual(try physicalTreatmentRows(in: readOnlyAssembly), baseline)
    }

    func testWorkingHealthAndPregnancyApplicationIDsAreUniqueAcrossSelectedHerd() async throws {
        enum RecordKind: CaseIterable {
            case health
            case pregnancy

            var entityName: String {
                switch self {
                case .health: CDHealthRecord.coreDataEntityName
                case .pregnancy: CDPregnancyCheck.coreDataEntityName
                }
            }
        }

        enum CollisionOrigin: CaseIterable {
            case anotherWorkingSession
            case standaloneAnimalHistory
        }

        // Both Working-to-Working and Working-to-standalone collisions are
        // violations of the same Herd-owned history-record identity scope.
        for kind in RecordKind.allCases {
            for origin in CollisionOrigin.allCases {
                let harness = try CoreDataPersistenceHarness()
                let assembly = try await harness.makeAssembly()
                let environment = try CoreDataWorkingContractEnvironment(assembly: assembly)
                let primaryAnimals = environment.makeAnimalRepository()
                let primaryWorking = environment.makeCoreWorkingRepository()
                let pasture = try environment.makePastureRepository().create(
                    input: PastureInput(
                        name: "Working History Identity Pasture",
                        acreage: 24,
                        usableAcreage: 20,
                        targetAcresPerHead: 1.5
                    )
                )

                let firstAnimal = try primaryAnimals.create(input: Self.animalInput(
                    name: "History First Cow",
                    tagNumber: "HI-1",
                    pastureID: pasture.id
                ))
                let secondAnimal = try primaryAnimals.create(input: Self.animalInput(
                    name: "History Second Cow",
                    tagNumber: "HI-2",
                    pastureID: pasture.id
                ))
                let controlAnimal = try primaryAnimals.create(input: Self.animalInput(
                    name: "History Standalone Cow",
                    tagNumber: "HI-3",
                    pastureID: pasture.id
                ))

                func startAndWork(
                    repository: CoreDataWorkingRepository,
                    animalID: UUID,
                    sourcePastureID: UUID,
                    at date: Date
                ) async throws -> (sessionID: UUID, queueID: UUID) {
                    let sessionID = try await repository.startSession(
                        input: WorkingSessionStartInput(
                            date: date,
                            sourcePastureID: sourcePastureID,
                            treatmentTemplateName: "History Identity Session",
                            plannedTreatments: [],
                            animalIDs: [animalID]
                        )
                    )
                    let queueID = try XCTUnwrap(
                        repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id
                    )
                    try await repository.complete(
                        queueItemID: queueID,
                        inSessionID: sessionID,
                        treatmentEntries: [],
                        pregnancyCheck: WorkingPregnancyCheckInput(
                            date: date,
                            result: .open,
                            estimatedDaysPregnant: nil,
                            dueDate: nil,
                            sireAnimalID: nil
                        ),
                        markCastrated: false,
                        observationNotes: "Work observation"
                    )
                    return (sessionID, queueID)
                }

                let first = try await startAndWork(
                    repository: primaryWorking,
                    animalID: firstAnimal.id,
                    sourcePastureID: pasture.id,
                    at: Date(timeIntervalSinceReferenceDate: 380_000)
                )
                let second = try await startAndWork(
                    repository: primaryWorking,
                    animalID: secondAnimal.id,
                    sourcePastureID: pasture.id,
                    at: Date(timeIntervalSinceReferenceDate: 381_000)
                )
                let controlSessionID = try await primaryWorking.startSession(
                    input: WorkingSessionStartInput(
                        date: Date(timeIntervalSinceReferenceDate: 382_000),
                        sourcePastureID: pasture.id,
                        treatmentTemplateName: "Unmodified Working Control",
                        plannedTreatments: [],
                        animalIDs: [controlAnimal.id]
                    )
                )
                let controlQueueID = try XCTUnwrap(
                    primaryWorking.fetchSessionDetail(id: controlSessionID)?.queueItems.first?.id
                )

                _ = try primaryAnimals.addHealthRecord(
                    animalID: controlAnimal.id,
                    input: HealthRecordInput(
                        date: Date(timeIntervalSinceReferenceDate: 382_100),
                        treatment: "Standalone observation",
                        notes: "Independent Animal history"
                    )
                )
                _ = try primaryAnimals.addPregnancyCheck(
                    animalID: controlAnimal.id,
                    input: PregnancyCheckInput(
                        date: Date(timeIntervalSinceReferenceDate: 382_200),
                        result: .open,
                        technician: nil,
                        estimatedDaysPregnant: nil,
                        dueDate: nil,
                        sireAnimalID: nil
                    )
                )

                let foreignHerdID = UUID()
                try environment.seedAdditionalHerd(
                    id: foreignHerdID,
                    name: "Independent History Identity Herd"
                )
                let foreignSelection = CoreDataWorkingContractSelection()
                foreignSelection.currentHerdID = foreignHerdID
                let foreignPasture = try CoreDataPastureRepository(
                    selection: foreignSelection,
                    assembly: assembly
                ).create(input: PastureInput(
                    name: "Foreign History Pasture",
                    acreage: 20,
                    usableAcreage: 18,
                    targetAcresPerHead: 1.5
                ))
                let foreignAnimal = try CoreDataAnimalRepository(
                    selection: foreignSelection,
                    assembly: assembly
                ).create(input: Self.animalInput(
                    name: "Foreign History Cow",
                    tagNumber: "HI-F",
                    pastureID: foreignPasture.id
                ))
                let foreignWorking = CoreDataWorkingRepository(
                    selection: foreignSelection,
                    assembly: assembly
                )
                let foreign = try await startAndWork(
                    repository: foreignWorking,
                    animalID: foreignAnimal.id,
                    sourcePastureID: foreignPasture.id,
                    at: Date(timeIntervalSinceReferenceDate: 383_000)
                )
                XCTAssertEqual(try primaryWorking.fetchSessions().count, 3)
                XCTAssertEqual(try foreignWorking.fetchSessions().count, 1)

                // Create the collision in *persisted* records, not a Domain
                // snapshot. The independent Herd intentionally reuses the ID.
                let writeContext = try assembly.contextFactory.makeWriteContext()
                let duplicateID = try writeContext.performAndWait { () throws -> UUID in
                    switch kind {
                    case .health:
                        let records = try writeContext.fetch(
                            NSFetchRequest<CDHealthRecord>(
                                entityName: CDHealthRecord.coreDataEntityName
                            )
                        )
                        let source = try XCTUnwrap(records.first {
                            $0.workingSession?.id == first.sessionID
                        })
                        let colliding = try XCTUnwrap(records.first {
                            switch origin {
                            case .anotherWorkingSession:
                                return $0.workingSession?.id == second.sessionID
                            case .standaloneAnimalHistory:
                                return $0.workingSession == nil
                                    && $0.animal.id == controlAnimal.id
                            }
                        })
                        let foreignRecord = try XCTUnwrap(records.first {
                            $0.workingSession?.id == foreign.sessionID
                        })
                        colliding.id = source.id
                        foreignRecord.id = source.id
                        try writeContext.save()
                        return source.id
                    case .pregnancy:
                        let records = try writeContext.fetch(
                            NSFetchRequest<CDPregnancyCheck>(
                                entityName: CDPregnancyCheck.coreDataEntityName
                            )
                        )
                        let source = try XCTUnwrap(records.first {
                            $0.workingSession?.id == first.sessionID
                        })
                        let colliding = try XCTUnwrap(records.first {
                            switch origin {
                            case .anotherWorkingSession:
                                return $0.workingSession?.id == second.sessionID
                            case .standaloneAnimalHistory:
                                return $0.workingSession == nil
                                    && $0.animal.id == controlAnimal.id
                            }
                        })
                        let foreignRecord = try XCTUnwrap(records.first {
                            $0.workingSession?.id == foreign.sessionID
                        })
                        colliding.id = source.id
                        foreignRecord.id = source.id
                        try writeContext.save()
                        return source.id
                    }
                }

                func physicalRows(in assembly: CoreDataPersistenceAssembly) throws -> [String] {
                    let context = assembly.contextFactory.makeReadContext()
                    return try context.performAndWait {
                        switch kind {
                        case .health:
                            return try context.fetch(NSFetchRequest<CDHealthRecord>(
                                entityName: CDHealthRecord.coreDataEntityName
                            )).map {
                                [
                                    $0.herd.id.uuidString,
                                    $0.animal.id.uuidString,
                                    $0.workingSession?.id.uuidString ?? "standalone",
                                    $0.id.uuidString,
                                    $0.treatment,
                                    $0.notes ?? "",
                                    String($0.date.timeIntervalSinceReferenceDate)
                                ].joined(separator: "|")
                            }.sorted()
                        case .pregnancy:
                            return try context.fetch(NSFetchRequest<CDPregnancyCheck>(
                                entityName: CDPregnancyCheck.coreDataEntityName
                            )).map {
                                [
                                    $0.herd.id.uuidString,
                                    $0.animal.id.uuidString,
                                    $0.workingSession?.id.uuidString ?? "standalone",
                                    $0.id.uuidString,
                                    $0.resultRawValue,
                                    String($0.date.timeIntervalSinceReferenceDate)
                                ].joined(separator: "|")
                            }.sorted()
                        }
                    }
                }

                let baseline = try physicalRows(in: assembly)
                XCTAssertEqual(baseline.count, 4)
                let expected = CoreDataPersistenceError.duplicateApplicationID(
                    entity: kind.entityName,
                    id: duplicateID,
                    herdID: environment.herdID
                )
                XCTAssertThrowsError(try primaryWorking.fetchSessions()) {
                    XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                }
                for id in [first.sessionID, second.sessionID, controlSessionID] {
                    XCTAssertThrowsError(try primaryWorking.fetchSessionDetail(id: id)) {
                        XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                    }
                }
                for target in [
                    (first.sessionID, first.queueID),
                    (second.sessionID, second.queueID),
                    (controlSessionID, controlQueueID)
                ] {
                    XCTAssertThrowsError(try primaryWorking.fetchQueueItemEditor(
                        sessionID: target.0,
                        queueItemID: target.1
                    )) {
                        XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                    }
                }
                XCTAssertEqual(try physicalRows(in: assembly), baseline)

                // Same UUID remains legitimate in a different Herd.
                XCTAssertEqual(try foreignWorking.fetchSessions().map(\.id), [foreign.sessionID])
                XCTAssertNotNil(try foreignWorking.fetchSessionDetail(id: foreign.sessionID))
                XCTAssertNotNil(try foreignWorking.fetchQueueItemEditor(
                    sessionID: foreign.sessionID,
                    queueItemID: foreign.queueID
                ))

                let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
                let readOnlyPrimary = CoreDataWorkingRepository(
                    selection: environment.selection,
                    assembly: readOnlyAssembly
                )
                XCTAssertThrowsError(try readOnlyPrimary.fetchSessions()) {
                    XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                }
                XCTAssertThrowsError(try readOnlyPrimary.fetchSessionDetail(
                    id: controlSessionID
                )) {
                    XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                }
                XCTAssertThrowsError(try readOnlyPrimary.fetchQueueItemEditor(
                    sessionID: controlSessionID,
                    queueItemID: controlQueueID
                )) {
                    XCTAssertEqual($0 as? CoreDataPersistenceError, expected)
                }
                let readOnlyForeign = CoreDataWorkingRepository(
                    selection: foreignSelection,
                    assembly: readOnlyAssembly
                )
                XCTAssertNotNil(try readOnlyForeign.fetchSessionDetail(id: foreign.sessionID))
                XCTAssertNotNil(try readOnlyForeign.fetchQueueItemEditor(
                    sessionID: foreign.sessionID,
                    queueItemID: foreign.queueID
                ))
                XCTAssertEqual(try physicalRows(in: readOnlyAssembly), baseline)
            }
        }
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

    var historicalStatusInjection: WorkingHistoricalStatusInjection {
        WorkingHistoricalStatusInjection(
            setPersistedStatuses: { sessionID, queueItemID, sessionStatus, queueStatus in
                let context = try self.assembly.contextFactory.makeWriteContext()
                let herdID = self.herdID
                let lookup = CoreDataLookup()
                try context.performAndWait {
                    guard let session = try lookup.herdOwned(
                        CDWorkingSession.self,
                        id: sessionID,
                        herdID: herdID,
                        in: context
                    ), let queueItem = try lookup.herdOwned(
                        CDWorkingQueueItem.self,
                        id: queueItemID,
                        herdID: herdID,
                        in: context
                    ) else {
                        throw WorkingRepositoryError.sessionNotFound
                    }
                    session.statusRawValue = sessionStatus.rawValue
                    queueItem.statusRawValue = queueStatus.rawValue
                    try context.save()
                }
            }
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
                _ = try await self.makeCoreWorkingRepository().replacePrimaryTag(
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
