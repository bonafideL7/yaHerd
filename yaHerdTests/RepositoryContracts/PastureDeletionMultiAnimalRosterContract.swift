import XCTest
@testable import yaHerd

/// Permanent characterization that pasture deletion preserves complete to-many Field Check rosters.
@MainActor
enum PastureDeletionMultiAnimalRosterContract {
    static func assertDeletionPreservesCompleteFieldCheckRoster(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let pasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Multi-Roster Pasture",
                acreage: 30,
                usableAcreage: 27,
                targetAcresPerHead: 1.5
            )
        )

        let animalRepository = fixture.makeAnimalRepository()
        let firstAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Multi-Roster Cow 1",
                tagNumber: "801",
                pastureID: pasture.id
            )
        )
        let secondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Multi-Roster Cow 2",
                tagNumber: "802",
                pastureID: pasture.id
            )
        )

        let startedAt = Date(timeIntervalSince1970: 1_780_259_200)
        let archivedAt = Date(timeIntervalSince1970: 1_780_345_600)
        let fieldCheckRepository = fixture.makeFieldCheckRepository()
        let sessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: startedAt,
                notes: "Deletion multi-animal roster contract"
            )
        )

        try fixture.deletePastures([pasture.id], archivedAt)

        let reloadedFieldChecks = fixture.makeFieldCheckRepository()
        let archivedSession = try XCTUnwrap(
            reloadedFieldChecks.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, 2, file: file, line: line)
        XCTAssertEqual(archivedSession.animalChecks.count, 2, file: file, line: line)

        let actualAnimalIDs = archivedSession.animalChecks.compactMap(\.animalID)
        XCTAssertEqual(actualAnimalIDs.count, 2, file: file, line: line)
        XCTAssertEqual(
            Set(actualAnimalIDs),
            Set([firstAnimal.id, secondAnimal.id]),
            "Deleting a pasture must preserve every Field Check animal snapshot, not only the first.",
            file: file,
            line: line
        )

        let firstCheck = try XCTUnwrap(
            archivedSession.animalChecks.first { $0.animalID == firstAnimal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(firstCheck.displayTagNumber, "801", file: file, line: line)

        let secondCheck = try XCTUnwrap(
            archivedSession.animalChecks.first { $0.animalID == secondAnimal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(secondCheck.displayTagNumber, "802", file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedFieldChecks.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.expectedHeadCountSnapshot, 2, file: file, line: line)
        XCTAssertEqual(summary.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(summary.pastureName, "Delete Multi-Roster Pasture", file: file, line: line)
        XCTAssertEqual(summary.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(summary.isPastureArchived, file: file, line: line)
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
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
}
