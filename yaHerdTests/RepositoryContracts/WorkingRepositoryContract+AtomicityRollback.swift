import Foundation
import XCTest
@testable import yaHerd

enum WorkingRollbackInjectedError: Error, Equatable {
    case afterSessionStartStaged(sessionID: UUID, queueItemIDs: Set<UUID>)
    case afterCollectionStaged(sessionID: UUID, queueItemIDs: Set<UUID>)
    case afterQueueItemCompletionStaged(sessionID: UUID, queueItemID: UUID)
    case afterWorkDataReplacementStaged(sessionID: UUID, queueItemID: UUID)
    case afterWorkDataDeletionStaged(sessionID: UUID, queueItemID: UUID)
    case afterPrimaryTagReplacementStaged(
        sessionID: UUID,
        queueItemID: UUID,
        replacementTagID: UUID
    )
    case afterSessionCompletionStaged(
        sessionID: UUID,
        movedAnimalID: UUID,
        destinationQueueItemIDs: Set<UUID>
    )
    case afterSessionDeletionStaged(sessionID: UUID, restoredAnimalID: UUID)
    case afterTemplateDeletionStaged(templateIDs: Set<UUID>)
}

struct WorkingPersistedWorkDataIDs: Equatable {
    let treatmentRecordIDs: Set<UUID>
    let pregnancyCheckIDs: Set<UUID>
    let healthRecordIDs: Set<UUID>
}

@MainActor
struct WorkingHistoricalPersistenceInspection {
    /// Returns Working child IDs for the session + captured Animal application identity.
    /// After live Animal deletion, treatment records are located by their historical animal-ID
    /// snapshot; generated health/pregnancy rows are expected to have cascaded with the Animal.
    let persistedWorkDataIDs: (
        _ sessionID: UUID,
        _ animalID: UUID
    ) throws -> WorkingPersistedWorkDataIDs
}

/// Target-only fault-injection hooks for Core Data Working transaction boundaries.
///
/// These hooks intentionally are not production repository requirements. A Core Data contract runner
/// supplies operations that fail after partial state has been staged but before commit, plus raw-row
/// probes that can detect orphaned children hidden from normal Domain projections. No SwiftData runner
/// should be added for these requirements.
@MainActor
struct WorkingRollbackFailureInjection {
    let startSessionFailingAfterQueueStaged: (
        _ input: WorkingSessionStartInput
    ) throws -> Void
    let collectAnimalsFailingAfterQueueStaged: (
        _ sessionID: UUID,
        _ animalIDs: [UUID]
    ) throws -> Void
    let completeQueueItemFailingAfterMutationStaged: (
        _ sessionID: UUID,
        _ queueItemID: UUID,
        _ treatmentEntries: [WorkingTreatmentEntryInput],
        _ pregnancyCheck: WorkingPregnancyCheckInput?,
        _ markCastrated: Bool,
        _ observationNotes: String
    ) throws -> Void
    let replaceWorkDataFailingAfterMutationStaged: (
        _ sessionID: UUID,
        _ queueItemID: UUID,
        _ input: WorkingSessionAnimalEditInput
    ) throws -> Void
    let replacePrimaryTagFailingAfterMutationStaged: (
        _ sessionID: UUID,
        _ queueItemID: UUID,
        _ input: WorkingTagReplacementInput
    ) throws -> Void
    let deleteWorkDataFailingAfterCleanupStaged: (
        _ sessionID: UUID,
        _ queueItemID: UUID
    ) throws -> Void
    let completeSessionFailingAfterMovementStaged: (
        _ sessionID: UUID,
        _ assignments: [WorkingQueueDestinationAssignment]
    ) throws -> Void
    let deleteSessionFailingAfterCleanupStaged: (
        _ sessionID: UUID
    ) throws -> Void
    let deleteTemplatesFailingAfterDeletionStaged: (
        _ templateIDs: [UUID]
    ) throws -> Void
    let persistedQueueItemIDs: () throws -> Set<UUID>
    let persistedWorkDataIDs: (
        _ sessionID: UUID,
        _ animalID: UUID
    ) throws -> WorkingPersistedWorkDataIDs
    let persistedMovementRecordIDs: (
        _ animalIDs: [UUID]
    ) throws -> Set<UUID>
    let persistedAnimalTagIDs: (
        _ animalID: UUID
    ) throws -> Set<UUID>
    let persistedTemplateIDs: () throws -> Set<UUID>
}

