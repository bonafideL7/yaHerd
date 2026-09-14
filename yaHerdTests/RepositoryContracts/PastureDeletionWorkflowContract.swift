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
        let pasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        let animalRepository = fixture.makeAnimalRepository()
        let animal = try animalRepository.create(
            input: AnimalInput(
                name: "Deletion Contract Cow",
                tagNumber: "701",
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

        let startedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let archivedAt = Date(timeIntervalSince1970: 1_780_086_400)
        let fieldCheckRepository = fixture.makeFieldCheckRepository()
        let sessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: startedAt,
                notes: "Deletion workflow contract"
            )
        )

        try fixture.deletePastures([pasture.id], archivedAt)

        XCTAssertNil(
            try fixture.makePastureRepository().fetchPastureDetail(id: pasture.id),
            "The deleted pasture must no longer be available as current pasture data.",
            file: file,
            line: line
        )

        let reloadedAnimalRepository = fixture.makeAnimalRepository()
        let reloadedAnimal = try XCTUnwrap(
            reloadedAnimalRepository.fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertNil(reloadedAnimal.pastureID, file: file, line: line)
        XCTAssertNil(reloadedAnimal.pastureName, file: file, line: line)
        XCTAssertTrue(
            try reloadedAnimalRepository.fetchTimeline(id: animal.id).contains { event in
                guard case .movement = event.type else { return false }
                return event.title == "Pasture Movement"
                    && event.details == "Delete Workflow Pasture → —"
            },
            "Deleting a pasture with residents must preserve movement history from that pasture to unassigned.",
            file: file,
            line: line
        )

        let archivedSession = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(archivedSession.startedAt, startedAt, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureName, "Delete Workflow Pasture", file: file, line: line)
        XCTAssertEqual(archivedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, 1, file: file, line: line)
        XCTAssertTrue(
            archivedSession.animalChecks.contains { $0.animalID == animal.id && $0.displayTagNumber == "701" },
            "Deleting the pasture must not discard the field-check roster snapshot.",
            file: file,
            line: line
        )
    }
}
