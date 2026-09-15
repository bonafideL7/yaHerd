import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    static func assertHardDeletedAnimalPreservesHistoricalSnapshots(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Hard Delete Snapshot Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let color = TagColorSnapshot(
            id: UUID(),
            name: "Hard Delete Snapshot Color",
            prefix: "HD",
            rgba: RGBAColor(r: 0.4, g: 0.5, b: 0.6)
        )
        try fixture.makeTagColorRepository().upsert(color)

        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Hard Delete Snapshot Animal",
                tagNumber: "HD701",
                tagColorID: color.id,
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

        let fieldChecks = fixture.makeFieldCheckRepository()
        let sessionID = try fieldChecks.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_780_000_000),
                notes: "Hard delete snapshot contract"
            )
        )
        let beforeDelete = try XCTUnwrap(
            fieldChecks.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkBeforeDelete = try XCTUnwrap(
            beforeDelete.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )

        try fieldChecks.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_780_003_600),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Snapshot must survive hard delete",
                animalID: animal.id
            )
        )
        let withFinding = try XCTUnwrap(
            fieldChecks.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingBeforeDelete = try XCTUnwrap(
            withFinding.findings.first { $0.animalID == animal.id },
            file: file,
            line: line
        )

        try fixture.makeAnimalRepository().delete(ids: [animal.id])
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            "The fixture must hard-delete the linked live animal.",
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkAfterDelete = try XCTUnwrap(
            reloaded.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Hard-deleting a live animal must not cascade-delete its Field Check roster history.",
            file: file,
            line: line
        )
        XCTAssertEqual(checkAfterDelete.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.displayTagNumber, checkBeforeDelete.displayTagNumber, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.displayTagColorID, checkBeforeDelete.displayTagColorID, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.animalName, checkBeforeDelete.animalName, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.animalSex, checkBeforeDelete.animalSex, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.animalType, checkBeforeDelete.animalType, file: file, line: line)
        XCTAssertEqual(checkAfterDelete.wasExpectedAtStart, checkBeforeDelete.wasExpectedAtStart, file: file, line: line)

        let findingAfterDelete = try XCTUnwrap(
            reloaded.findings.first { $0.id == findingBeforeDelete.id },
            "Hard-deleting a live animal must not cascade-delete its Field Check finding history.",
            file: file,
            line: line
        )
        XCTAssertEqual(findingAfterDelete.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.animalDisplayTagNumber, findingBeforeDelete.animalDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.animalDisplayTagColorID, findingBeforeDelete.animalDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.pastureName, findingBeforeDelete.pastureName, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.sessionID, sessionID, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.note, "Snapshot must survive hard delete", file: file, line: line)
    }
}
