import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    static func assertMissingFindingResolutionAndDeletionSynchronizeRoster(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Missing Finding Synchronization Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Missing Finding Synchronization Animal",
                tagNumber: "MF901",
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
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_780_200_000),
                notes: "Missing finding synchronization contract"
            )
        )

        func addMissingFinding(note: String, recordedAt: Date) throws -> UUID {
            try repository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: recordedAt,
                    type: .missingAnimal,
                    severity: .warning,
                    status: .open,
                    note: note,
                    animalID: animal.id
                )
            )
            let detail = try XCTUnwrap(
                fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
                file: file,
                line: line
            )
            return try XCTUnwrap(
                detail.findings.first { $0.note == note }?.id,
                file: file,
                line: line
            )
        }

        func reloadedAnimalCheck() throws -> FieldCheckAnimalCheckSnapshot {
            let detail = try XCTUnwrap(
                fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
                file: file,
                line: line
            )
            return try XCTUnwrap(
                detail.animalChecks.first { $0.animalID == animal.id },
                file: file,
                line: line
            )
        }

        let firstResolvableID = try addMissingFinding(
            note: "Resolve first missing finding",
            recordedAt: Date(timeIntervalSince1970: 1_780_203_600)
        )
        let secondResolvableID = try addMissingFinding(
            note: "Resolve second missing finding",
            recordedAt: Date(timeIntervalSince1970: 1_780_207_200)
        )
        XCTAssertTrue(
            try reloadedAnimalCheck().isMissing,
            "Any unresolved missing-animal finding must mark the roster animal missing.",
            file: file,
            line: line
        )

        try repository.updateFindingStatus(
            sessionID: sessionID,
            findingID: firstResolvableID,
            status: .resolved
        )
        XCTAssertTrue(
            try reloadedAnimalCheck().isMissing,
            "Resolving one missing-animal finding must preserve missing state while another unresolved missing finding remains.",
            file: file,
            line: line
        )

        try repository.updateFindingStatus(
            sessionID: sessionID,
            findingID: secondResolvableID,
            status: .resolved
        )
        XCTAssertFalse(
            try reloadedAnimalCheck().isMissing,
            "Resolving the final unresolved missing-animal finding must clear synchronized roster missing state.",
            file: file,
            line: line
        )
        let afterResolution = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterResolution.findings.first { $0.id == firstResolvableID }?.status,
            .resolved,
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterResolution.findings.first { $0.id == secondResolvableID }?.status,
            .resolved,
            file: file,
            line: line
        )

        let firstDeletableID = try addMissingFinding(
            note: "Delete first missing finding",
            recordedAt: Date(timeIntervalSince1970: 1_780_210_800)
        )
        let secondDeletableID = try addMissingFinding(
            note: "Delete second missing finding",
            recordedAt: Date(timeIntervalSince1970: 1_780_214_400)
        )
        XCTAssertTrue(
            try reloadedAnimalCheck().isMissing,
            file: file,
            line: line
        )

        try repository.deleteFinding(sessionID: sessionID, findingID: firstDeletableID)
        XCTAssertTrue(
            try reloadedAnimalCheck().isMissing,
            "Deleting one missing-animal finding must preserve missing state while another unresolved missing finding remains.",
            file: file,
            line: line
        )

        try repository.deleteFinding(sessionID: sessionID, findingID: secondDeletableID)
        let afterDeletion = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let animalCheckAfterDeletion = try XCTUnwrap(
            afterDeletion.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        XCTAssertFalse(
            animalCheckAfterDeletion.isMissing,
            "Deleting the final unresolved missing-animal finding must clear synchronized roster missing state.",
            file: file,
            line: line
        )
        XCTAssertFalse(afterDeletion.findings.contains { $0.id == firstDeletableID }, file: file, line: line)
        XCTAssertFalse(afterDeletion.findings.contains { $0.id == secondDeletableID }, file: file, line: line)
        XCTAssertTrue(afterDeletion.findings.contains { $0.id == firstResolvableID && $0.status == .resolved }, file: file, line: line)
        XCTAssertTrue(afterDeletion.findings.contains { $0.id == secondResolvableID && $0.status == .resolved }, file: file, line: line)
    }
}
