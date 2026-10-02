import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataFieldCheckRepositoryContractTests: XCTestCase {
    func testFieldCheckReadsAndMutationsStayWithinSelectedHerd() async throws {
        let environment = try await makeEnvironment()
        let primaryPasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Primary Herd Field Check",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let primaryRepository = environment.makeFieldCheckRepository()
        let primarySessionID = try await primaryRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: primaryPasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 90_000),
                notes: "Primary herd session"
            )
        )
        try await primaryRepository.addFinding(
            sessionID: primarySessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSinceReferenceDate: 90_100),
                type: .fenceIssue,
                severity: .warning,
                status: .open,
                note: "Primary herd finding",
                animalID: nil
            )
        )

        let otherHerdID = UUID()
        try environment.seedAdditionalHerd(
            id: otherHerdID,
            name: "Other Field Check Contract Herd"
        )
        let otherSelection = CoreDataFieldCheckContractSelection()
        otherSelection.currentHerdID = otherHerdID
        let otherPasture = try CoreDataPastureRepository(
            selection: otherSelection,
            assembly: environment.assembly
        ).create(
            input: PastureInput(
                name: "Other Herd Field Check",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let otherRepository = CoreDataFieldCheckRepository(
            selection: otherSelection,
            assembly: environment.assembly
        )
        let otherSessionID = try await otherRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: otherPasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 90_200),
                notes: "Other herd session"
            )
        )
        try await otherRepository.addFinding(
            sessionID: otherSessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSinceReferenceDate: 90_300),
                type: .waterIssue,
                severity: .critical,
                status: .open,
                note: "Other herd finding",
                animalID: nil
            )
        )

        XCTAssertEqual(
            Set(try primaryRepository.fetchSessions().map(\.id)),
            Set([primarySessionID])
        )
        XCTAssertEqual(
            try primaryRepository.fetchOpenFindings(limit: 0).map(\.note),
            ["Primary herd finding"]
        )
        XCTAssertNil(
            try primaryRepository.fetchSessionDetail(id: otherSessionID)
        )
        do {
            try await primaryRepository.updateNotes(
                sessionID: otherSessionID,
                notes: "Must not cross Herd boundary"
            )
            XCTFail("Expected sessionNotFound for a session owned by another Herd.")
        } catch {
            guard let repositoryError = error as? FieldCheckRepositoryError,
                  case .sessionNotFound = repositoryError else {
                XCTFail("Expected sessionNotFound for a session owned by another Herd, received \(error).")
                return
            }
        }

        XCTAssertEqual(
            Set(try otherRepository.fetchSessions().map(\.id)),
            Set([otherSessionID])
        )
        XCTAssertEqual(
            try otherRepository.fetchOpenFindings(limit: 0).map(\.note),
            ["Other herd finding"]
        )
        XCTAssertNil(
            try otherRepository.fetchSessionDetail(id: primarySessionID)
        )
    }

    func testCorruptPersistedFieldCheckEnumsFailProjection() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Corrupt Enum Field Check",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try environment.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Corrupt Enum Animal",
                tagNumber: "CE-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 10_000),
                status: .active,
                pastureID: pasture.id,
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
        )
        let repository = environment.makeFieldCheckRepository()
        let sessionID = try await repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 91_000),
                notes: "Corrupt enum projection"
            )
        )
        try await repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSinceReferenceDate: 91_100),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Corrupt me",
                animalID: animal.id
            )
        )
        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detail.findings.first?.id)
        let checkID = try XCTUnwrap(detail.animalChecks.first?.id)

        try environment.setFindingRawValue(
            findingID: findingID,
            key: "typeRawValue",
            value: "not-a-finding-type"
        )
        XCTAssertThrowsError(
            try environment.makeFieldCheckRepository().fetchSessionDetail(id: sessionID)
        ) { error in
            XCTAssertEqual(
                error as? CoreDataFieldCheckMappingError,
                .invalidFindingType(
                    findingID: findingID,
                    value: "not-a-finding-type"
                )
            )
        }

        try environment.setFindingRawValue(
            findingID: findingID,
            key: "typeRawValue",
            value: FieldCheckFindingType.generalObservation.rawValue
        )
        try environment.setAnimalCheckRawValue(
            animalCheckID: checkID,
            key: "animalTypeRawValueSnapshot",
            value: "not-an-animal-type"
        )
        XCTAssertThrowsError(
            try environment.makeFieldCheckRepository().fetchSessionDetail(id: sessionID)
        ) { error in
            XCTAssertEqual(
                error as? CoreDataFieldCheckMappingError,
                .invalidAnimalType(
                    checkID: checkID,
                    value: "not-an-animal-type"
                )
            )
        }

        try environment.setAnimalCheckRawValue(
            animalCheckID: checkID,
            key: "animalTypeRawValueSnapshot",
            value: detail.animalChecks[0].animalType.rawValue
        )
        try environment.setFindingRawValue(
            findingID: findingID,
            key: "statusRawValue",
            value: "not-a-finding-status"
        )
        XCTAssertThrowsError(
            try environment.makeFieldCheckRepository().fetchOpenFindings(limit: 0)
        ) { error in
            XCTAssertEqual(
                error as? CoreDataFieldCheckMappingError,
                .invalidFindingStatus(
                    findingID: findingID,
                    value: "not-a-finding-status"
                )
            )
        }
    }

    func testSessionCreationAndReadProjections() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertSessionCreationAndReadProjections(
            using: environment.fixture
        )
    }

    func testMutableCountsNotesAndRosterStateSurviveReload() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMutableCountsNotesAndRosterStateSurviveReload(
            using: environment.fixture
        )
    }

    func testTrackedAnimalAdditionPersistsRosterAndDestination() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertTrackedAnimalAdditionPersistsRosterAndDestination(
            using: environment.fixture
        )
    }

    func testFindingLifecycleAndOpenFindingReader() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertFindingLifecycleAndOpenFindingReader(
            using: environment.fixture
        )
    }

    func testHistoricalSnapshotsSurviveLiveRecordChanges() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertHistoricalSnapshotsSurviveLiveRecordChanges(
            using: environment.fixture
        )
    }

    func testCompletionReopenAndEditLocking() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertCompletionReopenAndEditLocking(
            using: environment.fixture
        )
    }

    func testMissingRecordErrors() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingRecordErrors(
            using: environment.fixture
        )
    }

    func testChildMutationIDsAreSessionScoped() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertChildMutationIDsAreSessionScoped(
            using: environment.fixture
        )
    }

    func testHardDeletedAnimalPreservesHistoricalSnapshots() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertHardDeletedAnimalPreservesHistoricalSnapshots(
            using: environment.fixture
        )
    }

    func testCompletedSessionMissingFindingStatusSynchronization() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertCompletedSessionMissingFindingStatusSynchronization(
            using: environment.fixture
        )
    }

    func testUntaggedFindingNameSnapshotSurvivesLiveRename() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertUntaggedFindingNameSnapshotSurvivesLiveRename(
            using: environment.fixture
        )
    }

    func testFindingWritesPreserveHistoricalSnapshotsAfterLiveRecordChanges() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertFindingWritesPreserveHistoricalSnapshotsAfterLiveRecordChanges(
            using: environment.fixture
        )
    }

    func testLinkedFindingAttentionProjections() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertLinkedFindingAttentionProjections(
            using: environment.fixture
        )
    }

    func testUnlinkedFindingDoesNotFlagRosterAnimals() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertUnlinkedFindingDoesNotFlagRosterAnimals(
            using: environment.fixture
        )
    }

    func testMissingFindingResolutionAndDeletionSynchronizeRoster() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingResolutionAndDeletionSynchronizeRoster(
            using: environment.fixture
        )
    }

    func testOrphanedMissingFindingStatusSynchronization() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertOrphanedMissingFindingStatusSynchronization(
            using: environment.fixture
        )
    }

    func testFindingReassignmentUsesSessionRosterSnapshotAfterLiveRecordChanges() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertFindingReassignmentUsesSessionRosterSnapshotAfterLiveRecordChanges(
            using: environment.fixture
        )
    }

    func testOrphanedFindingFullEditPreservesSnapshotsAndRosterSynchronization() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertOrphanedFindingFullEditPreservesSnapshotsAndRosterSynchronization(
            using: environment.fixture
        )
    }

    func testSessionCreationFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertSessionCreationFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.sessionCreationFailureInjection()
        )
    }

    func testMissingFindingWritesRollBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingWritesRollBack(
            using: environment.fixture,
            failureInjection: environment.missingFindingFailureInjection()
        )
    }

    func testSessionCompletionFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertSessionCompletionFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.sessionCompletionFailureInjection()
        )
    }

    func testTrackedAnimalInsertionFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertTrackedAnimalInsertionFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.trackedAnimalFailureInjection()
        )
    }

    func testMissingFindingTypeTransitionFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingTypeTransitionFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.missingFindingFailureInjection()
        )
    }

    func testRosterMissingStateNormalizationFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertRosterMissingStateNormalizationFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.rosterStateFailureInjection()
        )
    }

    func testRosterCountedStateNormalizationFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertRosterCountedStateNormalizationFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.rosterStateFailureInjection()
        )
    }

    func testMissingFindingQuickCountNormalizationFailureRollsBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingQuickCountNormalizationFailureRollsBack(
            using: environment.fixture,
            failureInjection: environment.missingFindingQuickCountFailureInjection()
        )
    }

    func testMissingFindingUpdateAndStatusQuickCountNormalizationFailuresRollBack() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingUpdateAndStatusQuickCountNormalizationFailuresRollBack(
            using: environment.fixture,
            failureInjection: environment.missingFindingMutationQuickCountFailureInjection()
        )
    }

    func testMissingFindingFailureContextRecovers() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertMissingFindingFailureContextRecovers(
            using: environment.fixture,
            failureInjection: environment.missingFindingRecoveryInjection()
        )
    }

    func testAllFaultInjectedWriteContextsRecoverBeforeNextSave() async throws {
        let environment = try await makeEnvironment()
        try await FieldCheckRepositoryContract.assertAllFaultInjectedWriteContextsRecoverBeforeNextSave(
            using: environment.fixture,
            failureInjection: environment.allFailureContextsRecoveryInjection()
        )
    }

    func testPastureDeletionProjectsArchivedFieldCheckHistory() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Archived Field Check Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let controlPasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Control Field Check Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let repository = environment.makeFieldCheckRepository()
        let sessionID = try await repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 120_000),
                notes: "Archive projection target"
            )
        )
        let controlSessionID = try await repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: controlPasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 120_100),
                notes: "Archive projection control"
            )
        )
        let archivedAt = Date(timeIntervalSinceReferenceDate: 120_200)

        try await CoreDataPastureDeletionTransactionWriter(
            selection: environment.selection,
            assembly: environment.assembly
        ).deletePastures(
            DeletePasturesTransactionPlan(
                expectedStates: [
                    PastureDeletionExpectedState(
                        pastureID: pasture.id,
                        residentAnimalIDs: []
                    )
                ],
                operations: [
                    .archiveFieldChecks(
                        pastureIDs: [pasture.id],
                        archivedAt: archivedAt
                    ),
                    .deletePastures(ids: [pasture.id])
                ]
            )
        )

        let reloaded = environment.makeFieldCheckRepository()
        let archived = try XCTUnwrap(
            reloaded.fetchSessionDetail(id: sessionID)
        )
        XCTAssertEqual(archived.pastureID, pasture.id)
        XCTAssertEqual(archived.pastureName, "Archived Field Check Pasture")
        XCTAssertEqual(archived.pastureArchivedAt, archivedAt)
        XCTAssertTrue(archived.isPastureArchived)
        XCTAssertNil(
            try environment.makePastureRepository().fetchPastureDetail(id: pasture.id)
        )

        let archivedSummary = try XCTUnwrap(
            reloaded.fetchSessions().first { $0.id == sessionID }
        )
        XCTAssertEqual(archivedSummary.pastureID, pasture.id)
        XCTAssertEqual(archivedSummary.pastureName, "Archived Field Check Pasture")
        XCTAssertEqual(archivedSummary.pastureArchivedAt, archivedAt)
        XCTAssertTrue(archivedSummary.isPastureArchived)

        let control = try XCTUnwrap(
            reloaded.fetchSessionDetail(id: controlSessionID)
        )
        XCTAssertEqual(control.pastureID, controlPasture.id)
        XCTAssertEqual(control.pastureName, "Control Field Check Pasture")
        XCTAssertNil(control.pastureArchivedAt)
        XCTAssertFalse(control.isPastureArchived)
    }

    func testPastureDeletionRejectsFieldCheckWriteUntilDeletionReleasesBoundary() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Deletion Coordination Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let repository = environment.makeFieldCheckRepository()
        let sessionID = try await repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 121_000),
                notes: "Before coordinated deletion"
            )
        )
        let archivedAt = Date(timeIntervalSinceReferenceDate: 121_100)
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: pasture.id,
                    residentAnimalIDs: []
                )
            ],
            operations: [
                .archiveFieldChecks(
                    pastureIDs: [pasture.id],
                    archivedAt: archivedAt
                ),
                .deletePastures(ids: [pasture.id])
            ]
        )
        let barrier = CoreDataFieldCheckCommitBarrier()

        let pendingDeletion = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan,
                beforeSave: { _ in
                    barrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        do {
            try await environment.makeFieldCheckRepository().updateNotes(
                sessionID: sessionID,
                notes: "Must not stage while deletion owns boundary"
            )
            XCTFail("Expected Field Check writes to be rejected while Pasture deletion owns the boundary.")
        } catch {
            XCTAssertEqual(
                error as? CoreDataResidentWriteCoordinationError,
                .pastureDeletionInProgress
            )
        }

        barrier.release()
        try await pendingDeletion.value

        let postDeleteRepository = environment.makeFieldCheckRepository()
        let archived = try XCTUnwrap(
            postDeleteRepository.fetchSessionDetail(id: sessionID)
        )
        XCTAssertEqual(archived.notes, "Before coordinated deletion")
        XCTAssertEqual(archived.pastureArchivedAt, archivedAt)
        XCTAssertTrue(archived.isPastureArchived)

        try await postDeleteRepository.updateNotes(
            sessionID: sessionID,
            notes: "Write after deletion release"
        )
        XCTAssertEqual(
            try environment.makeFieldCheckRepository()
                .fetchSessionDetail(id: sessionID)?
                .notes,
            "Write after deletion release"
        )
    }

    func testConcurrentFieldCheckWritesEnterPersistenceSerially() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Field Check Serial Gate",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let repository = environment.makeFieldCheckRepository()
        let sessionID = try await repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 121_500),
                notes: "Initial"
            )
        )
        let firstBarrier = CoreDataFieldCheckCommitBarrier()
        let secondEntry = CoreDataFieldCheckWriteEntryProbe()

        let firstWrite = Task { @MainActor in
            try await repository.updateNotes(
                sessionID: sessionID,
                notes: "First"
            ) { _ in
                firstBarrier.blockUntilReleased()
            }
        }

        await waitUntilReached(firstBarrier)
        XCTAssertTrue(firstBarrier.didReach)

        let secondWrite = Task { @MainActor in
            try await repository.updateNotes(
                sessionID: sessionID,
                notes: "Second"
            ) { _ in
                secondEntry.markReached()
            }
        }

        for _ in 0..<50 {
            await Task.yield()
        }
        XCTAssertFalse(
            secondEntry.didReach,
            "A second Field Check transaction must not enter its private-context save boundary while the first write still owns the serial gate."
        )

        firstBarrier.release()
        try await firstWrite.value
        try await secondWrite.value

        XCTAssertTrue(secondEntry.didReach)
        XCTAssertEqual(
            try environment.makeFieldCheckRepository()
                .fetchSessionDetail(id: sessionID)?
                .notes,
            "Second"
        )
    }

    func testPendingFieldCheckRejectsLaterSynchronousAnimalWriterWithoutBlocking() async {
        let boundary = CoreDataAnimalWriteBoundary()
        await boundary.beginAnimalWrite()

        let fieldCheckAcquire = Task {
            await boundary.acquireFieldCheck()
        }

        for _ in 0..<1_000 {
            if boundary.hasPendingFieldCheck {
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(
            boundary.hasPendingFieldCheck,
            "Field Check must become pending while an earlier Animal writer owns the boundary."
        )

        do {
            try boundary.beginAnimalWriteSynchronously()
            XCTFail("A synchronous Animal writer must fail fast instead of blocking the main actor behind a pending Field Check.")
            boundary.endAnimalWrite()
        } catch {
            XCTAssertEqual(
                error as? CoreDataAnimalWriteBoundaryError,
                .fieldCheckPending
            )
        }

        XCTAssertEqual(
            boundary.queuedWriterCount,
            0,
            "Rejected synchronous work must not leak a waiter into the shared boundary."
        )

        boundary.endAnimalWrite()
        await fieldCheckAcquire.value
        boundary.releaseFieldCheck()
    }

    func testLegacyAnimalUpdateQueuesBehindInFlightFieldCheckAnimalMutation() async throws {
        let environment = try await makeEnvironment()
        let source = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Shared Animal Boundary Source",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Shared Animal Boundary Destination",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animalRepository = environment.makeAnimalRepository()
        let animal = try animalRepository.create(
            input: AnimalInput(
                name: "Shared Boundary Cow",
                tagNumber: "SB-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 10_000),
                status: .active,
                pastureID: source.id,
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
        )
        let fieldCheckRepository = environment.makeFieldCheckRepository()
        let sessionID = try await fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: destination.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 121_700),
                notes: "Shared Animal boundary"
            )
        )
        let barrier = CoreDataFieldCheckCommitBarrier()

        let pendingFieldCheckMove = Task { @MainActor in
            try await fieldCheckRepository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: animal.id,
                checkedAt: Date(timeIntervalSinceReferenceDate: 121_800)
            ) { _ in
                barrier.blockUntilReleased()
            }
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        let queueProbe = CoreDataQueuedAnimalWriterReleaseProbe(
            boundary: environment.assembly.animalWriteBoundary,
            barrier: barrier
        )
        let releaseTask = Task.detached {
            await queueProbe.releaseWhenWriterQueues()
        }

        let updatedAnimal = try animalRepository.update(
            id: animal.id,
            input: AnimalInput(
                name: "Updated After Field Check Move",
                tagNumber: "SB-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 10_000),
                status: .active,
                pastureID: destination.id,
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
        )

        await releaseTask.value
        try await pendingFieldCheckMove.value

        XCTAssertTrue(
            queueProbe.didObserveQueuedWriter,
            "The synchronous legacy Animal update must queue on the same boundary while the Field Check transaction owns that Animal graph."
        )
        XCTAssertEqual(updatedAnimal.name, "Updated After Field Check Move")
        XCTAssertEqual(updatedAnimal.pastureID, destination.id)

        let reloadedAnimal = try XCTUnwrap(
            environment.makeAnimalRepository().fetchAnimalDetail(id: animal.id)
        )
        XCTAssertEqual(reloadedAnimal.name, "Updated After Field Check Move")
        XCTAssertEqual(reloadedAnimal.pastureID, destination.id)

        let reloadedSession = try XCTUnwrap(
            environment.makeFieldCheckRepository().fetchSessionDetail(id: sessionID)
        )
        XCTAssertTrue(
            reloadedSession.animalChecks.contains { $0.animalID == animal.id }
        )
    }

    func testTrackedAnimalMoveRotatesAnimalAggregateRevision() async throws {
        let environment = try await makeEnvironment()
        let control = try await environment.makeFieldCheckRevisionControl()
        let fixture = AnimalAggregateCrossFeatureRevisionContractFixture(
            makeTestControl: { operation in
                guard operation == .fieldCheckAddTrackedAnimal else {
                    preconditionFailure("M7 owns only the Field Check tracked-animal revision probe.")
                }
                return control
            },
            makeParentDeletionProjectionProbe: {
                preconditionFailure("Not part of the M7 Field Check revision slice.")
            },
            makeLegacyUpdateTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M7 Field Check revision slice.")
            },
            makeDirectTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M7 Field Check revision slice.")
            },
            makeWorkingTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M7 Field Check revision slice.")
            },
            makeTagColorRemapDependentProjectionProbe: {
                preconditionFailure("Not part of the M7 Field Check revision slice.")
            }
        )

        try await AnimalAggregateCrossFeatureRevisionContract
            .assertFieldCheckAddTrackedAnimalRotatesRevision(using: fixture)
    }

    private func waitUntilReached(
        _ barrier: CoreDataFieldCheckCommitBarrier
    ) async {
        for _ in 0..<1_000 {
            if barrier.didReach {
                return
            }
            await Task.yield()
        }
    }

    private func makeEnvironment() async throws -> CoreDataFieldCheckContractEnvironment {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        return try CoreDataFieldCheckContractEnvironment(assembly: assembly)
    }
}

