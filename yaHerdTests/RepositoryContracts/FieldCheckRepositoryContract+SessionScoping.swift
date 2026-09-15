import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    static func assertChildMutationIDsAreSessionScoped(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Session Scope Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Session Scope Animal",
                tagNumber: "SS801",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
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

        let repository = fixture.makeFieldCheckRepository()
        let firstSessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_780_400_000),
                notes: "First scoped session"
            )
        )
        let secondSessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_780_486_400),
                notes: "Second scoped session"
            )
        )

        try repository.addFinding(
            sessionID: firstSessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_780_403_600),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "First scoped finding",
                animalID: animal.id
            )
        )
        try repository.addFinding(
            sessionID: secondSessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_780_490_000),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Second scoped finding",
                animalID: animal.id
            )
        )

        let firstBefore = try XCTUnwrap(
            repository.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let secondBefore = try XCTUnwrap(
            repository.fetchSessionDetail(id: secondSessionID),
            file: file,
            line: line
        )
        let firstCheck = try XCTUnwrap(firstBefore.animalChecks.first, file: file, line: line)
        let secondCheck = try XCTUnwrap(secondBefore.animalChecks.first, file: file, line: line)
        let firstFinding = try XCTUnwrap(firstBefore.findings.first, file: file, line: line)
        let secondFinding = try XCTUnwrap(secondBefore.findings.first, file: file, line: line)

        func assertAnimalCheckNotFound(_ operation: () throws -> Void) {
            XCTAssertThrowsError(try operation(), file: file, line: line) { error in
                guard let repositoryError = error as? FieldCheckRepositoryError,
                      case .animalCheckNotFound = repositoryError else {
                    XCTFail(
                        "Expected animalCheckNotFound for a child UUID owned by another session, received \(error).",
                        file: file,
                        line: line
                    )
                    return
                }
            }
        }

        func assertFindingNotFound(_ operation: () throws -> Void) {
            XCTAssertThrowsError(try operation(), file: file, line: line) { error in
                guard let repositoryError = error as? FieldCheckRepositoryError,
                      case .findingNotFound = repositoryError else {
                    XCTFail(
                        "Expected findingNotFound for a child UUID owned by another session, received \(error).",
                        file: file,
                        line: line
                    )
                    return
                }
            }
        }

        for (sessionID, foreignCheckID) in [
            (firstSessionID, secondCheck.id),
            (secondSessionID, firstCheck.id)
        ] {
            assertAnimalCheckNotFound {
                try repository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: foreignCheckID,
                    isCounted: true
                )
            }
            assertAnimalCheckNotFound {
                try repository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: foreignCheckID,
                    isMissing: true
                )
            }
        }

        for (sessionID, foreignFindingID) in [
            (firstSessionID, secondFinding.id),
            (secondSessionID, firstFinding.id)
        ] {
            assertFindingNotFound {
                try repository.updateFinding(
                    sessionID: sessionID,
                    findingID: foreignFindingID,
                    input: FieldCheckFindingInput(
                        recordedAt: Date(timeIntervalSince1970: 1_780_493_600),
                        type: .limping,
                        severity: .critical,
                        status: .monitoring,
                        note: "Must not cross session boundary",
                        animalID: animal.id
                    )
                )
            }
            assertFindingNotFound {
                try repository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: foreignFindingID,
                    status: .resolved
                )
            }
            assertFindingNotFound {
                try repository.deleteFinding(
                    sessionID: sessionID,
                    findingID: foreignFindingID
                )
            }
        }

        let firstAfter = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let secondAfter = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: secondSessionID),
            file: file,
            line: line
        )

        let firstCheckAfter = try XCTUnwrap(
            firstAfter.animalChecks.first { $0.id == firstCheck.id },
            file: file,
            line: line
        )
        let secondCheckAfter = try XCTUnwrap(
            secondAfter.animalChecks.first { $0.id == secondCheck.id },
            file: file,
            line: line
        )
        XCTAssertFalse(firstCheckAfter.wasCounted, file: file, line: line)
        XCTAssertFalse(firstCheckAfter.isMissing, file: file, line: line)
        XCTAssertFalse(secondCheckAfter.wasCounted, file: file, line: line)
        XCTAssertFalse(secondCheckAfter.isMissing, file: file, line: line)

        let firstFindingAfter = try XCTUnwrap(
            firstAfter.findings.first { $0.id == firstFinding.id },
            file: file,
            line: line
        )
        let secondFindingAfter = try XCTUnwrap(
            secondAfter.findings.first { $0.id == secondFinding.id },
            file: file,
            line: line
        )
        XCTAssertEqual(firstAfter.findings.count, 1, file: file, line: line)
        XCTAssertEqual(secondAfter.findings.count, 1, file: file, line: line)
        XCTAssertEqual(firstFindingAfter.sessionID, firstSessionID, file: file, line: line)
        XCTAssertEqual(secondFindingAfter.sessionID, secondSessionID, file: file, line: line)
        XCTAssertEqual(firstFindingAfter.status, .open, file: file, line: line)
        XCTAssertEqual(secondFindingAfter.status, .open, file: file, line: line)
        XCTAssertEqual(firstFindingAfter.note, "First scoped finding", file: file, line: line)
        XCTAssertEqual(secondFindingAfter.note, "Second scoped finding", file: file, line: line)
    }
}
