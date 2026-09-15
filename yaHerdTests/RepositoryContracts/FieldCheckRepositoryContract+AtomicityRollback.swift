import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckSessionCreationRollbackInjectedError: Error, Equatable {
    case afterSessionStaged(sessionID: UUID)
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
/// after the session itself has been staged but before its initial roster is fully persisted.
///
/// The final persistence runner should surface the sentinel with the staged application UUID so
/// this contract can prove that neither the partial session nor any of its roster rows survive.
@MainActor
struct FieldCheckSessionCreationRollbackFailureInjection {
    let createSessionFailingAfterSessionStaged: (
        _ input: FieldCheckSessionStartInput
    ) throws -> Void
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
@MainActor
struct FieldCheckSessionCompletionRollbackFailureInjection {
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
        let input = FieldCheckSessionStartInput(
            pastureID: pasture.id,
            startedAt: atomicityDate(year: 2026, month: 9, day: 20, hour: 8),
            notes: "Session creation rollback contract"
        )
        var stagedSessionID: UUID?

        XCTAssertThrowsError(
            try failureInjection.createSessionFailingAfterSessionStaged(input),
            "The fault-injected create-session operation must fail after the session has been staged.",
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
            case .afterSessionStaged(let sessionID):
                stagedSessionID = sessionID
            }
        }

        let failedSessionID = try XCTUnwrap(
            stagedSessionID,
            "The injected sentinel must identify the staged session application UUID.",
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
            "A failed session-creation boundary must not leave a partial session or roster behind.",
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

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeSessions = try beforeRepository.fetchSessions()
        let beforeOpenFindings = try beforeRepository.fetchOpenFindings(limit: 0)
        XCTAssertNil(beforeDetail.completedAt, file: file, line: line)
        XCTAssertEqual(beforeDetail.quickCowCount, 1, file: file, line: line)
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
        XCTAssertEqual(
            try afterRepository.fetchSessionDetail(id: sessionID),
            beforeDetail,
            "A failed coordinated finding write must leave finding history and roster synchronization unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchSessions(),
            beforeSessions,
            "A failed coordinated finding write must leave session-summary projections unchanged.",
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