@MainActor
private final class CoreDataFieldCheckContractEnvironment {
    let assembly: CoreDataPersistenceAssembly
    let selection = CoreDataFieldCheckContractSelection()
    let herdID = UUID()

    private let failureState = CoreDataFieldCheckInjectedFailureState()

    init(assembly: CoreDataPersistenceAssembly) throws {
        self.assembly = assembly
        selection.currentHerdID = herdID
        try seedHerd()
    }

    var fixture: FieldCheckRepositoryContractFixture {
        FieldCheckRepositoryContractFixture(
            makeFieldCheckRepository: { self.makeFieldCheckRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makePastureRepository: { self.makePastureRepository() },
            makeTagColorRepository: { self.makeTagColorRepository() }
        )
    }

    func makeFieldCheckRepository() -> CoreDataFieldCheckRepository {
        CoreDataFieldCheckRepository(selection: selection, assembly: assembly)
    }

    func makeFieldCheckRepository(
        findingMutationCheckpoint: @escaping @Sendable (
            CoreDataFieldCheckFindingMutationCheckpoint,
            NSManagedObjectContext
        ) throws -> Void
    ) -> CoreDataFieldCheckRepository {
        CoreDataFieldCheckRepository(
            selection: selection,
            assembly: assembly,
            findingMutationCheckpoint: findingMutationCheckpoint
        )
    }

    func makeAnimalRepository() -> CoreDataAnimalRepository {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func makePastureRepository() -> CoreDataPastureRepository {
        CoreDataPastureRepository(selection: selection, assembly: assembly)
    }

    func makeTagColorRepository() -> CoreDataTagColorRepository {
        CoreDataTagColorRepository(selection: selection, assembly: assembly)
    }

    func sessionCreationFailureInjection() -> FieldCheckSessionCreationRollbackFailureInjection {
        FieldCheckSessionCreationRollbackFailureInjection(
            createSessionFailingAfterSessionStaged: { input in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                _ = try await repository.createSession(input: input) { context in
                    state.capture(context)
                    let session = try Self.singleInsertedSession(in: context)
                    let checks = Set(
                        context.insertedObjects.compactMap {
                            ($0 as? CDFieldCheckAnimalCheck)?.id
                        }
                    )
                    throw FieldCheckSessionCreationRollbackInjectedError.afterSessionStaged(
                        sessionID: session.id,
                        stagedAnimalCheckIDs: checks
                    )
                }
            },
            persistedAnimalCheckIDs: {
                try self.persistedAnimalCheckIDs()
            }
        )
    }

    func missingFindingFailureInjection() -> FieldCheckMissingFindingRollbackFailureInjection {
        FieldCheckMissingFindingRollbackFailureInjection(
            addMissingFindingFailingBetweenFindingAndMissingState: { sessionID, input in
                let state = self.failureState
                let repository = self.makeFieldCheckRepository { checkpoint, context in
                    guard case let .findingMutationStaged(operation, stagedSessionID, findingID) = checkpoint,
                          case .add = operation,
                          stagedSessionID == sessionID else {
                        return
                    }
                    state.capture(context)
                    throw FieldCheckMissingFindingRollbackInjectedError.betweenFindingAndMissingState(
                        operation: .add,
                        findingID: findingID
                    )
                }
                try await repository.addFinding(
                    sessionID: sessionID,
                    input: input
                )
            },
            updateMissingFindingFailingBetweenFindingAndMissingState: { sessionID, findingID, input in
                let state = self.failureState
                let repository = self.makeFieldCheckRepository { checkpoint, context in
                    guard case let .findingMutationStaged(operation, stagedSessionID, stagedFindingID) = checkpoint,
                          case .update = operation,
                          stagedSessionID == sessionID,
                          stagedFindingID == findingID else {
                        return
                    }
                    state.capture(context)
                    throw FieldCheckMissingFindingRollbackInjectedError.betweenFindingAndMissingState(
                        operation: .update,
                        findingID: findingID
                    )
                }
                try await repository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                )
            },
            updateMissingFindingStatusFailingBetweenFindingAndMissingState: { sessionID, findingID, status in
                let state = self.failureState
                let repository = self.makeFieldCheckRepository { checkpoint, context in
                    guard case let .findingMutationStaged(operation, stagedSessionID, stagedFindingID) = checkpoint,
                          case .updateStatus = operation,
                          stagedSessionID == sessionID,
                          stagedFindingID == findingID else {
                        return
                    }
                    state.capture(context)
                    throw FieldCheckMissingFindingRollbackInjectedError.betweenFindingAndMissingState(
                        operation: .updateStatus,
                        findingID: findingID
                    )
                }
                try await repository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                )
            },
            deleteMissingFindingFailingBetweenFindingAndMissingState: { sessionID, findingID in
                let state = self.failureState
                let repository = self.makeFieldCheckRepository { checkpoint, context in
                    guard case let .missingSynchronizationStaged(operation, stagedSessionID, stagedFindingID) = checkpoint,
                          case .delete = operation,
                          stagedSessionID == sessionID,
                          stagedFindingID == findingID else {
                        return
                    }
                    state.capture(context)
                    throw FieldCheckMissingFindingRollbackInjectedError.betweenFindingAndMissingState(
                        operation: .delete,
                        findingID: findingID
                    )
                }
                try await repository.deleteFinding(
                    sessionID: sessionID,
                    findingID: findingID
                )
            }
        )
    }