@MainActor
extension WorkingRepositoryContract {
    static func assertSessionStartFailureRollsBackAllStagedState(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Start Rollback Source", using: fixture)
        let first = try makeAnimal(name: "Start Rollback One", tagNumber: "SR101", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Start Rollback Two", tagNumber: "SR102", sex: .male, pastureID: source.id, using: fixture)
        let beforeSessions = try fixture.makeWorkingRepository().fetchSessions()
        let beforeQueueIDs = try failureInjection.persistedQueueItemIDs()
        let beforeFirst = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), file: file, line: line)
        let beforeSecond = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        let input = WorkingSessionStartInput(
            date: date(year: 2026, month: 10, day: 1),
            sourcePastureID: source.id,
            treatmentTemplateName: "Start Rollback",
            plannedTreatments: [WorkingTreatmentPlanItem(id: UUID(), name: "Rollback Vaccine")],
            animalIDs: [first.id, second.id]
        )
        var stagedSessionID: UUID?
        var stagedQueueItemIDs = Set<UUID>()

        XCTAssertThrowsError(
            try failureInjection.startSessionFailingAfterQueueStaged(input),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterSessionStartStaged(sessionID, queueItemIDs) = error else {
                XCTFail("The start failpoint must surface after the session and queue state have been staged: \(error)", file: file, line: line)
                return
            }
            stagedSessionID = sessionID
            stagedQueueItemIDs = queueItemIDs
        }

        let failedSessionID = try XCTUnwrap(stagedSessionID, file: file, line: line)
        XCTAssertFalse(stagedQueueItemIDs.isEmpty, "The start failpoint must identify at least one staged queue row.", file: file, line: line)
        XCTAssertEqual(try fixture.makeWorkingRepository().fetchSessions(), beforeSessions, file: file, line: line)
        XCTAssertNil(try fixture.makeWorkingRepository().fetchSessionDetail(id: failedSessionID), file: file, line: line)
        let afterQueueIDs = try failureInjection.persistedQueueItemIDs()
        XCTAssertEqual(afterQueueIDs, beforeQueueIDs, "Failed session start must not leave orphaned queue rows.", file: file, line: line)
        XCTAssertTrue(stagedQueueItemIDs.isDisjoint(with: afterQueueIDs), file: file, line: line)

