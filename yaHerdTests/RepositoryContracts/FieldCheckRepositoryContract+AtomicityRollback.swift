import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckSessionCreationRollbackInjectedError: Error, Equatable {
    case afterSessionStaged(sessionID: UUID)
}

enum FieldCheckMissingFindingRollbackInjectedError: Error, Equatable {
    case betweenFindingAndMissingState(findingID: UUID)
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

/// Permanent fault-injection hook for persistence implementations that can fail an unresolved
/// missing-animal finding write between the finding mutation and synchronized roster mutation.
///
/// The final persistence runner may stage either side first; the injected failure must happen after
/// one side has been staged but before the logical operation commits, and must surface the sentinel
/// with the staged finding application UUID.
@MainActor
struct FieldCheckMissingFindingRollbackFailureInjection {
    let addMissingFindingFailingBetweenFindingAndMissingState: (
        _ sessionID: UUID,
        _ input: FieldCheckFindingInput
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

    static func assertMissingFindingCreationFailureRollsBack(
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
        let animal = try fixture.makeAnimalRepository().create(
            input: atomicityAnimalInput(
                name: "Missing Finding Rollback Animal",
                tagNumber: "MF201",
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

        let beforeRepository = fixture.makeFieldCheckRepository()
        let beforeDetail = try XCTUnwrap(
            beforeRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeCheck = try XCTUnwrap(
            beforeDetail.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        XCTAssertFalse(beforeCheck.isMissing, file: file, line: line)
        let beforeSessions = try beforeRepository.fetchSessions()
        let beforeOpenFindings = try beforeRepository.fetchOpenFindings(limit: 0)

        let input = FieldCheckFindingInput(
            recordedAt: atomicityDate(year: 2026, month: 9, day: 21, hour: 9),
            type: .missingAnimal,
            severity: .warning,
            status: .open,
            note: "Injected missing finding",
            animalID: animal.id
        )
        var stagedFindingID: UUID?

        XCTAssertThrowsError(
            try failureInjection.addMissingFindingFailingBetweenFindingAndMissingState(sessionID, input),
            "The fault-injected missing-finding operation must fail between its two coordinated mutations.",
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
            case .betweenFindingAndMissingState(let findingID):
                stagedFindingID = findingID
            }
        }

        let failedFindingID = try XCTUnwrap(
            stagedFindingID,
            "The injected sentinel must identify the staged finding application UUID.",
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
            "A failed missing-finding boundary must leave both finding history and synchronized roster state unchanged.",
            file: file,
            line: line
        )
        XCTAssertFalse(afterDetail.findings.contains { $0.id == failedFindingID }, file: file, line: line)
        let afterCheck = try XCTUnwrap(
            afterDetail.animalChecks.first { $0.id == beforeCheck.id },
            file: file,
            line: line
        )
        XCTAssertFalse(
            afterCheck.isMissing,
            "The roster animal must not remain missing when the coordinated finding write rolls back.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try afterRepository.fetchSessions(),
            beforeSessions,
            "A failed missing-finding boundary must leave session-summary projections unchanged.",
            file: file,
            line: line
        )
        let afterOpenFindings = try afterRepository.fetchOpenFindings(limit: 0)
        XCTAssertEqual(
            afterOpenFindings,
            beforeOpenFindings,
            "A failed missing-finding boundary must not leak a partial finding into open-finding projections.",
            file: file,
            line: line
        )
        XCTAssertFalse(afterOpenFindings.contains { $0.id == failedFindingID }, file: file, line: line)
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