    func sessionCompletionFailureInjection() -> FieldCheckSessionCompletionRollbackFailureInjection {
        FieldCheckSessionCompletionRollbackFailureInjection(
            seedRawQuickCowCount: { sessionID, count in
                try self.setRawQuickCowCount(sessionID: sessionID, count: count)
            },
            rawQuickCowCount: { sessionID in
                try self.rawQuickCowCount(sessionID: sessionID)
            },
            completeSessionFailingAfterCompletionStaged: { sessionID in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.completeSession(id: sessionID) { context in
                    state.capture(context)
                    throw FieldCheckSessionCompletionRollbackInjectedError.afterCompletionStaged(
                        sessionID: sessionID
                    )
                }
            }
        )
    }

    func trackedAnimalFailureInjection() -> FieldCheckTrackedAnimalRollbackFailureInjection {
        FieldCheckTrackedAnimalRollbackFailureInjection(
            addTrackedAnimalFailingAfterMovementStaged: { sessionID, animalID, checkedAt in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.addTrackedAnimalToSession(
                    sessionID: sessionID,
                    animalID: animalID,
                    checkedAt: checkedAt
                ) { context in
                    state.capture(context)
                    throw FieldCheckTrackedAnimalRollbackInjectedError.afterMovementStaged
                }
            }
        )
    }

