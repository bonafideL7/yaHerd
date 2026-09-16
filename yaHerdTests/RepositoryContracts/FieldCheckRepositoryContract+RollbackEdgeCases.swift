import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckRosterStateRollbackInjectedError: Error, Equatable {
    case afterMissingStateAndQuickCountNormalizationStaged(sessionID: UUID, animalCheckID: UUID)
}

/// Permanent fault-injection hook for persistence implementations that can fail after both a roster
/// missing-state mutation and its associated quick-count normalization have been staged but before
/// the logical operation commits.
///
/// The raw quick-count accessor intentionally bypasses repository projection normalization so the
/// final persistence runner can prove both durable values roll back together.
@MainActor
struct FieldCheckRosterStateRollbackFailureInjection {
    let rawQuickCowCount: (
        _ sessionID: UUID
    ) throws -> Int?
    let setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged: (
        _ sessionID: UUID,
        _ animalCheckID: UUID,
        _ isMissing: Bool
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
