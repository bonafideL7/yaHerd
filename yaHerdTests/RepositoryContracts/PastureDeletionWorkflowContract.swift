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
    let makeTagColorRepository: () -> any TagColorRepository
    let makeFieldCheckRepository: () -> any FieldCheckRepository
    let deletePastures: ([UUID], Date) throws -> Void
}

@MainActor
enum PastureDeletionWorkflowContract {
    private struct ExpectedAnimalCheck {
        let animalID: UUID
        let displayTagNumber: String
        let displayTagColorID: UUID?
        let damDisplayTagNumber: String?
        let damDisplayTagColorID: UUID?
        let animalName: String
        let animalSex: Sex
        let animalType: AnimalType
        let wasExpectedAtStart: Bool
        let wasCounted: Bool
        let needsAttention: Bool
        let isMissing: Bool
    }

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

        let tagColorRepository = fixture.makeTagColorRepository()
        let animalTagColor = TagColorSnapshot(
            name: "Deletion Contract Animal Color",
            prefix: "A",
            rgba: RGBAColor(r: 0.2, g: 0.6, b: 0.8)
        )
        let damTagColor = TagColorSnapshot(
            name: "Deletion Contract Dam Color",
            prefix: "D",
            rgba: RGBAColor(r: 0.8, g: 0.5, b: 0.2)
        )
        try tagColorRepository.upsert(animalTagColor)
        try tagColorRepository.upsert(damTagColor)

