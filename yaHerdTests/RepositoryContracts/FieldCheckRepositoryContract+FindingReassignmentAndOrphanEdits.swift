import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    static func assertFindingReassignmentUsesSessionRosterSnapshotAfterLiveRecordChanges(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let originalColor = TagColorSnapshot(
            id: UUID(),
            name: "Reassignment Snapshot Amber",
            prefix: "RSA",
            rgba: RGBAColor(r: 0.3, g: 0.4, b: 0.5)
        )
        let replacementColor = TagColorSnapshot(
            id: UUID(),
            name: "Reassignment Snapshot Blue",
            prefix: "RSB",
            rgba: RGBAColor(r: 0.6, g: 0.4, b: 0.2)
        )
        try fixture.makeTagColorRepository().upsert(originalColor)
        try fixture.makeTagColorRepository().upsert(replacementColor)

        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Reassignment Snapshot North",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let sourceAnimal = try fixture.makeAnimalRepository().create(
            input: findingEdgeAnimalInput(
                name: "Reassignment Source",
                tagNumber: "RS701",
                tagColorID: originalColor.id,
                pastureID: pasture.id
            )
        )
        let targetAnimal = try fixture.makeAnimalRepository().create(
            input: findingEdgeAnimalInput(
                name: "Reassignment Target",
                tagNumber: "RS702",
                tagColorID: originalColor.id,
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: findingEdgeDate(year: 2026, month: 9, day: 29, hour: 8),
                notes: "Finding reassignment snapshot contract"
            )
        )
        let initialDetail = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let targetCheckBeforeLiveChange = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == targetAnimal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(targetCheckBeforeLiveChange.displayTagNumber, "RS702", file: file, line: line)
        XCTAssertEqual(targetCheckBeforeLiveChange.displayTagColorID, originalColor.id, file: file, line: line)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: findingEdgeDate(year: 2026, month: 9, day: 29, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Finding before reassignment",
                animalID: sourceAnimal.id
            )
        )
        let beforeReassignment = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingID = try XCTUnwrap(
            beforeReassignment.findings.first { $0.note == "Finding before reassignment" }?.id,
            file: file,
            line: line
        )
        let sourceCheckBeforeReassignment = try XCTUnwrap(
            beforeReassignment.animalChecks.first { $0.animalID == sourceAnimal.id },
            file: file,
            line: line
        )
        let targetCheckBeforeReassignment = try XCTUnwrap(
            beforeReassignment.animalChecks.first { $0.id == targetCheckBeforeLiveChange.id },
            file: file,
            line: line
        )
        XCTAssertTrue(sourceCheckBeforeReassignment.needsAttention, file: file, line: line)
        XCTAssertFalse(targetCheckBeforeReassignment.needsAttention, file: file, line: line)
        XCTAssertEqual(beforeReassignment.flaggedAnimalCount, 1, file: file, line: line)

        _ = try fixture.makePastureRepository().update(
            id: pasture.id,
            input: PastureInput(
                name: "Reassignment Snapshot South",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: targetAnimal.id,
            input: findingEdgeAnimalInput(
                name: "Changed Reassignment Target",
                tagNumber: "RS999",
                tagColorID: replacementColor.id,
                pastureID: pasture.id
            )
        )

        let reassignmentWriter = fixture.makeFieldCheckRepository()
        try reassignmentWriter.updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: FieldCheckFindingInput(
                recordedAt: findingEdgeDate(year: 2026, month: 9, day: 29, hour: 10),
                type: .pinkEye,
                severity: .warning,
                status: .monitoring,
                note: "Finding reassigned after live changes",
                animalID: targetAnimal.id
            )
        )

        let reloadedRepository = fixture.makeFieldCheckRepository()
        let reloadedDetail = try XCTUnwrap(
            reloadedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let reassignedFinding = try XCTUnwrap(
            reloadedDetail.findings.first { $0.id == findingID },
            file: file,
            line: line
        )
        XCTAssertEqual(reassignedFinding.id, findingID, file: file, line: line)
        XCTAssertEqual(reassignedFinding.animalID, targetAnimal.id, file: file, line: line)
        XCTAssertEqual(
            reassignedFinding.animalDisplayTagNumber,
            targetCheckBeforeLiveChange.displayTagNumber,
            "Reassigning a finding must use the target animal's session-time roster tag rather than its changed live tag.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reassignedFinding.animalDisplayTagColorID,
            targetCheckBeforeLiveChange.displayTagColorID,
            "Reassigning a finding must use the target animal's session-time roster color rather than its changed live color.",
            file: file,
            line: line
        )
        XCTAssertEqual(reassignedFinding.pastureName, "Reassignment Snapshot North", file: file, line: line)
        XCTAssertEqual(reassignedFinding.note, "Finding reassigned after live changes", file: file, line: line)

        let retainedSourceCheck = try XCTUnwrap(
            reloadedDetail.animalChecks.first { $0.id == sourceCheckBeforeReassignment.id },
            "Reassigning a finding must retain the source animal's roster row.",
            file: file,
            line: line
        )
        let retainedTargetCheck = try XCTUnwrap(
            reloadedDetail.animalChecks.first { $0.id == targetCheckBeforeLiveChange.id },
            file: file,
            line: line
        )
        XCTAssertEqual(retainedSourceCheck.animalID, sourceAnimal.id, file: file, line: line)
        XCTAssertFalse(
            retainedSourceCheck.needsAttention,
            "Reassigning the source animal's only unresolved finding must clear its attention state.",
            file: file,
            line: line
        )
        XCTAssertEqual(retainedTargetCheck.animalID, targetAnimal.id, file: file, line: line)
        XCTAssertEqual(retainedTargetCheck.displayTagNumber, "RS702", file: file, line: line)
        XCTAssertEqual(retainedTargetCheck.displayTagColorID, originalColor.id, file: file, line: line)
        XCTAssertTrue(
            retainedTargetCheck.needsAttention,
            "Reassigning an unresolved finding must move attention to the target roster animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedDetail.flaggedAnimalCount, 1, file: file, line: line)

        let reloadedSummary = try XCTUnwrap(
            reloadedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let summarySourceCheck = try XCTUnwrap(
            reloadedSummary.animalChecks.first { $0.id == sourceCheckBeforeReassignment.id },
            "The session summary must retain the source roster row after finding reassignment.",
            file: file,
            line: line
        )
        let summaryTargetCheck = try XCTUnwrap(
            reloadedSummary.animalChecks.first { $0.id == targetCheckBeforeLiveChange.id },
            "The session summary must retain the target roster row after finding reassignment.",
            file: file,
            line: line
        )
        XCTAssertEqual(summarySourceCheck.animalID, sourceAnimal.id, file: file, line: line)
        XCTAssertFalse(
            summarySourceCheck.needsAttention,
            "Session summaries must clear attention from the source animal after its final unresolved finding is reassigned.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaryTargetCheck.animalID, targetAnimal.id, file: file, line: line)
        XCTAssertTrue(
            summaryTargetCheck.needsAttention,
            "Session summaries must move attention to the target animal after finding reassignment.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedSummary.flaggedAnimalCount, 1, file: file, line: line)

        let openFinding = try XCTUnwrap(
            try reloadedRepository.fetchOpenFindings(limit: 0).first { $0.id == findingID },
            file: file,
            line: line
        )
        XCTAssertEqual(openFinding.animalID, targetAnimal.id, file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagNumber, "RS702", file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagColorID, originalColor.id, file: file, line: line)
        XCTAssertEqual(openFinding.pastureName, "Reassignment Snapshot North", file: file, line: line)
    }

    static func assertOrphanedFindingFullEditPreservesSnapshotsAndRosterSynchronization(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let color = TagColorSnapshot(
            id: UUID(),
            name: "Orphan Edit Amber",
            prefix: "OEA",
            rgba: RGBAColor(r: 0.5, g: 0.4, b: 0.3)
        )
        try fixture.makeTagColorRepository().upsert(color)

        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Orphan Edit Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: findingEdgeAnimalInput(
                name: "Orphan Edit Animal",
                tagNumber: "OE801",
                tagColorID: color.id,
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: findingEdgeDate(year: 2026, month: 9, day: 30, hour: 8),
                notes: "Orphan full edit contract"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 1])
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: findingEdgeDate(year: 2026, month: 9, day: 30, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Finding before orphan edit",
                animalID: animal.id
            )
        )

        let beforeDelete = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkBeforeDelete = try XCTUnwrap(
            beforeDelete.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        let findingBeforeDelete = try XCTUnwrap(
            beforeDelete.findings.first { $0.note == "Finding before orphan edit" },
            file: file,
            line: line
        )
        XCTAssertEqual(checkBeforeDelete.displayTagNumber, "OE801", file: file, line: line)
        XCTAssertEqual(checkBeforeDelete.displayTagColorID, color.id, file: file, line: line)
        XCTAssertFalse(checkBeforeDelete.isMissing, file: file, line: line)
        XCTAssertEqual(beforeDelete.quickCowCount, 1, file: file, line: line)

        try fixture.makeAnimalRepository().delete(ids: [animal.id])
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            "The fixture must remove the live animal before exercising the full finding edit.",
            file: file,
            line: line
        )

        let orphanedWriter = fixture.makeFieldCheckRepository()
        let orphanedBeforeEdit = try XCTUnwrap(
            orphanedWriter.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(
            orphanedBeforeEdit.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Hard deletion must retain the historical roster row needed to edit the orphan-linked finding.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            orphanedBeforeEdit.findings.first { $0.id == findingBeforeDelete.id },
            "Hard deletion must retain the historical finding row before the full edit.",
            file: file,
            line: line
        )

        try orphanedWriter.updateFinding(
            sessionID: sessionID,
            findingID: findingBeforeDelete.id,
            input: FieldCheckFindingInput(
                recordedAt: findingEdgeDate(year: 2026, month: 9, day: 30, hour: 10),
                type: .missingAnimal,
                severity: .critical,
                status: .monitoring,
                note: "Edited after live animal deletion",
                animalID: animal.id
            )
        )

        let reloadedRepository = fixture.makeFieldCheckRepository()
        let reloadedDetail = try XCTUnwrap(
            reloadedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let editedFinding = try XCTUnwrap(
            reloadedDetail.findings.first { $0.id == findingBeforeDelete.id },
            file: file,
            line: line
        )
        let editedCheck = try XCTUnwrap(
            reloadedDetail.animalChecks.first { $0.id == checkBeforeDelete.id },
            file: file,
            line: line
        )

        XCTAssertEqual(editedFinding.id, findingBeforeDelete.id, file: file, line: line)
        XCTAssertEqual(editedFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(editedFinding.type, .missingAnimal, file: file, line: line)
        XCTAssertEqual(editedFinding.severity, .critical, file: file, line: line)
        XCTAssertEqual(editedFinding.status, .monitoring, file: file, line: line)
        XCTAssertEqual(editedFinding.note, "Edited after live animal deletion", file: file, line: line)
        XCTAssertEqual(
            editedFinding.animalDisplayTagNumber,
            findingBeforeDelete.animalDisplayTagNumber,
            "A full edit after live-animal deletion must preserve the retained roster tag snapshot.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            editedFinding.animalDisplayTagColorID,
            findingBeforeDelete.animalDisplayTagColorID,
            "A full edit after live-animal deletion must preserve the retained roster color snapshot.",
            file: file,
            line: line
        )
        XCTAssertEqual(editedFinding.pastureName, findingBeforeDelete.pastureName, file: file, line: line)

        XCTAssertEqual(editedCheck.id, checkBeforeDelete.id, file: file, line: line)
        XCTAssertEqual(editedCheck.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(editedCheck.displayTagNumber, checkBeforeDelete.displayTagNumber, file: file, line: line)
        XCTAssertEqual(editedCheck.displayTagColorID, checkBeforeDelete.displayTagColorID, file: file, line: line)
        XCTAssertTrue(
            editedCheck.isMissing,
            "Changing an orphan-linked finding to unresolved missing must synchronize the retained roster row by snapshot identity.",
            file: file,
            line: line
        )
        XCTAssertFalse(editedCheck.wasCounted, file: file, line: line)
        XCTAssertEqual(reloadedDetail.missingAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(reloadedDetail.quickCowCount, 0, file: file, line: line)
        XCTAssertEqual(reloadedDetail.quickAnimalTypeCounts[.cow], 0, file: file, line: line)

        let openFinding = try XCTUnwrap(
            try reloadedRepository.fetchOpenFindings(limit: 0).first { $0.id == findingBeforeDelete.id },
            file: file,
            line: line
        )
        XCTAssertEqual(openFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagNumber, checkBeforeDelete.displayTagNumber, file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagColorID, checkBeforeDelete.displayTagColorID, file: file, line: line)
        XCTAssertEqual(openFinding.pastureName, findingBeforeDelete.pastureName, file: file, line: line)
        XCTAssertEqual(openFinding.status, .monitoring, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let summaryCheck = try XCTUnwrap(
            summary.animalChecks.first { $0.id == checkBeforeDelete.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(summaryCheck.isMissing, file: file, line: line)
        XCTAssertEqual(summary.missingAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(summary.quickCowCount, 0, file: file, line: line)
        XCTAssertEqual(summary.openFindingsCount, 1, file: file, line: line)
    }

    private static func findingEdgeAnimalInput(
        name: String,
        tagNumber: String,
        tagColorID: UUID?,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: .female,
            birthDate: findingEdgeDate(year: 2020, month: 1, day: 1),
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

    private static func findingEdgeDate(
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