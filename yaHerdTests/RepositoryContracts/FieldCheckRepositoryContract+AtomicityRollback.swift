import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckSessionCreationRollbackInjectedError: Error, Equatable {
    case afterSessionStaged(sessionID: UUID, stagedAnimalCheckIDs: Set<UUID>)
}

enum FieldCheckMissingFindingRollbackOperation: Equatable {
    case add
    case update
    case updateStatus
    case delete
}

enum FieldCheckMissingFindingRollbackInjectedError: Error, Equatable {
    case betweenFindingAndMissingState(
        operation: FieldCheckMissingFindingRollbackOperation,
        findingID: UUID
    )
}

enum FieldCheckSessionCompletionRollbackInjectedError: Error, Equatable {
    case afterCompletionStaged(sessionID: UUID)
}

/// Permanent fault-injection hook for persistence implementations that can fail session creation
/// after the session and at least one initial roster row have been staged but before the logical
/// operation commits.
///
/// The final persistence runner must surface the staged application UUIDs and expose a direct
/// persisted-row probe so this contract can detect orphaned roster rows even when the staged session
/// itself was rolled back or is no longer reachable through repository projections.
@MainActor
struct FieldCheckSessionCreationRollbackFailureInjection {
    let createSessionFailingAfterSessionStaged: (
        _ input: FieldCheckSessionStartInput
    ) throws -> Void
    let persistedAnimalCheckIDs: () throws -> Set<UUID>
}

/// Permanent fault-injection hook for persistence implementations that can fail coordinated
/// missing-animal finding writes between the finding mutation and synchronized roster mutation.
///
/// The final persistence runner may stage either side first; the injected failure must happen after
/// one side has been staged but before the logical operation commits. Every operation must surface
/// the sentinel with its operation and finding application UUID so an unrelated early failure cannot
/// satisfy the rollback contract.
@MainActor
struct FieldCheckMissingFindingRollbackFailureInjection {
    let addMissingFindingFailingBetweenFindingAndMissingState: (
        _ sessionID: UUID,
        _ input: FieldCheckFindingInput
    ) throws -> Void
    let updateMissingFindingFailingBetweenFindingAndMissingState: (
        _ sessionID: UUID,
        _ findingID: UUID,
        _ input: FieldCheckFindingInput
    ) throws -> Void
    let updateMissingFindingStatusFailingBetweenFindingAndMissingState: (
        _ sessionID: UUID,
        _ findingID: UUID,
        _ status: FieldCheckFindingStatus
    ) throws -> Void
    let deleteMissingFindingFailingBetweenFindingAndMissingState: (
        _ sessionID: UUID,
        _ findingID: UUID
    ) throws -> Void
}

