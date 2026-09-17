import XCTest
@testable import yaHerd

@MainActor
extension AnimalRepositoryContract {
    /// Permanent future-state coverage that verifies batch pasture moves affect only the requested
    /// animal IDs, including nil-destination unassignment.
    static func assertMovementHonorsSelectedAnimalIDs(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let north = try pastureRepository.create(
            input: PastureInput(
                name: "Subset Contract North",
                acreage: 25,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )
        let south = try pastureRepository.create(
            input: PastureInput(
                name: "Subset Contract South",
                acreage: 30,
                usableAcreage: 28,
                targetAcresPerHead: 1.75
            )
        )

        let repository = fixture.makeAnimalRepository()
        let firstSelected = try repository.create(
            input: subsetMovementAnimalInput(
                name: "Subset Contract Cow One",
                tagNumber: "SM01",
                birthDate: subsetContractDate(year: 2021, month: 3, day: 4),
                pastureID: north.id
            )
        )
        let secondSelected = try repository.create(
            input: subsetMovementAnimalInput(
                name: "Subset Contract Cow Two",
                tagNumber: "SM02",
                birthDate: subsetContractDate(year: 2021, month: 3, day: 5),
                pastureID: north.id
            )
        )
        let unselected = try repository.create(
            input: subsetMovementAnimalInput(
                name: "Subset Contract Cow Unselected",
                tagNumber: "SM03",
                birthDate: subsetContractDate(year: 2021, month: 3, day: 6),
                pastureID: north.id
            )
        )
        let selectedIDs = [firstSelected.id, secondSelected.id]
        let unselectedTimelineBeforeMove = try repository.fetchTimeline(id: unselected.id)

        try repository.move(ids: selectedIDs, toPastureID: south.id)

        let movedRepository = fixture.makeAnimalRepository()
        let unselectedAfterMove = try XCTUnwrap(
            movedRepository.fetchAnimalDetail(id: unselected.id),
            "A batch move must not remove an unselected source-pasture resident.",
            file: file,
            line: line
        )
        XCTAssertEqual(unselectedAfterMove.pastureID, north.id, file: file, line: line)
        XCTAssertEqual(unselectedAfterMove.pastureName, north.name, file: file, line: line)
        XCTAssertEqual(
            try movedRepository.fetchTimeline(id: unselected.id),
            unselectedTimelineBeforeMove,
            "Moving a selected subset must not create movement history for an unselected resident.",
            file: file,
            line: line
        )

        let movedPastureRepository = fixture.makePastureRepository()
        let northResidentsAfterMove = try movedPastureRepository.fetchResidentAnimals(pastureID: north.id)
        let southResidentsAfterMove = try movedPastureRepository.fetchResidentAnimals(pastureID: south.id)
        XCTAssertTrue(
            northResidentsAfterMove.contains { $0.id == unselected.id },
            "An unselected animal must remain in the source pasture resident lookup.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            southResidentsAfterMove.contains { $0.id == unselected.id },
            "An unselected animal must not appear in the destination pasture resident lookup.",
            file: file,
            line: line
        )

        try movedRepository.move(ids: selectedIDs, toPastureID: nil)

        let unassignedRepository = fixture.makeAnimalRepository()
        let unselectedAfterUnassignment = try XCTUnwrap(
            unassignedRepository.fetchAnimalDetail(id: unselected.id),
            "Unassigning a selected subset must not alter an unselected pasture resident.",
            file: file,
            line: line
        )
        XCTAssertEqual(unselectedAfterUnassignment.pastureID, north.id, file: file, line: line)
        XCTAssertEqual(unselectedAfterUnassignment.pastureName, north.name, file: file, line: line)
        XCTAssertEqual(
            try unassignedRepository.fetchTimeline(id: unselected.id),
            unselectedTimelineBeforeMove,
            "Nil-destination movement must not create history for an unselected resident.",
            file: file,
            line: line
        )

        let unassignedPastureRepository = fixture.makePastureRepository()
        let northResidentsAfterUnassignment = try unassignedPastureRepository.fetchResidentAnimals(pastureID: north.id)
        let southResidentsAfterUnassignment = try unassignedPastureRepository.fetchResidentAnimals(pastureID: south.id)
        XCTAssertTrue(
            northResidentsAfterUnassignment.contains { $0.id == unselected.id },
            "An unselected animal must remain in the source pasture after other animals are unassigned.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            southResidentsAfterUnassignment.contains { $0.id == unselected.id },
            "An unselected animal must remain absent from the destination pasture after the selected batch is unassigned.",
            file: file,
            line: line
        )
    }

    private static func subsetMovementAnimalInput(
        name: String,
        tagNumber: String,
        birthDate: Date,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: birthDate,
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

    private static func subsetContractDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