    func rosterStateFailureInjection() -> FieldCheckRosterStateRollbackFailureInjection {
        FieldCheckRosterStateRollbackFailureInjection(
            seedRawQuickCowCount: { sessionID, count in
                try self.setRawQuickCowCount(sessionID: sessionID, count: count)
            },
            rawQuickCowCount: { sessionID in
                try self.rawQuickCowCount(sessionID: sessionID)
            },
            setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged: { sessionID, checkID, isMissing in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: checkID,
                    isMissing: isMissing
                ) { context in
                    state.capture(context)
                    throw FieldCheckRosterStateRollbackInjectedError
                        .afterMissingStateAndQuickCountNormalizationStaged(
                            sessionID: sessionID,
                            animalCheckID: checkID
                        )
                }
            },
            setAnimalCheckCountedFailingAfterRosterStateAndNormalizationStaged: { sessionID, checkID, isCounted in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: checkID,
                    isCounted: isCounted
                ) { context in
                    state.capture(context)
                    throw FieldCheckRosterStateRollbackInjectedError
                        .afterCountedStateAndQuickCountNormalizationStaged(
                            sessionID: sessionID,
                            animalCheckID: checkID
                        )
                }
            }
        )
    }

    func missingFindingQuickCountFailureInjection() -> FieldCheckMissingFindingQuickCountRollbackFailureInjection {
        FieldCheckMissingFindingQuickCountRollbackFailureInjection(
            rawQuickCowCount: { sessionID in
                try self.rawQuickCowCount(sessionID: sessionID)
            },
            addMissingFindingFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, input in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.addFinding(
                    sessionID: sessionID,
                    input: input
                ) { context in
                    state.capture(context)
                    let finding = try Self.singleInsertedFinding(in: context)
                    let checkID = try Self.requiredAnimalCheckID(
                        sessionID: sessionID,
                        animalID: input.animalID,
                        in: context
                    )
                    throw FieldCheckMissingFindingQuickCountRollbackInjectedError
                        .afterMissingStateAndQuickCountNormalizationStaged(
                            sessionID: sessionID,
                            findingID: finding.id,
                            animalCheckID: checkID
                        )
                }
            }
        )
    }

    func missingFindingMutationQuickCountFailureInjection() -> FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection {
        FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection(
            rawQuickCowCount: { sessionID in
                try self.rawQuickCowCount(sessionID: sessionID)
            },
            updateFindingFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, findingID, input in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                ) { context in
                    state.capture(context)
                    let checkID = try Self.requiredAnimalCheckID(
                        sessionID: sessionID,
                        animalID: input.animalID,
                        in: context
                    )
                    throw FieldCheckMissingFindingMutationQuickCountRollbackInjectedError
                        .afterMissingStateAndQuickCountNormalizationStaged(
                            operation: .update,
                            sessionID: sessionID,
                            findingID: findingID,
                            animalCheckID: checkID
                        )
                }
            },
            updateFindingStatusFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, findingID, status in
                let repository = self.makeFieldCheckRepository()
                let state = self.failureState
                try await repository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                ) { context in
                    state.capture(context)
                    let finding = try Self.requiredFinding(
                        id: findingID,
                        sessionID: sessionID,
                        in: context
                    )
                    let checkID = try Self.requiredAnimalCheckID(
                        sessionID: sessionID,
                        animalID: finding.animalIDSnapshot,
                        in: context
                    )
                    throw FieldCheckMissingFindingMutationQuickCountRollbackInjectedError
                        .afterMissingStateAndQuickCountNormalizationStaged(
                            operation: .updateStatus,
                            sessionID: sessionID,
                            findingID: findingID,
                            animalCheckID: checkID
                        )
                }
            }
        )
    }

    func missingFindingRecoveryInjection() -> FieldCheckMissingFindingRollbackContextRecoveryInjection {
        FieldCheckMissingFindingRollbackContextRecoveryInjection(
            rollback: missingFindingFailureInjection(),
            saveProbeNotesThroughFailureContext: { sessionID, notes in
                try self.failureState.saveProbeNotes(
                    sessionID: sessionID,
                    notes: notes,
                    herdID: self.herdID
                )
            }
        )
    }

    func allFailureContextsRecoveryInjection() -> FieldCheckAllFailureContextsRecoveryInjection {
        FieldCheckAllFailureContextsRecoveryInjection(
            missingFinding: missingFindingRecoveryInjection(),
            sessionCreation: sessionCreationFailureInjection(),
            saveProbeAfterSessionCreationFailure: recoverySaveProbe(),
            trackedAnimal: trackedAnimalFailureInjection(),
            saveProbeAfterTrackedAnimalFailure: recoverySaveProbe(),
            sessionCompletion: sessionCompletionFailureInjection(),
            saveProbeAfterSessionCompletionFailure: recoverySaveProbe(),
            rosterState: rosterStateFailureInjection(),
            saveProbeAfterRosterMissingFailure: recoverySaveProbe(),
            saveProbeAfterRosterCountedFailure: recoverySaveProbe(),
            missingFindingQuickCount: missingFindingQuickCountFailureInjection(),
            saveProbeAfterMissingFindingQuickCountAddFailure: recoverySaveProbe(),
            missingFindingMutationQuickCount: missingFindingMutationQuickCountFailureInjection(),
            saveProbeAfterMissingFindingQuickCountUpdateFailure: recoverySaveProbe(),
            saveProbeAfterMissingFindingQuickCountStatusFailure: recoverySaveProbe()
        )
    }

    func makeFieldCheckRevisionControl() async throws -> CoreDataFieldCheckRevisionControl {
        let pastureRepository = makePastureRepository()
        let source = try pastureRepository.create(
            input: PastureInput(
                name: "Field Check Revision Source",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try pastureRepository.create(
            input: PastureInput(
                name: "Field Check Revision Destination",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        let animalRepository = makeAnimalRepository()
        let affected = try animalRepository.create(
            input: revisionAnimalInput(
                name: "Field Check Revision Target",
                tagNumber: "FC-REV-1",
                pastureID: source.id
            )
        )
        let unrelated = try animalRepository.create(
            input: revisionAnimalInput(
                name: "Field Check Revision Control",
                tagNumber: "FC-REV-2",
                pastureID: source.id
            )
        )

        let sessionID = try await makeFieldCheckRepository().createSession(
            input: FieldCheckSessionStartInput(
                pastureID: destination.id,
                startedAt: Date(timeIntervalSinceReferenceDate: 122_000),
                notes: "Field Check revision contract"
            )
        )

        return CoreDataFieldCheckRevisionControl(
            assembly: assembly,
            selection: selection,
            sessionID: sessionID,
            affectedAnimalID: affected.id,
            unrelatedAnimalID: unrelated.id,
            checkedAt: Date(timeIntervalSinceReferenceDate: 122_100)
        )
    }

    private func revisionAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSinceReferenceDate: 10_000),
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

    private func recoverySaveProbe() -> (UUID, String) throws -> Void {
        { sessionID, notes in
            try self.failureState.saveProbeNotes(
                sessionID: sessionID,
                notes: notes,
                herdID: self.herdID
            )
        }
    }

    private func persistedAnimalCheckIDs() throws -> Set<UUID> {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDFieldCheckAnimalCheck>(
                entityName: CDFieldCheckAnimalCheck.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return Set(try context.fetch(request).map(\.id))
        }
    }

    private func setRawQuickCowCount(
        sessionID: UUID,
        count: Int
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let session = try assembly.lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herdID,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            session.quickCowCount = Int64(count)
            try context.save()
        }
    }

    private func rawQuickCowCount(sessionID: UUID) throws -> Int? {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            try assembly.lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herdID,
                in: context
            ).map { Int($0.quickCowCount) }
        }
    }

    func seedAdditionalHerd(id: UUID, name: String) throws {
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

    func setFindingRawValue(
        findingID: UUID,
        key: String,
        value: String
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let finding = try assembly.lookup.herdOwned(
                CDFieldCheckFinding.self,
                id: findingID,
                herdID: herdID,
                in: context
            ) else {
                throw CoreDataFieldCheckContractTestError.missingStagedFinding
            }
            finding.setValue(value, forKey: key)
            try context.save()
        }
    }

    func setAnimalCheckRawValue(
        animalCheckID: UUID,
        key: String,
        value: String
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let check = try assembly.lookup.herdOwned(
                CDFieldCheckAnimalCheck.self,
                id: animalCheckID,
                herdID: herdID,
                in: context
            ) else {
                throw CoreDataFieldCheckContractTestError.missingStagedAnimalCheck
            }
            check.setValue(value, forKey: key)
            try context.save()
        }
    }

    private func seedHerd() throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Field Check Contract Herd"
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
            herd.updatedAt = herd.createdAt
            try context.save()
        }
    }

    private nonisolated static func singleInsertedSession(
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckSession {
        let inserted = context.insertedObjects.compactMap {
            $0 as? CDFieldCheckSession
        }
        guard inserted.count == 1, let session = inserted.first else {
            throw CoreDataFieldCheckContractTestError.missingStagedSession
        }
        return session
    }

    private nonisolated static func singleInsertedFinding(
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckFinding {
        let inserted = context.insertedObjects.compactMap {
            $0 as? CDFieldCheckFinding
        }
        guard inserted.count == 1, let finding = inserted.first else {
            throw CoreDataFieldCheckContractTestError.missingStagedFinding
        }
        return finding
    }

    private nonisolated static func requiredAnimalCheckID(
        sessionID: UUID,
        animalID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> UUID {
        guard let animalID else {
            throw CoreDataFieldCheckContractTestError.missingStagedAnimalCheck
        }
        let request = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        request.predicate = NSPredicate(
            format: "session.id == %@ AND animalIDSnapshot == %@",
            sessionID as NSUUID,
            animalID as NSUUID
        )
        request.fetchLimit = 1
        guard let check = try context.fetch(request).first else {
            throw CoreDataFieldCheckContractTestError.missingStagedAnimalCheck
        }
        return check.id
    }

    private nonisolated static func requiredFinding(
        id: UUID,
        sessionID: UUID,
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckFinding {
        let request = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        request.predicate = NSPredicate(
            format: "id == %@ AND session.id == %@",
            id as NSUUID,
            sessionID as NSUUID
        )
        request.fetchLimit = 1
        guard let finding = try context.fetch(request).first else {
            throw CoreDataFieldCheckContractTestError.missingStagedFinding
        }
        return finding
    }
}

@MainActor
private final class CoreDataFieldCheckContractSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

private enum CoreDataFieldCheckContractTestError: Error {
    case missingStagedSession
    case missingStagedFinding
    case missingStagedAnimalCheck
    case missingCapturedContext
    case missingProbeSession
}

private final class CoreDataFieldCheckInjectedFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedContext: NSManagedObjectContext?

    func capture(_ context: NSManagedObjectContext) {
        lock.lock()
        capturedContext = context
        lock.unlock()
    }

    func saveProbeNotes(
        sessionID: UUID,
        notes: String,
        herdID: UUID
    ) throws {
        lock.lock()
        let context = capturedContext
        lock.unlock()

        guard let context else {
            throw CoreDataFieldCheckContractTestError.missingCapturedContext
        }

        try context.performAndWait {
            let request = NSFetchRequest<CDFieldCheckSession>(
                entityName: CDFieldCheckSession.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "id == %@ AND herd.id == %@",
                sessionID as NSUUID,
                herdID as NSUUID
            )
            request.fetchLimit = 1
            guard let session = try context.fetch(request).first else {
                throw CoreDataFieldCheckContractTestError.missingProbeSession
            }
            session.notes = notes
            try context.save()
        }
    }
}


@MainActor
private final class CoreDataFieldCheckRevisionControl:
    AnimalAggregateCrossFeatureRevisionContractTestControl
{
    let operation: AnimalAggregateCrossFeatureRevisionOperation = .fieldCheckAddTrackedAnimal
    let affectedAnimalIDs: [UUID]
    let unrelatedAnimalID: UUID

    private let assembly: CoreDataPersistenceAssembly
    private let selection: CoreDataFieldCheckContractSelection
    private let sessionID: UUID
    private let affectedAnimalID: UUID
    private let checkedAt: Date

    init(
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataFieldCheckContractSelection,
        sessionID: UUID,
        affectedAnimalID: UUID,
        unrelatedAnimalID: UUID,
        checkedAt: Date
    ) {
        self.assembly = assembly
        self.selection = selection
        self.sessionID = sessionID
        self.affectedAnimalID = affectedAnimalID
        self.affectedAnimalIDs = [affectedAnimalID]
        self.unrelatedAnimalID = unrelatedAnimalID
        self.checkedAt = checkedAt
    }

    func makeAggregateReader() -> any AnimalAggregateEditReading {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func makeAnimalRepository() -> any AnimalRepository {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func performMutation() async throws {
        try await CoreDataFieldCheckRepository(
            selection: selection,
            assembly: assembly
        ).addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: affectedAnimalID,
            checkedAt: checkedAt
        )
    }
}

private final class CoreDataQueuedAnimalWriterReleaseProbe: @unchecked Sendable {
    private let boundary: CoreDataAnimalWriteBoundary
    private let barrier: CoreDataFieldCheckCommitBarrier
    private let lock = NSLock()
    private var observedQueuedWriter = false

    init(
        boundary: CoreDataAnimalWriteBoundary,
        barrier: CoreDataFieldCheckCommitBarrier
    ) {
        self.boundary = boundary
        self.barrier = barrier
    }

    var didObserveQueuedWriter: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedQueuedWriter
    }

    func releaseWhenWriterQueues() async {
        var observed = false

        for _ in 0..<10_000 {
            if boundary.queuedWriterCount > 0 {
                observed = true
                break
            }
            await Task.yield()
        }

        lock.lock()
        observedQueuedWriter = observed
        lock.unlock()
        barrier.release()
    }
}

private final class CoreDataFieldCheckWriteEntryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reached = false

    var didReach: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reached
    }

    func markReached() {
        lock.lock()
        reached = true
        lock.unlock()
    }
}

private final class CoreDataFieldCheckCommitBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var reached = false
    private var released = false

    var didReach: Bool {
        condition.lock()
        defer { condition.unlock() }
        return reached
    }

    func blockUntilReleased() {
        condition.lock()
        reached = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
