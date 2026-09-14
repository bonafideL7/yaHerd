import XCTest
@testable import yaHerd

/// Permanent behavioral contract for the user-facing pasture-deletion workflow.
///
/// This characterizes the durable outcome users rely on today without requiring the current
/// SwiftData implementation to gain the stronger atomic transaction semantics planned for Core Data.
@MainActor
struct PastureDeletionWorkflowContractFixture {
    let makePastureRepository: () -> any PastureRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makeFieldCheckRepository: () -> any FieldCheckRepository
    let deletePastures: ([UUID], Date) throws -> Void
}

@MainActor
enum PastureDeletionWorkflowContract {
    static func assertDeleteMovesResidentsAndArchivesFieldCheckHistory(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let firstPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow North",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let secondPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow South",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.75
            )
        )

        let animalRepository = fixture.makeAnimalRepository()
        let firstAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow North",
                tagNumber: "701",
                pastureID: firstPasture.id
            )
        )
        let secondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow South",
                tagNumber: "702",
                pastureID: secondPasture.id
            )
        )

        let firstStartedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let secondStartedAt = Date(timeIntervalSince1970: 1_780_043_200)
        let archivedAt = Date(timeIntervalSince1970: 1_780_086_400)
        let fieldCheckRepository = fixture.makeFieldCheckRepository()
        let firstSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: firstPasture.id,
                startedAt: firstStartedAt,
                notes: "Deletion workflow contract north"
            )
        )
        let secondSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: secondPasture.id,
                startedAt: secondStartedAt,
                notes: "Deletion workflow contract south"
            )
        )

        try fixture.deletePastures([firstPasture.id, secondPasture.id], archivedAt)

        let reloadedPastures = fixture.makePastureRepository()
        XCTAssertNil(
            try reloadedPastures.fetchPastureDetail(id: firstPasture.id),
            "Every requested pasture must be deleted, including the first item in a batch.",
            file: file,
            line: line
        )
        XCTAssertNil(
            try reloadedPastures.fetchPastureDetail(id: secondPasture.id),
            "Every requested pasture must be deleted, including later items in a batch.",
            file: file,
            line: line
        )

        let reloadedAnimals = fixture.makeAnimalRepository()
        try assertAnimalMovedToUnassigned(
            animalID: firstAnimal.id,
            pastureName: "Delete Workflow North",
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertAnimalMovedToUnassigned(
            animalID: secondAnimal.id,
            pastureName: "Delete Workflow South",
            repository: reloadedAnimals,
            file: file,
            line: line
        )

        let reloadedFieldChecks = fixture.makeFieldCheckRepository()
        try assertArchivedFieldCheckSession(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            animalID: firstAnimal.id,
            tagNumber: "701",
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSession(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            animalID: secondAnimal.id,
            tagNumber: "702",
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )
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

    private static func assertAnimalMovedToUnassigned(
        animalID: UUID,
        pastureName: String,
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let reloadedAnimal = try XCTUnwrap(
            repository.fetchAnimalDetail(id: animalID),
            file: file,
            line: line
        )
        XCTAssertNil(reloadedAnimal.pastureID, file: file, line: line)
        XCTAssertNil(reloadedAnimal.pastureName, file: file, line: line)
        XCTAssertTrue(
            try repository.fetchTimeline(id: animalID).contains { event in
                guard case .movement = event.type else { return false }
                return event.title == "Pasture Movement"
                    && event.details == "\(pastureName) → —"
            },
            "Deleting every populated pasture in a batch must preserve its resident movement history.",
            file: file,
            line: line
        )
    }

    private static func assertArchivedFieldCheckSession(
        sessionID: UUID,
        startedAt: Date,
        pastureID: UUID,
        pastureName: String,
        animalID: UUID,
        tagNumber: String,
        archivedAt: Date,
        repository: any FieldCheckRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let archivedSession = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(archivedSession.startedAt, startedAt, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, 1, file: file, line: line)
        XCTAssertTrue(
            archivedSession.animalChecks.contains {
                $0.animalID == animalID && $0.displayTagNumber == tagNumber
            },
            "Deleting every pasture in a batch must retain its field-check roster snapshot.",
            file: file,
            line: line
        )
    }
}
