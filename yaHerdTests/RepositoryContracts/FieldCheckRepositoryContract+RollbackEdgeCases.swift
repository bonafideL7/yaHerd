import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckRosterStateRollbackInjectedError: Error, Equatable {
    case afterMissingStateAndQuickCountNormalizationStaged(sessionID: UUID, animalCheckID: UUID)
    case afterCountedStateAndQuickCountNormalizationStaged(sessionID: UUID, animalCheckID: UUID)
}

/// Permanent fault-injection hook for persistence implementations that can fail after a coordinated
/// roster-state mutation and its associated quick-count normalization have been staged but before
/// the logical operation commits.
///
/// The raw quick-count accessors intentionally bypass repository projection normalization so the
/// final persistence runner can seed a value that the staged operation must change, then prove both
/// durable values roll back together.
@MainActor
struct FieldCheckRosterStateRollbackFailureInjection {
    let seedRawQuickCowCount: (
        _ sessionID: UUID,
        _ count: Int
    ) throws -> Void
    let rawQuickCowCount: (
        _ sessionID: UUID
    ) throws -> Int?
    let setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged: (
        _ sessionID: UUID,
        _ animalCheckID: UUID,
        _ isMissing: Bool
    ) throws -> Void
    let setAnimalCheckCountedFailingAfterRosterStateAndNormalizationStaged: (
        _ sessionID: UUID,
        _ animalCheckID: UUID,
        _ isCounted: Bool
    ) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertMissingFindingTypeTransitionFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckMissingFindingRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Type Transition Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: rollbackEdgeAnimalInput(
                name: "Type Transition Rollback Animal",
                tagNumber: "TR401",
                pastureID: pasture.id
            )
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: rollbackEdgeDate(year: 2026, month: 9, day: 23, hour: 8),
                notes: "Finding type transition rollback contract"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: rollbackEdgeDate(year: 2026, month: 9, day: 23, hour: 9),
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Original missing finding",
                animalID: animal.id
            )
        )

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingBeforeFailure = try XCTUnwrap(
            beforeDetail.findings.first { $0.type == .missingAnimal && $0.animalID == animal.id },
            file: file,
            line: line
        )
        let animalCheckBeforeFailure = try XCTUnwrap(
            beforeDetail.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        XCTAssertTrue(
            animalCheckBeforeFailure.isMissing,
            "The fixture must begin with the roster animal synchronized to the unresolved missing-animal finding.",
            file: file,
            line: line
        )
        let openFindingsBeforeFailure = try beforeRepository.fetchOpenFindings(limit: 0)
        let summaryBeforeFailure = try XCTUnwrap(
            beforeRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )

        let transitionInput = FieldCheckFindingInput(
            recordedAt: rollbackEdgeDate(year: 2026, month: 9, day: 23, hour: 10),
            type: .limping,
            severity: .critical,
            status: .monitoring,
            note: "Injected non-missing transition",
            animalID: animal.id
        )
        var stagedFindingID: UUID?

        XCTAssertThrowsError(
            try failureInjection.updateMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                findingBeforeFailure.id,
                transitionInput
            ),
            "The fault-injected type transition must fail between the finding mutation and synchronized roster mutation.",
            file: file,
            line: line
        ) { error in
            guard let injected = error as? FieldCheckMissingFindingRollbackInjectedError else {
                XCTFail(
                    "The operation must surface FieldCheckMissingFindingRollbackInjectedError rather than an unrelated early failure: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            switch injected {
            case .betweenFindingAndMissingState(let operation, let findingID):
                XCTAssertEqual(operation, .update, file: file, line: line)
                stagedFindingID = findingID
            }
        }
        XCTAssertEqual(
            stagedFindingID,
            findingBeforeFailure.id,
            "The failpoint must identify the finding whose type transition was staged.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        let afterDetail = try XCTUnwrap(
            afterRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingAfterFailure = try XCTUnwrap(
            afterDetail.findings.first { $0.id == findingBeforeFailure.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            findingAfterFailure,
            findingBeforeFailure,
            "A failed missing-to-non-missing type transition must preserve the complete persisted finding snapshot.",
            file: file,
            line: line
        )

        let animalCheckAfterFailure = try XCTUnwrap(
            afterDetail.animalChecks.first { $0.id == animalCheckBeforeFailure.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            animalCheckAfterFailure,
            animalCheckBeforeFailure,
            "A failed finding type transition must preserve the synchronized roster row.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            animalCheckAfterFailure.isMissing,
            "The roster animal must remain missing when a missing-to-non-missing finding update rolls back.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchOpenFindings(limit: 0),
            openFindingsBeforeFailure,
            "A failed type transition must leave open-finding projections unchanged.",
            file: file,
            line: line
        )
        let summaryAfterFailure = try XCTUnwrap(
            afterRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterFailure.openFindingsCount, summaryBeforeFailure.openFindingsCount, file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.missingAnimalCount, summaryBeforeFailure.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            summaryAfterFailure.animalChecks.first { $0.id == animalCheckBeforeFailure.id },
            summaryBeforeFailure.animalChecks.first { $0.id == animalCheckBeforeFailure.id },
            "A failed type transition must leave the summary roster projection unchanged.",
            file: file,
            line: line
        )
    }

    static func assertRosterMissingStateNormalizationFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckRosterStateRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Roster State Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: rollbackEdgeAnimalInput(
                name: "Roster State Rollback Animal",
                tagNumber: "RS501",
                pastureID: pasture.id
            )
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: rollbackEdgeDate(year: 2026, month: 9, day: 24, hour: 8),
                notes: "Roster-state normalization rollback contract"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 1])

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkBeforeFailure = try XCTUnwrap(
            beforeDetail.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(checkBeforeFailure.animalType, .cow, file: file, line: line)
        XCTAssertFalse(checkBeforeFailure.isMissing, file: file, line: line)
        XCTAssertFalse(checkBeforeFailure.wasCounted, file: file, line: line)
        XCTAssertEqual(beforeDetail.quickCowCount, 1, file: file, line: line)
        XCTAssertEqual(beforeDetail.quickAnimalTypeCounts[.cow], 1, file: file, line: line)
        XCTAssertEqual(beforeDetail.missingAnimalCount, 0, file: file, line: line)

        let rawQuickCowCountBeforeFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The raw roster-state rollback probe must find the persisted session quick count.",
            file: file,
            line: line
        )
        XCTAssertEqual(rawQuickCowCountBeforeFailure, 1, file: file, line: line)

        let summaryBeforeFailure = try XCTUnwrap(
            beforeRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try failureInjection.setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged(
                sessionID,
                checkBeforeFailure.id,
                true
            ),
            "The fault-injected roster mutation must fail after both missing state and quick-count normalization have been staged.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckRosterStateRollbackInjectedError,
                .afterMissingStateAndQuickCountNormalizationStaged(
                    sessionID: sessionID,
                    animalCheckID: checkBeforeFailure.id
                ),
                "The operation must surface the roster-state rollback sentinel rather than an unrelated early failure.",
                file: file,
                line: line
            )
        }

        let rawQuickCowCountAfterFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The raw roster-state rollback probe must still find the persisted session after failure.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            rawQuickCowCountAfterFailure,
            rawQuickCowCountBeforeFailure,
            "A failed roster-state write must roll back the staged raw quick-count normalization.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        let afterDetail = try XCTUnwrap(
            afterRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkAfterFailure = try XCTUnwrap(
            afterDetail.animalChecks.first { $0.id == checkBeforeFailure.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            checkAfterFailure,
            checkBeforeFailure,
            "A failed roster-state write must preserve the complete persisted roster snapshot.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            checkAfterFailure.isMissing,
            "A failed setAnimalCheckMissing operation must not leak its staged missing state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDetail.quickCowCount, beforeDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickAnimalTypeCounts[.cow], beforeDetail.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterDetail.missingAnimalCount, beforeDetail.missingAnimalCount, file: file, line: line)

        let summaryAfterFailure = try XCTUnwrap(
            afterRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterFailure.quickCowCount, summaryBeforeFailure.quickCowCount, file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.quickAnimalTypeCounts[.cow], summaryBeforeFailure.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.missingAnimalCount, summaryBeforeFailure.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            summaryAfterFailure.animalChecks.first { $0.id == checkBeforeFailure.id },
            summaryBeforeFailure.animalChecks.first { $0.id == checkBeforeFailure.id },
            "A failed roster-state write must leave the summary roster projection unchanged.",
            file: file,
            line: line
        )
    }

    static func assertRosterCountedStateNormalizationFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckRosterStateRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Counted State Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: rollbackEdgeAnimalInput(
                name: "Counted State Rollback Animal",
                tagNumber: "RS502",
                pastureID: pasture.id
            )
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: rollbackEdgeDate(year: 2026, month: 9, day: 25, hour: 8),
                notes: "Counted-state normalization rollback contract"
            )
        )
        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let animalCheckID = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        try repository.setAnimalCheckMissing(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isMissing: true
        )

        let staleRawQuickCowCount = 99
        try failureInjection.seedRawQuickCowCount(sessionID, staleRawQuickCowCount)

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkBeforeFailure = try XCTUnwrap(
            beforeDetail.animalChecks.first { $0.id == animalCheckID },
            file: file,
            line: line
        )
        XCTAssertTrue(checkBeforeFailure.isMissing, file: file, line: line)
        XCTAssertFalse(checkBeforeFailure.wasCounted, file: file, line: line)
        XCTAssertEqual(beforeDetail.quickCowCount, staleRawQuickCowCount, file: file, line: line)
        XCTAssertEqual(
            beforeDetail.quickAnimalTypeCounts[.cow],
            0,
            "A missing roster animal has no quick-count capacity even while the raw stored value is deliberately stale.",
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDetail.missingAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(beforeDetail.individuallyVerifiedCount, 0, file: file, line: line)

        let rawQuickCowCountBeforeFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The counted-state rollback probe must read the deliberately stale persisted quick count.",
            file: file,
            line: line
        )
        XCTAssertEqual(rawQuickCowCountBeforeFailure, staleRawQuickCowCount, file: file, line: line)
        let summaryBeforeFailure = try XCTUnwrap(
            beforeRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try failureInjection.setAnimalCheckCountedFailingAfterRosterStateAndNormalizationStaged(
                sessionID,
                animalCheckID,
                true
            ),
            "The fault-injected counted-state mutation must fail after counted/missing state and quick-count normalization have been staged.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckRosterStateRollbackInjectedError,
                .afterCountedStateAndQuickCountNormalizationStaged(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID
                ),
                "The operation must surface the counted-state rollback sentinel rather than an unrelated early failure.",
                file: file,
                line: line
            )
        }

        let rawQuickCowCountAfterFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The raw counted-state rollback probe must still find the persisted session after failure.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            rawQuickCowCountAfterFailure,
            staleRawQuickCowCount,
            "A failed counted-state write must roll back the staged quick-count normalization from 99 to zero.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        let afterDetail = try XCTUnwrap(
            afterRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkAfterFailure = try XCTUnwrap(
            afterDetail.animalChecks.first { $0.id == animalCheckID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            checkAfterFailure,
            checkBeforeFailure,
            "A failed counted-state write must preserve the complete persisted roster row.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            checkAfterFailure.isMissing,
            "A failed counted transition must not leak the staged clearing of missing state.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            checkAfterFailure.wasCounted,
            "A failed counted transition must not leak its staged counted timestamp.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDetail.quickCowCount, beforeDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickAnimalTypeCounts[.cow], beforeDetail.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterDetail.missingAnimalCount, beforeDetail.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(afterDetail.individuallyVerifiedCount, beforeDetail.individuallyVerifiedCount, file: file, line: line)

        let summaryAfterFailure = try XCTUnwrap(
            afterRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterFailure.quickCowCount, summaryBeforeFailure.quickCowCount, file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.quickAnimalTypeCounts[.cow], summaryBeforeFailure.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.missingAnimalCount, summaryBeforeFailure.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(summaryAfterFailure.individuallyVerifiedCount, summaryBeforeFailure.individuallyVerifiedCount, file: file, line: line)
        XCTAssertEqual(
            summaryAfterFailure.animalChecks.first { $0.id == animalCheckID },
            summaryBeforeFailure.animalChecks.first { $0.id == animalCheckID },
            "A failed counted-state write must leave the summary roster projection unchanged.",
            file: file,
            line: line
        )
    }

    static func assertMissingFindingQuickCountNormalizationFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckMissingFindingRollbackFailureInjection,
        rawQuickCowCount: (_ sessionID: UUID) throws -> Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Finding Quick Count Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let firstAnimal = try fixture.makeAnimalRepository().create(
            input: rollbackEdgeAnimalInput(
                name: "Finding Quick Count One",
                tagNumber: "FQ601",
                pastureID: pasture.id
            )
        )
        _ = try fixture.makeAnimalRepository().create(
            input: rollbackEdgeAnimalInput(
                name: "Finding Quick Count Two",
                tagNumber: "FQ602",
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: rollbackEdgeDate(year: 2026, month: 9, day: 26, hour: 8),
                notes: "Finding quick-count rollback contract"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 2])

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDetail.quickCowCount, 2, file: file, line: line)
        XCTAssertEqual(beforeDetail.quickAnimalTypeCounts[.cow], 2, file: file, line: line)
        XCTAssertEqual(beforeDetail.missingAnimalCount, 0, file: file, line: line)
        let firstCheckID = try XCTUnwrap(
            beforeDetail.animalChecks.first { $0.animalID == firstAnimal.id }?.id,
            file: file,
            line: line
        )
        let rawBeforeFailure = try XCTUnwrap(
            rawQuickCowCount(sessionID),
            "The finding rollback raw-count probe must find the persisted session.",
            file: file,
            line: line
        )
        XCTAssertEqual(rawBeforeFailure, 2, file: file, line: line)
        let beforeSummary = try XCTUnwrap(
            beforeRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let beforeOpenFindings = try beforeRepository.fetchOpenFindings(limit: 0)

        let input = FieldCheckFindingInput(
            recordedAt: rollbackEdgeDate(year: 2026, month: 9, day: 26, hour: 9),
            type: .missingAnimal,
            severity: .warning,
            status: .open,
            note: "Injected quick-count missing finding",
            animalID: firstAnimal.id
        )
        var stagedFindingID: UUID?
        XCTAssertThrowsError(
            try failureInjection.addMissingFindingFailingBetweenFindingAndMissingState(sessionID, input),
            "The fault-injected missing-finding add must fail after a coordinated mutation has been staged.",
            file: file,
            line: line
        ) { error in
            guard let injected = error as? FieldCheckMissingFindingRollbackInjectedError else {
                XCTFail(
                    "The operation must surface FieldCheckMissingFindingRollbackInjectedError rather than an unrelated early failure: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            switch injected {
            case .betweenFindingAndMissingState(let operation, let findingID):
                XCTAssertEqual(operation, .add, file: file, line: line)
                stagedFindingID = findingID
            }
        }
        let failedFindingID = try XCTUnwrap(stagedFindingID, file: file, line: line)

        let rawAfterFailure = try XCTUnwrap(
            rawQuickCowCount(sessionID),
            "The raw-count probe must still find the session after the injected failure.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            rawAfterFailure,
            rawBeforeFailure,
            "A failed missing-finding write must roll back the staged quick-count normalization from two cows to one.",
            file: file,
            line: line
        )

        let afterRepository = fixture.makeFieldCheckRepository()
        let afterDetail = try XCTUnwrap(
            afterRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertFalse(afterDetail.findings.contains { $0.id == failedFindingID }, file: file, line: line)
        let firstCheckAfterFailure = try XCTUnwrap(
            afterDetail.animalChecks.first { $0.id == firstCheckID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            firstCheckAfterFailure.isMissing,
            "The failed finding add must not leak synchronized missing state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDetail.quickCowCount, beforeDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterDetail.quickAnimalTypeCounts[.cow], beforeDetail.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterDetail.missingAnimalCount, beforeDetail.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            try afterRepository.fetchOpenFindings(limit: 0),
            beforeOpenFindings,
            file: file,
            line: line
        )

        let afterSummary = try XCTUnwrap(
            afterRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(afterSummary.quickCowCount, beforeSummary.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterSummary.quickAnimalTypeCounts[.cow], beforeSummary.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterSummary.missingAnimalCount, beforeSummary.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            afterSummary.animalChecks.first { $0.id == firstCheckID },
            beforeSummary.animalChecks.first { $0.id == firstCheckID },
            "The summary roster projection must remain unchanged when the coordinated finding write rolls back.",
            file: file,
            line: line
        )
    }

    private static func rollbackEdgeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: rollbackEdgeDate(year: 2020, month: 1, day: 1),
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

    private static func rollbackEdgeDate(
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