        let animalRepository = fixture.makeAnimalRepository()
        let dam = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Dam",
                tagNumber: "D700",
                pastureID: nil,
                tagColorID: damTagColor.id
            )
        )
        let firstAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow North",
                tagNumber: "701",
                pastureID: firstPasture.id,
                tagColorID: animalTagColor.id,
                damID: dam.id
            )
        )
        let firstPastureSecondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Bull North",
                tagNumber: "706",
                pastureID: firstPasture.id,
                sex: .male
            )
        )
        let secondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow South",
                tagNumber: "702",
                pastureID: secondPasture.id,
                tagColorID: animalTagColor.id
            )
        )
        let trackedAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Tracked Bull",
                tagNumber: "707",
                pastureID: secondPasture.id,
                sex: .male
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
        let findingRecordedAt = Date(timeIntervalSince1970: 1_780_050_000)
        let trackedAt = Date(timeIntervalSince1970: 1_780_060_000)
        let archivedAt = Date(timeIntervalSince1970: 1_780_086_400)
        let firstNotes = "Deletion workflow contract north"
        let secondNotes = "Deletion workflow contract south"
        let fieldCheckRepository = fixture.makeFieldCheckRepository()
        let firstSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: firstPasture.id,
                startedAt: firstStartedAt,
                notes: firstNotes
            )
        )
        let secondSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: secondPasture.id,
                startedAt: secondStartedAt,
                notes: secondNotes
            )
        )

        let firstSessionBeforeStateChanges = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let countedCheck = try XCTUnwrap(
            firstSessionBeforeStateChanges.animalChecks.first { $0.animalID == firstAnimal.id },
            "The first resident must be present in the Field Check roster.",
            file: file,
            line: line
        )
        let missingCheck = try XCTUnwrap(
            firstSessionBeforeStateChanges.animalChecks.first { $0.animalID == firstPastureSecondAnimal.id },
            "The second resident must be present in the Field Check roster.",
            file: file,
            line: line
        )
        try fieldCheckRepository.setAnimalCheckCounted(
            sessionID: firstSessionID,
            animalCheckID: countedCheck.id,
            isCounted: true
        )
        try fieldCheckRepository.setAnimalCheckMissing(
            sessionID: firstSessionID,
            animalCheckID: missingCheck.id,
            isMissing: true
        )
        try fieldCheckRepository.addTrackedAnimalToSession(
            sessionID: firstSessionID,
            animalID: trackedAnimal.id,
            checkedAt: trackedAt
        )
        try fieldCheckRepository.updateQuickAnimalTypeCounts(
            sessionID: secondSessionID,
            counts: [.heifer: 1]
        )

        let findingInput = FieldCheckFindingInput(
            recordedAt: findingRecordedAt,
            type: .pinkEye,
            severity: .critical,
            status: .monitoring,
            note: "Deletion workflow finding",
            animalID: secondAnimal.id
        )
        try fieldCheckRepository.addFinding(sessionID: secondSessionID, input: findingInput)

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
        try assertAnimalMovedToUnassigned(
            animalID: trackedAnimal.id,
            pastureName: "Delete Workflow North",
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
        let firstExpectedAnimals = [
            ExpectedAnimalCheck(
                animalID: firstAnimal.id,
                displayTagNumber: "701",
                displayTagColorID: animalTagColor.id,
                damDisplayTagNumber: "D700",
                damDisplayTagColorID: damTagColor.id,
                animalName: "Deletion Contract Cow North",
                animalSex: .female,
                animalType: .heifer,
                wasExpectedAtStart: true,
                wasCounted: true,
                needsAttention: false,
                isMissing: false
            ),
            ExpectedAnimalCheck(
                animalID: firstPastureSecondAnimal.id,
                displayTagNumber: "706",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Bull North",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: false,
                isMissing: true
            ),
            ExpectedAnimalCheck(
                animalID: trackedAnimal.id,
                displayTagNumber: "707",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Tracked Bull",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: false,
                wasCounted: true,
                needsAttention: false,
                isMissing: false
            )
        ]
        let secondExpectedAnimals = [
            ExpectedAnimalCheck(
                animalID: secondAnimal.id,
                displayTagNumber: "702",
                displayTagColorID: animalTagColor.id,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Cow South",
                animalSex: .female,
                animalType: .heifer,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: true,
                isMissing: false
            ),
            ExpectedAnimalCheck(
                animalID: trackedAnimal.id,
                displayTagNumber: "707",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Tracked Bull",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: false,
                isMissing: false
            )
        ]

        try assertArchivedFieldCheckSession(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            expectedCompletedAt: firstCompletedAt,
            expectedNotes: firstNotes,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            expectedAnimals: firstExpectedAnimals,
            expectedQuickCounts: [:],
            expectedFinding: nil,
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSession(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            expectedCompletedAt: nil,
            expectedNotes: secondNotes,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            expectedAnimals: secondExpectedAnimals,
            expectedQuickCounts: [.heifer: 1],
            expectedFinding: findingInput,
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
            expectedAnimals: firstExpectedAnimals,
            expectedQuickCounts: [:],
            expectedOpenFindingsCount: 0,
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
            expectedAnimals: secondExpectedAnimals,
            expectedQuickCounts: [.heifer: 1],
            expectedOpenFindingsCount: 1,
            summaries: sessionSummaries,
            file: file,
            line: line
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID?,
        tagColorID: UUID? = nil,
        sex: Sex = .female,
        damID: UUID? = nil,
        status: AnimalStatus = .active,
        saleDate: Date? = nil,
        deathDate: Date? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: sex,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
            status: status,
            pastureID: pastureID,
            sireID: nil,
            damID: damID,
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
        expectedNotes: String,
        pastureID: UUID,
        pastureName: String,
        expectedAnimals: [ExpectedAnimalCheck],
        expectedQuickCounts: [AnimalType: Int],
        expectedFinding: FieldCheckFindingInput?,
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
        XCTAssertEqual(archivedSession.notes, expectedNotes, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(archivedSession.animalChecks.count, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(archivedSession.quickCowCount, expectedQuickCounts[.cow, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickHeiferCount, expectedQuickCounts[.heifer, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickCalfCount, expectedQuickCounts[.calf, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickBullCount, expectedQuickCounts[.bull, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickSteerCount, expectedQuickCounts[.steer, default: 0], file: file, line: line)

        let actualAnimalIDs = archivedSession.animalChecks.compactMap(\.animalID)
        XCTAssertEqual(actualAnimalIDs.count, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(
            Set(actualAnimalIDs),
            Set(expectedAnimals.map(\.animalID)),
            "Deleting a pasture must preserve every Field Check animal snapshot, not only the first.",
            file: file,
            line: line
        )

        for expectedAnimal in expectedAnimals {
            let check = try XCTUnwrap(
                archivedSession.animalChecks.first { $0.animalID == expectedAnimal.animalID },
                file: file,
                line: line
            )
            assertAnimalCheck(check, matches: expectedAnimal, file: file, line: line)
        }

        if let expectedFinding {
            XCTAssertEqual(archivedSession.findings.count, 1, file: file, line: line)
            let finding = try XCTUnwrap(archivedSession.findings.first, file: file, line: line)
            XCTAssertEqual(finding.recordedAt, expectedFinding.recordedAt, file: file, line: line)
            XCTAssertEqual(finding.type, expectedFinding.type, file: file, line: line)
            XCTAssertEqual(finding.severity, expectedFinding.severity, file: file, line: line)
            XCTAssertEqual(finding.status, expectedFinding.status, file: file, line: line)
            XCTAssertEqual(finding.note, expectedFinding.note, file: file, line: line)
            XCTAssertEqual(finding.animalID, expectedFinding.animalID, file: file, line: line)
            XCTAssertEqual(finding.pastureName, pastureName, file: file, line: line)
            XCTAssertEqual(finding.sessionID, sessionID, file: file, line: line)

            if let animalID = expectedFinding.animalID,
               let expectedAnimal = expectedAnimals.first(where: { $0.animalID == animalID }) {
                XCTAssertEqual(
                    finding.animalDisplayTagNumber,
                    expectedAnimal.displayTagNumber,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    finding.animalDisplayTagColorID,
                    expectedAnimal.displayTagColorID,
                    file: file,
                    line: line
                )
            }
        } else {
            XCTAssertTrue(archivedSession.findings.isEmpty, file: file, line: line)
        }
    }

    private static func assertArchivedFieldCheckSummary(
        sessionID: UUID,
        startedAt: Date,
        expectedCompletedAt: Date?,
        pastureID: UUID,
        pastureName: String,
        archivedAt: Date,
        expectedAnimals: [ExpectedAnimalCheck],
        expectedQuickCounts: [AnimalType: Int],
        expectedOpenFindingsCount: Int,
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
        XCTAssertEqual(summary.expectedHeadCountSnapshot, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(summary.quickCowCount, expectedQuickCounts[.cow, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickHeiferCount, expectedQuickCounts[.heifer, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickCalfCount, expectedQuickCounts[.calf, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickBullCount, expectedQuickCounts[.bull, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickSteerCount, expectedQuickCounts[.steer, default: 0], file: file, line: line)
        XCTAssertEqual(summary.openFindingsCount, expectedOpenFindingsCount, file: file, line: line)
        XCTAssertEqual(summary.animalChecks.count, expectedAnimals.count, file: file, line: line)

        for expectedAnimal in expectedAnimals {
            let check = try XCTUnwrap(
                summary.animalChecks.first { $0.animalID == expectedAnimal.animalID },
                file: file,
                line: line
            )
            assertAnimalCheck(check, matches: expectedAnimal, file: file, line: line)
        }
    }

    private static func assertAnimalCheck(
        _ check: FieldCheckAnimalCheckSnapshot,
        matches expected: ExpectedAnimalCheck,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(check.animalID, expected.animalID, file: file, line: line)
        XCTAssertEqual(check.displayTagNumber, expected.displayTagNumber, file: file, line: line)
        XCTAssertEqual(check.displayTagColorID, expected.displayTagColorID, file: file, line: line)
        XCTAssertEqual(check.damDisplayTagNumber, expected.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(check.damDisplayTagColorID, expected.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(check.animalName, expected.animalName, file: file, line: line)
        XCTAssertEqual(check.animalSex, expected.animalSex, file: file, line: line)
        XCTAssertEqual(check.animalType, expected.animalType, file: file, line: line)
        XCTAssertEqual(check.wasExpectedAtStart, expected.wasExpectedAtStart, file: file, line: line)
        XCTAssertEqual(check.wasCounted, expected.wasCounted, file: file, line: line)
        XCTAssertEqual(check.needsAttention, expected.needsAttention, file: file, line: line)
        XCTAssertEqual(check.isMissing, expected.isMissing, file: file, line: line)
    }
}
