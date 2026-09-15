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
        let firstPastureSecondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow North 2",
                tagNumber: "706",
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

        let soldAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Sold Cow",
                tagNumber: "703",
                pastureID: firstPasture.id,
                status: .sold,
                saleDate: Date(timeIntervalSince1970: 1_779_000_000)
            )
        )
        let deadAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Dead Cow",
                tagNumber: "704",
                pastureID: secondPasture.id,
                status: .dead,
                deathDate: Date(timeIntervalSince1970: 1_779_100_000)
            )
        )
        let archivedAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Archived Cow",
                tagNumber: "705",
                pastureID: secondPasture.id
            )
        )
        try animalRepository.archive(ids: [archivedAnimal.id])

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

        try fieldCheckRepository.completeSession(id: firstSessionID)
        let completedFirstSession = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let firstCompletedAt = try XCTUnwrap(
            completedFirstSession.completedAt,
            "The completed-session fixture must persist its completion timestamp before deletion.",
            file: file,
            line: line
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
            animalID: firstPastureSecondAnimal.id,
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
        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: soldAnimal.id,
            expectedStatus: .sold,
            expectedArchived: false,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: deadAnimal.id,
            expectedStatus: .dead,
            expectedArchived: false,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: archivedAnimal.id,
            expectedStatus: .active,
            expectedArchived: true,
            repository: reloadedAnimals,
            file: file,
            line: line
        )

        let reloadedFieldChecks = fixture.makeFieldCheckRepository()
        try assertArchivedFieldCheckSession(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            expectedCompletedAt: firstCompletedAt,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            expectedAnimals: [
                (id: firstAnimal.id, tagNumber: "701"),
                (id: firstPastureSecondAnimal.id, tagNumber: "706")
            ],
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSession(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            expectedCompletedAt: nil,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            expectedAnimals: [(id: secondAnimal.id, tagNumber: "702")],
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )

        let sessionSummaries = try reloadedFieldChecks.fetchSessions()
        try assertArchivedFieldCheckSummary(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            expectedCompletedAt: firstCompletedAt,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            archivedAt: archivedAt,
            expectedHeadCount: 2,
            summaries: sessionSummaries,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSummary(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            expectedCompletedAt: nil,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            archivedAt: archivedAt,
            expectedHeadCount: 1,
            summaries: sessionSummaries,
            file: file,
            line: line
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID,
        status: AnimalStatus = .active,
        saleDate: Date? = nil,
        deathDate: Date? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
            status: status,
            pastureID: pastureID,
            sireID: nil,
            damID: nil,
            distinguishingFeatures: [],
            saleDate: saleDate,
            salePrice: status == .sold ? 1_250 : nil,
            reasonSold: status == .sold ? "Deletion workflow contract" : nil,
            deathDate: deathDate,
            causeOfDeath: status == .dead ? "Deletion workflow contract" : nil,
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

    private static func assertInactiveAnimalSurvivesPastureDeletion(
        animalID: UUID,
        expectedStatus: AnimalStatus,
        expectedArchived: Bool,
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let animal = try XCTUnwrap(
            repository.fetchAnimalDetail(id: animalID),
            "Deleting a pasture must not delete sold, dead, or archived animals that still reference it.",
            file: file,
            line: line
        )
        XCTAssertEqual(animal.status, expectedStatus, file: file, line: line)
        XCTAssertEqual(animal.isArchived, expectedArchived, file: file, line: line)
        XCTAssertNil(animal.pastureID, file: file, line: line)
        XCTAssertNil(animal.pastureName, file: file, line: line)
    }

    private static func assertArchivedFieldCheckSession(
        sessionID: UUID,
        startedAt: Date,
        expectedCompletedAt: Date?,
        pastureID: UUID,
        pastureName: String,
        expectedAnimals: [(id: UUID, tagNumber: String)],
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
        XCTAssertEqual(archivedSession.completedAt, expectedCompletedAt, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(archivedSession.animalChecks.count, expectedAnimals.count, file: file, line: line)

        let actualAnimalIDs = archivedSession.animalChecks.compactMap(\.animalID)
        XCTAssertEqual(actualAnimalIDs.count, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(
            Set(actualAnimalIDs),
            Set(expectedAnimals.map { $0.id }),
            "Deleting a pasture must preserve every Field Check animal snapshot, not only the first.",
            file: file,
            line: line
        )

        for expectedAnimal in expectedAnimals {
            let check = try XCTUnwrap(
                archivedSession.animalChecks.first { $0.animalID == expectedAnimal.id },
                file: file,
                line: line
            )
            XCTAssertEqual(check.displayTagNumber, expectedAnimal.tagNumber, file: file, line: line)
        }
    }

    private static func assertArchivedFieldCheckSummary(
        sessionID: UUID,
        startedAt: Date,
        expectedCompletedAt: Date?,
        pastureID: UUID,
        pastureName: String,
        archivedAt: Date,
        expectedHeadCount: Int,
        summaries: [FieldCheckSessionSummary],
        file: StaticString,
        line: UInt
    ) throws {
        let summary = try XCTUnwrap(
            summaries.first { $0.id == sessionID },
            "Archived field-check sessions must remain visible through the list reader.",
            file: file,
            line: line
        )
        XCTAssertEqual(summary.startedAt, startedAt, file: file, line: line)
        XCTAssertEqual(summary.completedAt, expectedCompletedAt, file: file, line: line)
        XCTAssertEqual(summary.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(summary.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(summary.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(summary.isPastureArchived, file: file, line: line)
        XCTAssertEqual(summary.expectedHeadCountSnapshot, expectedHeadCount, file: file, line: line)
    }
}