        let afterFirst = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), file: file, line: line)
        let afterSecond = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        XCTAssertEqual(afterFirst, beforeFirst, "Failed session start must restore the first staged animal completely.", file: file, line: line)
        XCTAssertEqual(afterSecond, beforeSecond, "Failed session start must restore the second staged animal completely.", file: file, line: line)
    }

    static func assertAdditionalCollectionFailureRollsBackAllStagedState(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Collect Rollback Source", using: fixture)
        let existing = try makeAnimal(name: "Collect Existing", tagNumber: "CR100", sex: .female, pastureID: source.id, using: fixture)
        let firstCandidate = try makeAnimal(name: "Collect Candidate One", tagNumber: "CR101", sex: .female, pastureID: source.id, using: fixture)
        let secondCandidate = try makeAnimal(name: "Collect Candidate Two", tagNumber: "CR102", sex: .male, pastureID: source.id, using: fixture)
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 2),
                sourcePastureID: source.id,
                treatmentTemplateName: "Collect Rollback",
                plannedTreatments: [],
                animalIDs: [existing.id]
            )
        )
        let beforeSession = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        let beforeQueueIDs = try failureInjection.persistedQueueItemIDs()
        let beforeFirst = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: firstCandidate.id), file: file, line: line)
        let beforeSecond = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: secondCandidate.id), file: file, line: line)
        var stagedQueueIDs = Set<UUID>()

        XCTAssertThrowsError(
            try failureInjection.collectAnimalsFailingAfterQueueStaged(
                sessionID,
                [firstCandidate.id, secondCandidate.id]
            ),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterCollectionStaged(failedSessionID, queueItemIDs) = error else {
                XCTFail("The collection failpoint must surface after queue/ownership changes have been staged: \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(failedSessionID, sessionID, file: file, line: line)
            stagedQueueIDs = queueItemIDs
        }

        XCTAssertFalse(stagedQueueIDs.isEmpty, file: file, line: line)
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Failed collection must preserve the pre-existing session queue exactly.",
            file: file,
            line: line
        )
        let afterQueueIDs = try failureInjection.persistedQueueItemIDs()
        XCTAssertEqual(afterQueueIDs, beforeQueueIDs, "Failed collection must not leak staged queue rows.", file: file, line: line)
        XCTAssertTrue(stagedQueueIDs.isDisjoint(with: afterQueueIDs), file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: firstCandidate.id), beforeFirst, file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: secondCandidate.id), beforeSecond, file: file, line: line)
    }

    static func assertInitialQueueItemCompletionFailureRollsBackAllStagedState(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Completion Rollback Source", using: fixture)
        let animal = try makeAnimal(
            name: "Working Completion Rollback Cow",
            tagNumber: "QR201",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 3),
                sourcePastureID: source.id,
                treatmentTemplateName: "Completion Rollback",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(id: treatmentID, name: "Completion Rollback Treatment")
                ],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )
        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let beforeTimeline = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )
        let beforeRaw = try failureInjection.persistedWorkDataIDs(sessionID, animal.id)

        XCTAssertThrowsError(
            try failureInjection.completeQueueItemFailingAfterMutationStaged(
                sessionID,
                queueItemID,
                [
                    WorkingTreatmentEntryInput(
                        date: date(year: 2026, month: 10, day: 3, hour: 9),
                        treatmentItemID: treatmentID,
                        itemName: "Completion Rollback Treatment",
                        given: true,
                        dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                    )
                ],
                WorkingPregnancyCheckInput(
                    date: date(year: 2026, month: 10, day: 3, hour: 9, minute: 5),
                    result: .open,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                false,
                "Completion rollback observation"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRollbackInjectedError,
                .afterQueueItemCompletionStaged(
                    sessionID: sessionID,
                    queueItemID: queueItemID
                ),
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Failed initial queue completion must restore queued status/completion metadata.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            "Failed initial queue completion must not publish generated Animal history.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try failureInjection.persistedWorkDataIDs(sessionID, animal.id),
            beforeRaw,
            "Failed initial queue completion must not leak newly inserted treatment/pregnancy/health children.",
            file: file,
            line: line
        )
    }

    static func assertWorkDataReplacementFailureRollsBackAllStagedState(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Data Rollback Source", using: fixture)
        let destination = try makePasture(named: "Working Data Rollback Destination", using: fixture)
        let animal = try makeAnimal(name: "Data Rollback Cow", tagNumber: "DR201", sex: .female, pastureID: source.id, using: fixture)
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 3),
                sourcePastureID: source.id,
                treatmentTemplateName: "Data Rollback",
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatmentID, name: "Original Treatment")],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 3, hour: 9),
                    treatmentItemID: treatmentID,
                    itemName: "Original Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 10, day: 3, hour: 9, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Original rollback observation"
        )

        let beforeSession = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        let beforeTimeline = Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id))
        let beforeRaw = try failureInjection.persistedWorkDataIDs(sessionID, animal.id)
        let replacementInput = WorkingSessionAnimalEditInput(
            status: .inProgress,
            completedAt: beforeEditor.completedAt,
            destinationPastureID: destination.id,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 4, hour: 10),
                    treatmentItemID: treatmentID,
                    itemName: "Replacement Treatment",
                    given: false,
                    dose: WorkingTreatmentDose(amount: 1, unit: .milliliter)
                )
            ],
            pregnancyCheck: nil,
            castrationPerformed: true,
            observationNotes: "Replacement rollback observation"
        )

        XCTAssertThrowsError(
            try failureInjection.replaceWorkDataFailingAfterMutationStaged(
                sessionID,
                queueItemID,
                replacementInput
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRollbackInjectedError,
                .afterWorkDataReplacementStaged(sessionID: sessionID, queueItemID: queueItemID),
                file: file,
                line: line
            )
        }

        XCTAssertEqual(try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), beforeSession, file: file, line: line)
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            beforeEditor,
            "Failed work-data replacement must restore queue metadata and every replaced child record.",
            file: file,
            line: line
        )
        XCTAssertEqual(Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)), beforeTimeline, file: file, line: line)
        XCTAssertEqual(
            try failureInjection.persistedWorkDataIDs(sessionID, animal.id),
            beforeRaw,
            "Failed work-data replacement must not leave orphaned replacement children or delete original children.",
            file: file,
            line: line
        )
    }

    static func assertDeleteWorkDataFailureRollsBackResetAndChildren(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Reset Rollback Source", using: fixture)
        let destination = try makePasture(named: "Working Reset Rollback Destination", using: fixture)
        let animal = try makeAnimal(
            name: "Working Reset Rollback Cow",
            tagNumber: "RR301",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 4),
                sourcePastureID: source.id,
                treatmentTemplateName: "Reset Rollback",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(id: treatmentID, name: "Reset Rollback Treatment")
                ],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )
        try repository.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: destination.id,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: date(year: 2026, month: 10, day: 4, hour: 9),
                        treatmentItemID: treatmentID,
                        itemName: "Reset Rollback Treatment",
                        given: true,
                        dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: date(year: 2026, month: 10, day: 4, hour: 9, minute: 5),
                    result: .open,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: "Reset rollback observation"
            )
        )

        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let beforeTimeline = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )
        let beforeRaw = try failureInjection.persistedWorkDataIDs(sessionID, animal.id)

        XCTAssertThrowsError(
            try failureInjection.deleteWorkDataFailingAfterCleanupStaged(
                sessionID,
                queueItemID
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRollbackInjectedError,
                .afterWorkDataDeletionStaged(
                    sessionID: sessionID,
                    queueItemID: queueItemID
                ),
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Failed work-data reset must restore queue status/completion/destination metadata.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try failureInjection.persistedWorkDataIDs(sessionID, animal.id),
            beforeRaw,
            "Failed work-data reset must restore every removed child row.",
            file: file,
            line: line
        )
    }

    static func assertPrimaryTagReplacementFailureRollsBackAnimalAndQueueSnapshot(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Tag Rollback Source", using: fixture)
        let replacementColor = TagColorSnapshot(
            name: "Working Tag Rollback Color",
            prefix: "WTR",
            rgba: RGBAColor(r: 0.2, g: 0.5, b: 0.8)
        )
        try fixture.makeTagColorRepository().upsert(replacementColor)
        let animal = try makeAnimal(
            name: "Working Tag Rollback Cow",
            tagNumber: "TR401",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 4),
                sourcePastureID: source.id,
                treatmentTemplateName: "Tag Rollback",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )
        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let beforeAnimal = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        let beforeRawTagIDs = try failureInjection.persistedAnimalTagIDs(animal.id)
        var stagedReplacementTagID: UUID?

        XCTAssertThrowsError(
            try failureInjection.replacePrimaryTagFailingAfterMutationStaged(
                sessionID,
                queueItemID,
                WorkingTagReplacementInput(
                    number: "TR499",
                    colorID: replacementColor.id
                )
            ),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterPrimaryTagReplacementStaged(
                failedSessionID,
                failedQueueItemID,
                replacementTagID
            ) = error else {
                XCTFail(
                    "The retag failpoint must fire after old/new tag and queue snapshot changes are staged: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertEqual(failedSessionID, sessionID, file: file, line: line)
            XCTAssertEqual(failedQueueItemID, queueItemID, file: file, line: line)
            stagedReplacementTagID = replacementTagID
        }

        let failedReplacementTagID = try XCTUnwrap(
            stagedReplacementTagID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Failed Working retagging must restore the queue's captured tag snapshot.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            beforeAnimal,
            "Failed Working retagging must restore the original active/retired AnimalTag state.",
            file: file,
            line: line
        )
        let afterRawTagIDs = try failureInjection.persistedAnimalTagIDs(animal.id)
        XCTAssertEqual(
            afterRawTagIDs,
            beforeRawTagIDs,
            "Failed Working retagging must not leave a hidden replacement AnimalTag row.",
            file: file,
            line: line
        )
        XCTAssertFalse(afterRawTagIDs.contains(failedReplacementTagID), file: file, line: line)
    }

    static func assertTemplateBatchDeletionFailureRollsBackEveryTemplate(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeWorkingRepository()
        let firstID = try repository.createTemplate(
            name: "Working Delete Rollback Alpha",
            items: [WorkingTreatmentPlanItem(id: UUID(), name: "Alpha Treatment")]
        )
        let secondID = try repository.createTemplate(
            name: "Working Delete Rollback Beta",
            items: [WorkingTreatmentPlanItem(id: UUID(), name: "Beta Treatment")]
        )
        let controlID = try repository.createTemplate(
            name: "Working Delete Rollback Control",
            items: []
        )

        let beforeList = try fixture.makeWorkingRepository().fetchTemplates()
        let beforeFirst = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: firstID),
            file: file,
            line: line
        )
        let beforeSecond = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: secondID),
            file: file,
            line: line
        )
        let beforeRawIDs = try failureInjection.persistedTemplateIDs()
        var stagedIDs = Set<UUID>()

        XCTAssertThrowsError(
            try failureInjection.deleteTemplatesFailingAfterDeletionStaged(
                [firstID, secondID]
            ),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterTemplateDeletionStaged(templateIDs) = error else {
                XCTFail(
                    "The template-delete failpoint must fire after at least one requested delete is staged: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            stagedIDs = templateIDs
        }

        XCTAssertFalse(stagedIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(
            stagedIDs.isSubset(of: Set([firstID, secondID])),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchTemplates(),
            beforeList,
            "Failed template batch deletion must restore the complete sorted list.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: firstID),
            beforeFirst,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: secondID),
            beforeSecond,
            file: file,
            line: line
        )
        XCTAssertNotNil(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: controlID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try failureInjection.persistedTemplateIDs(),
            beforeRawIDs,
            "Failed batch deletion must not physically remove a subset of requested templates.",
            file: file,
            line: line
        )
    }

    static func assertSessionCompletionFailureRollsBackMovementsAndDestinations(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Finish Rollback Source", using: fixture)
        let destination = try makePasture(named: "Working Finish Rollback Destination", using: fixture)
        let first = try makeAnimal(name: "Finish Rollback One", tagNumber: "FR301", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Finish Rollback Two", tagNumber: "FR302", sex: .male, pastureID: source.id, using: fixture)
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 5),
                sourcePastureID: source.id,
                treatmentTemplateName: "Finish Rollback",
                plannedTreatments: [],
                animalIDs: [first.id, second.id]
            )
        )
        let started = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let firstQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == first.id }?.id,
            file: file,
            line: line
        )
        let secondQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == second.id }?.id,
            file: file,
            line: line
        )

        let animalRepository = fixture.makeAnimalRepository()
        try animalRepository.archive(ids: [second.id])
        try animalRepository.delete(ids: [second.id])

        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(
            beforeSession.queueItems.first { $0.id == secondQueueID },
            "The rollback fixture must include an orphaned historical queue row whose destination can be staged without a live movement.",
            file: file,
            line: line
        )
        let beforeFirst = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id),
            file: file,
            line: line
        )
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id),
            file: file,
            line: line
        )
        let beforeFirstTimeline = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: first.id)
        )
        let beforeMovementIDs = try failureInjection.persistedMovementRecordIDs([first.id])
        let assignments = [
            WorkingQueueDestinationAssignment(queueItemID: firstQueueID, destinationPastureID: destination.id),
            WorkingQueueDestinationAssignment(queueItemID: secondQueueID, destinationPastureID: nil)
        ]
        var stagedMovedAnimalID: UUID?
        var stagedDestinationQueueItemIDs = Set<UUID>()

        XCTAssertThrowsError(
            try failureInjection.completeSessionFailingAfterMovementStaged(sessionID, assignments),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterSessionCompletionStaged(
                failedSessionID,
                movedAnimalID,
                destinationQueueItemIDs
            ) = error else {
                XCTFail(
                    "The completion failpoint must surface after destination snapshots and at least one live movement have been staged: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertEqual(failedSessionID, sessionID, file: file, line: line)
            stagedMovedAnimalID = movedAnimalID
            stagedDestinationQueueItemIDs = destinationQueueItemIDs
        }
        XCTAssertEqual(
            try XCTUnwrap(stagedMovedAnimalID, file: file, line: line),
            first.id,
            "Only the live queue Animal can stage a movement; the orphaned row stages destination history only.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            stagedDestinationQueueItemIDs,
            Set([firstQueueID, secondQueueID]),
            "The completion failpoint must stage final destinations for both the live row and orphaned historical row before failing.",
            file: file,
            line: line
        )

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Failed session completion must roll back both live movement state and destination-only changes on orphaned queue history.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id),
            beforeFirst,
            file: file,
            line: line
        )
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: first.id)),
            beforeFirstTimeline,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try failureInjection.persistedMovementRecordIDs([first.id]),
            beforeMovementIDs,
            "Failed session completion must not leave a movement row for the live part of a mixed live/orphan queue.",
            file: file,
            line: line
        )
    }

    static func assertSessionDeletionFailureRollsBackRestorationAndCleanup(
        using fixture: WorkingRepositoryContractFixture,
        failureInjection: WorkingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Delete Rollback Source", using: fixture)
        let first = try makeAnimal(name: "Delete Rollback One", tagNumber: "XR401", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Delete Rollback Two", tagNumber: "XR402", sex: .female, pastureID: source.id, using: fixture)
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 6),
                sourcePastureID: source.id,
                treatmentTemplateName: "Delete Rollback",
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatmentID, name: "Delete Rollback Treatment")],
                animalIDs: [first.id, second.id]
            )
        )
        let beforeSession = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let firstQueueID = try XCTUnwrap(beforeSession.queueItems.first { $0.animalID == first.id }?.id, file: file, line: line)
        try repository.complete(
            queueItemID: firstQueueID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 6, hour: 9),
                    treatmentItemID: treatmentID,
                    itemName: "Delete Rollback Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 10, day: 6, hour: 9, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Delete rollback observation"
        )

        let beforeSessionWithWork = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        let beforeFirstEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: firstQueueID),
            file: file,
            line: line
        )
        let beforeFirst = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), file: file, line: line)
        let beforeSecond = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        let beforeFirstTimeline = Set(try fixture.makeAnimalRepository().fetchTimeline(id: first.id))
        let beforeWorkData = try failureInjection.persistedWorkDataIDs(sessionID, first.id)
        let beforeQueueIDs = try failureInjection.persistedQueueItemIDs()
        var stagedRestoredAnimalID: UUID?

        XCTAssertThrowsError(
            try failureInjection.deleteSessionFailingAfterCleanupStaged(sessionID),
            file: file,
            line: line
        ) { error in
            guard case let WorkingRollbackInjectedError.afterSessionDeletionStaged(failedSessionID, restoredAnimalID) = error else {
                XCTFail("The deletion failpoint must surface after animal restoration or linked-record cleanup has been staged: \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(failedSessionID, sessionID, file: file, line: line)
            stagedRestoredAnimalID = restoredAnimalID
        }
        XCTAssertTrue([first.id, second.id].contains(try XCTUnwrap(stagedRestoredAnimalID, file: file, line: line)), file: file, line: line)

        XCTAssertEqual(try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), beforeSessionWithWork, file: file, line: line)
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: firstQueueID),
            beforeFirstEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), beforeFirst, file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), beforeSecond, file: file, line: line)
        XCTAssertEqual(Set(try fixture.makeAnimalRepository().fetchTimeline(id: first.id)), beforeFirstTimeline, file: file, line: line)
        XCTAssertEqual(try failureInjection.persistedWorkDataIDs(sessionID, first.id), beforeWorkData, file: file, line: line)
        XCTAssertEqual(try failureInjection.persistedQueueItemIDs(), beforeQueueIDs, file: file, line: line)
    }
}
