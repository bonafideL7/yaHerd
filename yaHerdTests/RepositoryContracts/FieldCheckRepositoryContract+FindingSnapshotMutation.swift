import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    /// Verifies finding mutations continue to source display data from the session/roster snapshots
    /// even when the linked live pasture and animals have changed since the Field Check began.
    static func assertFindingWritesPreserveHistoricalSnapshotsAfterLiveRecordChanges(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let originalColorID = try mutationSnapshotColor(
            named: "Mutation Snapshot Amber",
            prefix: "MSA",
            using: fixture
        )
        let replacementColorID = try mutationSnapshotColor(
            named: "Mutation Snapshot Blue",
            prefix: "MSB",
            using: fixture
        )
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Mutation Snapshot North",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let dam = try fixture.makeAnimalRepository().create(
            input: mutationSnapshotAnimalInput(
                name: "Mutation Snapshot Dam",
                tagNumber: "D70",
                tagColorID: originalColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )
        let calf = try fixture.makeAnimalRepository().create(
            input: mutationSnapshotAnimalInput(
                name: "Mutation Snapshot Calf",
                tagNumber: "C70",
                tagColorID: originalColorID,
                sex: .female,
                pastureID: pasture.id,
                damID: dam.id
            )
        )
        let untagged = try fixture.makeAnimalRepository().create(
            input: mutationSnapshotAnimalInput(
                name: "Mutation Snapshot Untagged",
                tagNumber: "",
                tagColorID: originalColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: mutationSnapshotDate(year: 2026, month: 9, day: 27, hour: 8),
                notes: "Finding mutation snapshot contract"
            )
        )
        let initialDetail = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let calfCheckID = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == calf.id }?.id,
            file: file,
            line: line
        )
        let untaggedCheckID = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == untagged.id }?.id,
            file: file,
            line: line
        )

        _ = try fixture.makePastureRepository().update(
            id: pasture.id,
            input: PastureInput(
                name: "Mutation Snapshot South",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: dam.id,
            input: mutationSnapshotAnimalInput(
                name: "Changed Mutation Dam",
                tagNumber: "D99",
                tagColorID: replacementColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: calf.id,
            input: mutationSnapshotAnimalInput(
                name: "Changed Mutation Calf",
                tagNumber: "C99",
                tagColorID: replacementColorID,
                sex: .male,
                pastureID: pasture.id,
                damID: dam.id
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: untagged.id,
            input: mutationSnapshotAnimalInput(
                name: "Changed Mutation Untagged",
                tagNumber: "U99",
                tagColorID: replacementColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )

        let postChangeWriter = fixture.makeFieldCheckRepository()
        try postChangeWriter.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: mutationSnapshotDate(year: 2026, month: 9, day: 27, hour: 9),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Post-change tagged finding",
                animalID: calf.id
            )
        )
        try postChangeWriter.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: mutationSnapshotDate(year: 2026, month: 9, day: 27, hour: 10),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Post-change untagged finding",
                animalID: untagged.id
            )
        )

        let afterAddReader = fixture.makeFieldCheckRepository()
        let afterAddDetail = try XCTUnwrap(
            afterAddReader.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let taggedFinding = try XCTUnwrap(
            afterAddDetail.findings.first { $0.note == "Post-change tagged finding" },
            file: file,
            line: line
        )
        let untaggedFinding = try XCTUnwrap(
            afterAddDetail.findings.first { $0.note == "Post-change untagged finding" },
            file: file,
            line: line
        )
        XCTAssertEqual(taggedFinding.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(taggedFinding.animalDisplayTagNumber, "C70", file: file, line: line)
        XCTAssertEqual(taggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(taggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)
        XCTAssertEqual(untaggedFinding.animalID, untagged.id, file: file, line: line)
        XCTAssertEqual(
            untaggedFinding.animalDisplayTagNumber,
            "Mutation Snapshot Untagged",
            "A finding added after the live animal gains a tag must still use the original untagged roster name fallback.",
            file: file,
            line: line
        )
        XCTAssertEqual(untaggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(untaggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)

        let calfCheckAfterAdd = try XCTUnwrap(
            afterAddDetail.animalChecks.first { $0.id == calfCheckID },
            file: file,
            line: line
        )
        XCTAssertEqual(calfCheckAfterAdd.displayTagNumber, "C70", file: file, line: line)
        XCTAssertEqual(calfCheckAfterAdd.displayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(calfCheckAfterAdd.damDisplayTagNumber, "D70", file: file, line: line)
        XCTAssertEqual(calfCheckAfterAdd.damDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(calfCheckAfterAdd.animalName, "Mutation Snapshot Calf", file: file, line: line)
        let untaggedCheckAfterAdd = try XCTUnwrap(
            afterAddDetail.animalChecks.first { $0.id == untaggedCheckID },
            file: file,
            line: line
        )
        XCTAssertEqual(untaggedCheckAfterAdd.displayTagNumber, "", file: file, line: line)
        XCTAssertEqual(untaggedCheckAfterAdd.animalName, "Mutation Snapshot Untagged", file: file, line: line)

        _ = try fixture.makePastureRepository().update(
            id: pasture.id,
            input: PastureInput(
                name: "Mutation Snapshot West",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: calf.id,
            input: mutationSnapshotAnimalInput(
                name: "Changed Mutation Calf Again",
                tagNumber: "C100",
                tagColorID: replacementColorID,
                sex: .male,
                pastureID: pasture.id,
                damID: dam.id
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: untagged.id,
            input: mutationSnapshotAnimalInput(
                name: "Changed Mutation Untagged Again",
                tagNumber: "U100",
                tagColorID: replacementColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )

        let postSecondChangeWriter = fixture.makeFieldCheckRepository()
        try postSecondChangeWriter.updateFinding(
            sessionID: sessionID,
            findingID: taggedFinding.id,
            input: FieldCheckFindingInput(
                recordedAt: mutationSnapshotDate(year: 2026, month: 9, day: 27, hour: 11),
                type: .limping,
                severity: .critical,
                status: .monitoring,
                note: "Updated post-change tagged finding",
                animalID: calf.id
            )
        )
        try postSecondChangeWriter.updateFinding(
            sessionID: sessionID,
            findingID: untaggedFinding.id,
            input: FieldCheckFindingInput(
                recordedAt: mutationSnapshotDate(year: 2026, month: 9, day: 27, hour: 12),
                type: .generalObservation,
                severity: .warning,
                status: .monitoring,
                note: "Updated post-change untagged finding",
                animalID: untagged.id
            )
        )

        let afterUpdateReader = fixture.makeFieldCheckRepository()
        let afterUpdateDetail = try XCTUnwrap(
            afterUpdateReader.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let updatedTaggedFinding = try XCTUnwrap(
            afterUpdateDetail.findings.first { $0.id == taggedFinding.id },
            file: file,
            line: line
        )
        let updatedUntaggedFinding = try XCTUnwrap(
            afterUpdateDetail.findings.first { $0.id == untaggedFinding.id },
            file: file,
            line: line
        )
        XCTAssertEqual(updatedTaggedFinding.note, "Updated post-change tagged finding", file: file, line: line)
        XCTAssertEqual(updatedTaggedFinding.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(updatedTaggedFinding.animalDisplayTagNumber, "C70", file: file, line: line)
        XCTAssertEqual(updatedTaggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(updatedTaggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)
        XCTAssertEqual(updatedUntaggedFinding.note, "Updated post-change untagged finding", file: file, line: line)
        XCTAssertEqual(updatedUntaggedFinding.animalID, untagged.id, file: file, line: line)
        XCTAssertEqual(updatedUntaggedFinding.animalDisplayTagNumber, "Mutation Snapshot Untagged", file: file, line: line)
        XCTAssertEqual(updatedUntaggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(updatedUntaggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)

        let openFindings = try afterUpdateReader.fetchOpenFindings(limit: 0)
        let openTaggedFinding = try XCTUnwrap(
            openFindings.first { $0.id == taggedFinding.id },
            file: file,
            line: line
        )
        let openUntaggedFinding = try XCTUnwrap(
            openFindings.first { $0.id == untaggedFinding.id },
            file: file,
            line: line
        )
        XCTAssertEqual(openTaggedFinding.animalDisplayTagNumber, "C70", file: file, line: line)
        XCTAssertEqual(openTaggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(openTaggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)
        XCTAssertEqual(openUntaggedFinding.animalDisplayTagNumber, "Mutation Snapshot Untagged", file: file, line: line)
        XCTAssertEqual(openUntaggedFinding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(openUntaggedFinding.pastureName, "Mutation Snapshot North", file: file, line: line)
    }

    private static func mutationSnapshotColor(
        named name: String,
        prefix: String,
        using fixture: FieldCheckRepositoryContractFixture
    ) throws -> UUID {
        let color = TagColorSnapshot(
            id: UUID(),
            name: name,
            prefix: prefix,
            rgba: RGBAColor(r: 0.2, g: 0.4, b: 0.6)
        )
        try fixture.makeTagColorRepository().upsert(color)
        return color.id
    }

    private static func mutationSnapshotAnimalInput(
        name: String,
        tagNumber: String,
        tagColorID: UUID?,
        sex: Sex,
        pastureID: UUID,
        damID: UUID? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: sex,
            birthDate: mutationSnapshotDate(year: 2020, month: 1, day: 1),
            status: .active,
            pastureID: pastureID,
            sireID: nil,
            damID: damID,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }

    private static func mutationSnapshotDate(
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