/// Permanent fault-injection hook for persistence implementations that can fail session completion
/// after completion-time snapshot/count changes have been staged but before the operation commits.
///
/// The raw quick-count accessors intentionally bypass repository projection normalization. They let
/// the final persistence runner seed a stale persisted value that completion must normalize, then
/// prove that failed completion does not leak that staged normalization into durable storage.
@MainActor
struct FieldCheckSessionCompletionRollbackFailureInjection {
    let seedRawQuickCowCount: (
        _ sessionID: UUID,
        _ count: Int
    ) throws -> Void
    let rawQuickCowCount: (
        _ sessionID: UUID
    ) throws -> Int?
    let completeSessionFailingAfterCompletionStaged: (
        _ sessionID: UUID
    ) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertSessionCreationFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckSessionCreationRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Create Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Create Rollback One",
                tagNumber: "CR101",
                pastureID: pasture.id
            )
        )
        _ = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Create Rollback Two",
                tagNumber: "CR102",
                pastureID: pasture.id
            )
        )

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeSessions = try beforeRepository.fetchSessions()
        let beforePersistedAnimalCheckIDs = try failureInjection.persistedAnimalCheckIDs()
        let input = FieldCheckSessionStartInput(
            pastureID: pasture.id,
            startedAt: atomicityDate(year: 2026, month: 9, day: 20, hour: 8),
            notes: "Session creation rollback contract"
        )
        var stagedSessionID: UUID?
        var stagedAnimalCheckIDs = Set<UUID>()

        XCTAssertThrowsError(
            try failureInjection.createSessionFailingAfterSessionStaged(input),
            "The fault-injected create-session operation must fail after the session and an initial roster row have been staged.",
            file: file,
            line: line
        ) { error in
            guard let injected = error as? FieldCheckSessionCreationRollbackInjectedError else {
                XCTFail(
                    "The production operation must surface FieldCheckSessionCreationRollbackInjectedError rather than failing earlier for an unrelated reason: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            switch injected {
            case .afterSessionStaged(let sessionID, let animalCheckIDs):
                stagedSessionID = sessionID
                stagedAnimalCheckIDs = animalCheckIDs
            }
        }

        let failedSessionID = try XCTUnwrap(
            stagedSessionID,
            "The injected sentinel must identify the staged session application UUID.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            stagedAnimalCheckIDs.isEmpty,
            "The creation failpoint must be reached after at least one initial roster row has been staged.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        XCTAssertEqual(
            try afterRepository.fetchSessions(),
            beforeSessions,
            "A failed session-creation boundary must leave the persisted session list unchanged.",
            file: file,
            line: line
        )
        XCTAssertNil(
            try afterRepository.fetchSessionDetail(id: failedSessionID),
            "A failed session-creation boundary must not leave a partial session reachable through repository projections.",
            file: file,
            line: line
        )

        let afterPersistedAnimalCheckIDs = try failureInjection.persistedAnimalCheckIDs()
        XCTAssertEqual(
            afterPersistedAnimalCheckIDs,
            beforePersistedAnimalCheckIDs,
            "A failed session-creation boundary must not leave orphaned roster rows in persistent storage.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            stagedAnimalCheckIDs.isDisjoint(with: afterPersistedAnimalCheckIDs),
            "None of the roster rows identified by the staged failpoint may survive rollback.",
            file: file,
            line: line
        )
    }

    static func assertMissingFindingWritesRollBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckMissingFindingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Missing Finding Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let originalAnimal = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Missing Finding Original Animal",
                tagNumber: "MF201",
                pastureID: pasture.id
            )
        )
        let reassignmentAnimal = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Missing Finding Reassignment Animal",
                tagNumber: "MF202",
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: atomicityDate(year: 2026, month: 9, day: 21, hour: 8),
                notes: "Missing-finding rollback contract"
            )
        )

        let beforeAddRepository = fixture.makeFieldCheckRepository()
        let beforeAddDetail = try XCTUnwrap(
            beforeAddRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let originalCheckID = try XCTUnwrap(
            beforeAddDetail.animalChecks.first { $0.animalID == originalAnimal.id }?.id,
            file: file,
            line: line
        )
        let reassignmentCheckID = try XCTUnwrap(
            beforeAddDetail.animalChecks.first { $0.animalID == reassignmentAnimal.id }?.id,
            file: file,
            line: line
        )
        XCTAssertFalse(
            try XCTUnwrap(
                beforeAddDetail.animalChecks.first { $0.id == originalCheckID },
                file: file,
                line: line
            ).isMissing,
            file: file,
            line: line
        )
        XCTAssertFalse(
            try XCTUnwrap(
                beforeAddDetail.animalChecks.first { $0.id == reassignmentCheckID },
                file: file,
                line: line
            ).isMissing,
            file: file,
            line: line
        )

        let addInput = FieldCheckFindingInput(
            recordedAt: atomicityDate(year: 2026, month: 9, day: 21, hour: 9),
            type: .missingAnimal,
            severity: .warning,
            status: .open,
            note: "Injected missing finding",
            animalID: originalAnimal.id
        )
        let failedAddFindingID = try assertCoordinatedFindingFailureRollsBack(
            expectedOperation: .add,
            expectedFindingID: nil,
            sessionID: sessionID,
            beforeDetail: beforeAddDetail,
            beforeSessions: try beforeAddRepository.fetchSessions(),
            beforeOpenFindings: try beforeAddRepository.fetchOpenFindings(limit: 0),
            using: fixture,
            file: file,
            line: line
        ) {
            try failureInjection.addMissingFindingFailingBetweenFindingAndMissingState(sessionID, addInput)
        }
        let afterFailedAdd = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertFalse(afterFailedAdd.findings.contains { $0.id == failedAddFindingID }, file: file, line: line)
        XCTAssertFalse(
            try XCTUnwrap(
                afterFailedAdd.animalChecks.first { $0.id == originalCheckID },
                file: file,
                line: line
            ).isMissing,
            file: file,
            line: line
        )

        try repository.addFinding(sessionID: sessionID, input: addInput)
        let beforeMutationRepository = fixture.makeFieldCheckRepository()
        let beforeMutationDetail = try XCTUnwrap(
            beforeMutationRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingID = try XCTUnwrap(
            beforeMutationDetail.findings.first {
                $0.type == .missingAnimal && $0.animalID == originalAnimal.id && $0.note == "Injected missing finding"
            }?.id,
            file: file,
            line: line
        )
        XCTAssertTrue(
            try XCTUnwrap(
                beforeMutationDetail.animalChecks.first { $0.id == originalCheckID },
                file: file,
                line: line
            ).isMissing,
            file: file,
            line: line
        )
        XCTAssertFalse(
            try XCTUnwrap(
                beforeMutationDetail.animalChecks.first { $0.id == reassignmentCheckID },
                file: file,
                line: line
            ).isMissing,
            file: file,
            line: line
        )

        let beforeMutationSessions = try beforeMutationRepository.fetchSessions()
        let beforeMutationOpenFindings = try beforeMutationRepository.fetchOpenFindings(limit: 0)
        let reassignmentInput = FieldCheckFindingInput(
            recordedAt: atomicityDate(year: 2026, month: 9, day: 21, hour: 10),
            type: .missingAnimal,
            severity: .critical,
            status: .monitoring,
            note: "Injected reassignment",
            animalID: reassignmentAnimal.id
        )

        _ = try assertCoordinatedFindingFailureRollsBack(
            expectedOperation: .update,
            expectedFindingID: findingID,
            sessionID: sessionID,
            beforeDetail: beforeMutationDetail,
            beforeSessions: beforeMutationSessions,
            beforeOpenFindings: beforeMutationOpenFindings,
            using: fixture,
            file: file,
            line: line
        ) {
            try failureInjection.updateMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                findingID,
                reassignmentInput
            )
        }
        try assertMissingFindingRollbackRosterState(
            sessionID: sessionID,
            originalCheckID: originalCheckID,
            reassignmentCheckID: reassignmentCheckID,
            using: fixture,
            file: file,
            line: line
        )

        _ = try assertCoordinatedFindingFailureRollsBack(
            expectedOperation: .updateStatus,
            expectedFindingID: findingID,
            sessionID: sessionID,
            beforeDetail: beforeMutationDetail,
            beforeSessions: beforeMutationSessions,
            beforeOpenFindings: beforeMutationOpenFindings,
            using: fixture,
            file: file,
            line: line
        ) {
            try failureInjection.updateMissingFindingStatusFailingBetweenFindingAndMissingState(
                sessionID,
                findingID,
                .resolved
            )
        }
        try assertMissingFindingRollbackRosterState(
            sessionID: sessionID,
            originalCheckID: originalCheckID,
            reassignmentCheckID: reassignmentCheckID,
            using: fixture,
            file: file,
            line: line
        )

        _ = try assertCoordinatedFindingFailureRollsBack(
            expectedOperation: .delete,
            expectedFindingID: findingID,
            sessionID: sessionID,
            beforeDetail: beforeMutationDetail,
            beforeSessions: beforeMutationSessions,
            beforeOpenFindings: beforeMutationOpenFindings,
            using: fixture,
            file: file,
            line: line
        ) {
            try failureInjection.deleteMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                findingID
            )
        }
        try assertMissingFindingRollbackRosterState(
            sessionID: sessionID,
            originalCheckID: originalCheckID,
            reassignmentCheckID: reassignmentCheckID,
            using: fixture,
            file: file,
            line: line
        )
    }

    static func assertSessionCompletionFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckSessionCompletionRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Completion Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Completion Rollback Animal",
                tagNumber: "CP301",
                pastureID: pasture.id
            )
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: atomicityDate(year: 2026, month: 9, day: 22, hour: 8),
                notes: "Completion rollback contract"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 1])
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: atomicityDate(year: 2026, month: 9, day: 22, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Completion rollback finding",
                animalID: animal.id
            )
        )

        let staleRawQuickCowCount = 99
        try failureInjection.seedRawQuickCowCount(sessionID, staleRawQuickCowCount)
        let rawQuickCowCountBeforeFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The raw completion-rollback probe must be able to read the seeded session row.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            rawQuickCowCountBeforeFailure,
            staleRawQuickCowCount,
            "The completion rollback fixture must begin with a stale persisted quick count that completion is required to normalize.",
            file: file,
            line: line
        )

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeSessions = try beforeRepository.fetchSessions()
        let beforeOpenFindings = try beforeRepository.fetchOpenFindings(limit: 0)
        XCTAssertNil(beforeDetail.completedAt, file: file, line: line)
        XCTAssertEqual(
            beforeDetail.quickCowCount,
            staleRawQuickCowCount,
            "The snapshot should expose the deliberately stale persisted value so rollback can prove completion did not commit normalization.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            beforeDetail.quickAnimalTypeCounts[.cow],
            1,
            "The derived quick-count projection must still enforce the current roster capacity before completion.",
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDetail.animalChecks.count, 1, file: file, line: line)
        XCTAssertEqual(beforeDetail.findings.count, 1, file: file, line: line)

        XCTAssertThrowsError(
            try failureInjection.completeSessionFailingAfterCompletionStaged(sessionID),
            "The fault-injected completion operation must fail after completion-time mutations have been staged.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckSessionCompletionRollbackInjectedError,
                .afterCompletionStaged(sessionID: sessionID),
                "The production operation must surface the completion rollback sentinel rather than an unrelated early failure.",
                file: file,
                line: line
            )
        }

        let rawQuickCowCountAfterFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The raw completion-rollback probe must still find the session after the injected failure.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            rawQuickCowCountAfterFailure,
            staleRawQuickCowCount,
            "A failed completion must roll back the staged normalization of the deliberately stale persisted quick count.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        let afterDetail = try XCTUnwrap(
            afterRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterDetail,
            beforeDetail,
            "A failed completion boundary must leave the entire persisted session detail unchanged.",
            file: file,
            line: line
        )
        XCTAssertNil(
            afterDetail.completedAt,
            "A failed completion must leave the session open.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDetail.expectedHeadCountSnapshot, beforeDetail.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(afterDetail.quickCowCount, beforeDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickHeiferCount, beforeDetail.quickHeiferCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickCalfCount, beforeDetail.quickCalfCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickBullCount, beforeDetail.quickBullCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickSteerCount, beforeDetail.quickSteerCount, file: file, line: line)
        XCTAssertEqual(
            afterDetail.animalChecks,
            beforeDetail.animalChecks,
            "Completion-time snapshot backfills must not leak out of a failed save boundary.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterDetail.findings,
            beforeDetail.findings,
            "Finding history must remain unchanged when completion rolls back.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchSessions(),
            beforeSessions,
            "A failed completion must leave session-summary projections unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchOpenFindings(limit: 0),
            beforeOpenFindings,
            "A failed completion must leave open-finding projections unchanged.",
            file: file,
            line: line
        )
    }

    private static func assertCoordinatedFindingFailureRollsBack(
        expectedOperation: FieldCheckMissingFindingRollbackOperation,
        expectedFindingID: UUID?,
        sessionID: UUID,
        beforeDetail: FieldCheckSessionDetailSnapshot,
        beforeSessions: [FieldCheckSessionSummary],
        beforeOpenFindings: [FieldCheckFindingSnapshot],
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) throws -> UUID {
        var stagedFindingID: UUID?

        XCTAssertThrowsError(
            try operation(),
            "The fault-injected finding operation must fail between its coordinated finding and roster mutations.",
            file: file,
            line: line
        ) { error in
            guard let injected = error as? FieldCheckMissingFindingRollbackInjectedError else {
                XCTFail(
                    "The production operation must surface FieldCheckMissingFindingRollbackInjectedError rather than failing earlier for an unrelated reason: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            switch injected {
            case .betweenFindingAndMissingState(let actualOperation, let findingID):
                XCTAssertEqual(actualOperation, expectedOperation, file: file, line: line)
                stagedFindingID = findingID
            }
        }

        let failedFindingID = try XCTUnwrap(
            stagedFindingID,
            "The injected sentinel must identify the staged finding application UUID.",
            file: file,
            line: line
        )
        if let expectedFindingID {
            XCTAssertEqual(
                failedFindingID,
                expectedFindingID,
                "The injected sentinel must identify the finding targeted by the failed mutation.",
                file: file,
                line: line
            )
        }

        let afterRepository = fixture.makeFieldCheckRepository()
        try assertRollbackDetailEqualIgnoringRelationshipOrder(
            try afterRepository.fetchSessionDetail(id: sessionID),
            expected: beforeDetail,
            file: file,
            line: line
        )
        try assertRollbackSummariesEqualIgnoringRelationshipOrder(
            try afterRepository.fetchSessions(),
            expected: beforeSessions,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchOpenFindings(limit: 0),
            beforeOpenFindings,
            "A failed coordinated finding write must leave open-finding projections unchanged.",
            file: file,
            line: line
        )
        return failedFindingID
    }

    private static func assertRollbackDetailEqualIgnoringRelationshipOrder(
        _ actual: FieldCheckSessionDetailSnapshot?,
        expected: FieldCheckSessionDetailSnapshot,
        file: StaticString,
        line: UInt
    ) throws {
        let actual = try XCTUnwrap(
            actual,
            "A failed coordinated finding write must leave the session detail readable.",
            file: file,
            line: line
        )

        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.startedAt, expected.startedAt, file: file, line: line)
        XCTAssertEqual(actual.completedAt, expected.completedAt, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, file: file, line: line)
        XCTAssertEqual(actual.pastureID, expected.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expected.pastureName, file: file, line: line)
        XCTAssertEqual(actual.pastureArchivedAt, expected.pastureArchivedAt, file: file, line: line)
        XCTAssertEqual(actual.isPastureArchived, expected.isPastureArchived, file: file, line: line)
        XCTAssertEqual(actual.expectedHeadCountSnapshot, expected.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(actual.quickCowCount, expected.quickCowCount, file: file, line: line)
        XCTAssertEqual(actual.quickHeiferCount, expected.quickHeiferCount, file: file, line: line)
        XCTAssertEqual(actual.quickCalfCount, expected.quickCalfCount, file: file, line: line)
        XCTAssertEqual(actual.quickBullCount, expected.quickBullCount, file: file, line: line)
        XCTAssertEqual(actual.quickSteerCount, expected.quickSteerCount, file: file, line: line)
        XCTAssertEqual(
            actual.animalChecks.sorted(by: rollbackSnapshotIDOrder),
            expected.animalChecks.sorted(by: rollbackSnapshotIDOrder),
            "A failed coordinated finding write must leave roster snapshots unchanged regardless of relationship iteration order.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.findings.sorted(by: rollbackSnapshotIDOrder),
            expected.findings.sorted(by: rollbackSnapshotIDOrder),
            "A failed coordinated finding write must leave finding history unchanged regardless of relationship iteration order.",
            file: file,
            line: line
        )
    }

    private static func assertRollbackSummariesEqualIgnoringRelationshipOrder(
        _ actual: [FieldCheckSessionSummary],
        expected: [FieldCheckSessionSummary],
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertEqual(
            actual.map(\.id),
            expected.map(\.id),
            "A failed coordinated finding write must preserve the repository-defined session-summary ordering.",
            file: file,
            line: line
        )
        guard actual.count == expected.count else { return }

        for (actualSummary, expectedSummary) in zip(actual, expected) {
            XCTAssertEqual(actualSummary.id, expectedSummary.id, file: file, line: line)
            XCTAssertEqual(actualSummary.startedAt, expectedSummary.startedAt, file: file, line: line)
            XCTAssertEqual(actualSummary.completedAt, expectedSummary.completedAt, file: file, line: line)
            XCTAssertEqual(actualSummary.pastureID, expectedSummary.pastureID, file: file, line: line)
            XCTAssertEqual(actualSummary.pastureName, expectedSummary.pastureName, file: file, line: line)
            XCTAssertEqual(actualSummary.pastureArchivedAt, expectedSummary.pastureArchivedAt, file: file, line: line)
            XCTAssertEqual(actualSummary.isPastureArchived, expectedSummary.isPastureArchived, file: file, line: line)
            XCTAssertEqual(
                actualSummary.expectedHeadCountSnapshot,
                expectedSummary.expectedHeadCountSnapshot,
                file: file,
                line: line
            )
            XCTAssertEqual(actualSummary.quickCowCount, expectedSummary.quickCowCount, file: file, line: line)
            XCTAssertEqual(actualSummary.quickHeiferCount, expectedSummary.quickHeiferCount, file: file, line: line)
            XCTAssertEqual(actualSummary.quickCalfCount, expectedSummary.quickCalfCount, file: file, line: line)
            XCTAssertEqual(actualSummary.quickBullCount, expectedSummary.quickBullCount, file: file, line: line)
            XCTAssertEqual(actualSummary.quickSteerCount, expectedSummary.quickSteerCount, file: file, line: line)
            XCTAssertEqual(actualSummary.openFindingsCount, expectedSummary.openFindingsCount, file: file, line: line)
            XCTAssertEqual(
                actualSummary.animalChecks.sorted(by: rollbackSnapshotIDOrder),
                expectedSummary.animalChecks.sorted(by: rollbackSnapshotIDOrder),
                "A failed coordinated finding write must preserve summary roster snapshots regardless of relationship iteration order.",
                file: file,
                line: line
            )
        }
    }

    private static func rollbackSnapshotIDOrder<T: Identifiable>(
        _ lhs: T,
        _ rhs: T
    ) -> Bool where T.ID == UUID {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func assertMissingFindingRollbackRosterState(
        sessionID: UUID,
        originalCheckID: UUID,
        reassignmentCheckID: UUID,
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString,
        line: UInt
    ) throws {
        let detail = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertTrue(
            try XCTUnwrap(detail.animalChecks.first { $0.id == originalCheckID }, file: file, line: line).isMissing,
            "The original roster animal must remain missing when the coordinated mutation rolls back.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try XCTUnwrap(detail.animalChecks.first { $0.id == reassignmentCheckID }, file: file, line: line).isMissing,
            "The reassignment target must remain non-missing when the coordinated mutation rolls back.",
            file: file,
            line: line
        )
    }

    private static func atomicityAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: atomicityDate(year: 2020, month: 1, day: 1),
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

    private static func atomicityDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
