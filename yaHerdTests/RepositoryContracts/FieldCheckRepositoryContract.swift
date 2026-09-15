import XCTest
@testable import yaHerd

/// Permanent persistence-neutral behavioral contract for `FieldCheckRepository` implementations.
///
/// During Phase 0 the current SwiftData repository is only a characterization runner for behavior
/// it already implements. Production Core Data repositories should run these same assertions
/// unchanged. The contract intentionally works through Domain repositories and snapshots only.
@MainActor
struct FieldCheckRepositoryContractFixture {
    let makeFieldCheckRepository: () -> any FieldCheckRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makePastureRepository: () -> any PastureRepository
    let makeTagColorRepository: () -> any TagColorRepository
}

@MainActor
enum FieldCheckRepositoryContract {
    static func assertSessionCreationAndReadProjections(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try makePasture(named: "Contract North", using: fixture)
        let colorID = try makeColor(named: "Contract Emerald", prefix: "CE", using: fixture)
        let dam = try makeAnimal(
            name: "Contract Dam",
            tagNumber: "D10",
            tagColorID: colorID,
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let calf = try makeAnimal(
            name: "Contract Calf",
            tagNumber: "C10",
            tagColorID: colorID,
            sex: .female,
            pastureID: pasture.id,
            damID: dam.id,
            using: fixture
        )
        let archived = try makeAnimal(
            name: "Archived Contract Animal",
            tagNumber: "A10",
            tagColorID: colorID,
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        try fixture.makeAnimalRepository().archive(ids: [archived.id])

        let startedAt = date(year: 2026, month: 1, day: 10, hour: 8)
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: startedAt,
                notes: "  Initial contract notes  "
            )
        )
        let initial = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let initialCheckIDs = Set(initial.animalChecks.map(\.id))

        let reloadedRepository = fixture.makeFieldCheckRepository()
        let detail = try XCTUnwrap(
            reloadedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.id, sessionID, file: file, line: line)
        XCTAssertEqual(detail.startedAt, startedAt, file: file, line: line)
        XCTAssertNil(detail.completedAt, file: file, line: line)
        XCTAssertEqual(detail.notes, "Initial contract notes", file: file, line: line)
        XCTAssertEqual(detail.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(detail.pastureName, "Contract North", file: file, line: line)
        XCTAssertFalse(detail.isPastureArchived, file: file, line: line)
        XCTAssertNil(detail.pastureArchivedAt, file: file, line: line)
        XCTAssertEqual(detail.expectedHeadCountSnapshot, 2, file: file, line: line)
        XCTAssertEqual(Set(detail.animalChecks.map(\.id)), initialCheckIDs, "Roster application IDs must survive reload.", file: file, line: line)
        XCTAssertEqual(Set(detail.animalChecks.compactMap(\.animalID)), Set([dam.id, calf.id]), file: file, line: line)
        XCTAssertFalse(detail.animalChecks.contains { $0.animalID == archived.id }, "Archived animals must not enter the expected roster.", file: file, line: line)

        let damCheck = try XCTUnwrap(detail.animalChecks.first { $0.animalID == dam.id }, file: file, line: line)
        XCTAssertEqual(damCheck.displayTagNumber, "D10", file: file, line: line)
        XCTAssertEqual(damCheck.displayTagColorID, colorID, file: file, line: line)
        XCTAssertEqual(damCheck.animalName, "Contract Dam", file: file, line: line)
        XCTAssertEqual(damCheck.animalSex, .female, file: file, line: line)
        XCTAssertTrue(damCheck.wasExpectedAtStart, file: file, line: line)
        XCTAssertFalse(damCheck.wasCounted, file: file, line: line)
        XCTAssertFalse(damCheck.isMissing, file: file, line: line)

        let calfCheck = try XCTUnwrap(detail.animalChecks.first { $0.animalID == calf.id }, file: file, line: line)
        XCTAssertEqual(calfCheck.displayTagNumber, "C10", file: file, line: line)
        XCTAssertEqual(calfCheck.displayTagColorID, colorID, file: file, line: line)
        XCTAssertEqual(calfCheck.damDisplayTagNumber, "D10", file: file, line: line)
        XCTAssertEqual(calfCheck.damDisplayTagColorID, colorID, file: file, line: line)
        XCTAssertTrue(calfCheck.wasExpectedAtStart, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.startedAt, detail.startedAt, file: file, line: line)
        XCTAssertEqual(summary.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(summary.pastureName, detail.pastureName, file: file, line: line)
        XCTAssertEqual(summary.expectedHeadCountSnapshot, detail.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(Set(summary.animalChecks.map(\.id)), Set(detail.animalChecks.map(\.id)), file: file, line: line)
        XCTAssertEqual(summary.openFindingsCount, 0, file: file, line: line)

        let laterSessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 1, day: 11, hour: 8),
                notes: "Later session"
            )
        )
        let orderedSessions = try fixture.makeFieldCheckRepository().fetchSessions()
        XCTAssertEqual(orderedSessions.first?.id, laterSessionID, "Session summaries should be newest first.", file: file, line: line)
        XCTAssertTrue(orderedSessions.contains { $0.id == sessionID }, file: file, line: line)
    }

    static func assertMutableCountsNotesAndRosterStateSurviveReload(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try makePasture(named: "Mutable North", using: fixture)
        let firstAnimal = try makeAnimal(
            name: "Mutable One",
            tagNumber: "201",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        _ = try makeAnimal(
            name: "Mutable Two",
            tagNumber: "202",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 2, day: 10, hour: 8),
                notes: "Before mutation"
            )
        )
        let created = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertEqual(created.animalChecks.count, 2, file: file, line: line)
        let firstCheck = try XCTUnwrap(created.animalChecks.first { $0.animalID == firstAnimal.id }, file: file, line: line)
        let snapshotType = firstCheck.animalType
        XCTAssertNotEqual(snapshotType, .bull, file: file, line: line)

        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [snapshotType: 1])
        try repository.updateNotes(sessionID: sessionID, notes: "  Updated durable notes  ")

        _ = try fixture.makeAnimalRepository().update(
            id: firstAnimal.id,
            input: makeAnimalInput(
                name: "Mutable One",
                tagNumber: "201",
                sex: .male,
                pastureID: pasture.id
            )
        )
        try repository.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [snapshotType: 1, .bull: 1]
        )

        let afterCountReload = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(afterCountReload.notes, "Updated durable notes", file: file, line: line)
        XCTAssertEqual(afterCountReload.quickAnimalTypeCounts[snapshotType], 1, file: file, line: line)
        XCTAssertEqual(afterCountReload.quickBullCount, 0, "Quick-count capacity must use the captured roster type, not the animal's later live type.", file: file, line: line)
        XCTAssertEqual(afterCountReload.animalChecks.first { $0.id == firstCheck.id }?.animalType, snapshotType, file: file, line: line)

        let secondCheckID = try XCTUnwrap(created.animalChecks.first { $0.id != firstCheck.id }?.id, file: file, line: line)
        try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: firstCheck.id, isCounted: true)
        try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: firstCheck.id, isMissing: true)

        let afterMissingTransition = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let firstMissing = try XCTUnwrap(
            afterMissingTransition.animalChecks.first { $0.id == firstCheck.id },
            file: file,
            line: line
        )
        XCTAssertFalse(firstMissing.wasCounted, "Marking a roster animal missing must clear its counted state.", file: file, line: line)
        XCTAssertTrue(firstMissing.isMissing, file: file, line: line)

        try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: firstCheck.id, isCounted: true)
        try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: secondCheckID, isMissing: true)

        let reloaded = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let counted = try XCTUnwrap(reloaded.animalChecks.first { $0.id == firstCheck.id }, file: file, line: line)
        let missing = try XCTUnwrap(reloaded.animalChecks.first { $0.id == secondCheckID }, file: file, line: line)
        XCTAssertTrue(counted.wasCounted, file: file, line: line)
        XCTAssertFalse(counted.isMissing, "Marking a missing roster animal counted must clear its missing state.", file: file, line: line)
        XCTAssertFalse(missing.wasCounted, file: file, line: line)
        XCTAssertTrue(missing.isMissing, file: file, line: line)
        XCTAssertEqual(reloaded.missingAnimalCount, 1, file: file, line: line)

        let summary = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.missingAnimalCount, 1, file: file, line: line)
        XCTAssertTrue(summary.animalChecks.contains { $0.id == firstCheck.id && $0.wasCounted && !$0.isMissing }, file: file, line: line)
        XCTAssertTrue(summary.animalChecks.contains { $0.id == secondCheckID && !$0.wasCounted && $0.isMissing }, file: file, line: line)
    }

    static func assertTrackedAnimalAdditionPersistsRosterAndDestination(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let destination = try makePasture(named: "Tracked Destination", using: fixture)
        let source = try makePasture(named: "Tracked Source", using: fixture)
        _ = try makeAnimal(
            name: "Expected Animal",
            tagNumber: "301",
            sex: .female,
            pastureID: destination.id,
            using: fixture
        )
        let tracked = try makeAnimal(
            name: "Tracked Animal",
            tagNumber: "399",
            sex: .male,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: destination.id,
                startedAt: date(year: 2026, month: 3, day: 10, hour: 8),
                notes: "Tracked animal contract"
            )
        )
        let checkedAt = date(year: 2026, month: 3, day: 10, hour: 9)
        try repository.addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: tracked.id,
            checkedAt: checkedAt
        )

        let reloaded = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.expectedHeadCountSnapshot, 2, file: file, line: line)
        XCTAssertEqual(reloaded.animalChecks.count, 2, file: file, line: line)
        let trackedCheck = try XCTUnwrap(reloaded.animalChecks.first { $0.animalID == tracked.id }, file: file, line: line)
        XCTAssertFalse(trackedCheck.wasExpectedAtStart, file: file, line: line)
        XCTAssertTrue(trackedCheck.wasCounted, file: file, line: line)
        XCTAssertFalse(trackedCheck.isMissing, file: file, line: line)
        XCTAssertEqual(trackedCheck.displayTagNumber, "399", file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        let movedAnimal = try XCTUnwrap(animalRepository.fetchAnimalDetail(id: tracked.id), file: file, line: line)
        XCTAssertEqual(movedAnimal.pastureID, destination.id, file: file, line: line)
        XCTAssertEqual(movedAnimal.pastureName, destination.name, file: file, line: line)
        XCTAssertTrue(
            try animalRepository.fetchTimeline(id: tracked.id).contains {
                isMovementEvent($0, from: source.name, to: destination.name)
            },
            "Adding an out-of-pasture tracked animal must preserve the resulting movement history.",
            file: file,
            line: line
        )

        try repository.addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: tracked.id,
            checkedAt: date(year: 2026, month: 3, day: 10, hour: 10)
        )
        let afterRepeat = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(afterRepeat.expectedHeadCountSnapshot, 2, "Rechecking an existing tracked animal must not duplicate the roster or head-count snapshot.", file: file, line: line)
        XCTAssertEqual(afterRepeat.animalChecks.filter { $0.animalID == tracked.id }.count, 1, file: file, line: line)
        XCTAssertEqual(afterRepeat.animalChecks.first { $0.animalID == tracked.id }?.id, trackedCheck.id, file: file, line: line)
    }

    static func assertFindingLifecycleAndOpenFindingReader(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try makePasture(named: "Finding North", using: fixture)
        let animal = try makeAnimal(
            name: "Finding Animal",
            tagNumber: "401",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let reassignedAnimal = try makeAnimal(
            name: "Reassigned Finding Animal",
            tagNumber: "402",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 4, day: 10, hour: 8),
                notes: "Finding lifecycle"
            )
        )
        let originalDate = date(year: 2026, month: 4, day: 10, hour: 9)
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: originalDate,
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "  Not at the waterer  ",
                animalID: animal.id
            )
        )

        let afterAdd = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let finding = try XCTUnwrap(afterAdd.findings.first, file: file, line: line)
        XCTAssertEqual(finding.recordedAt, originalDate, file: file, line: line)
        XCTAssertEqual(finding.type, .missingAnimal, file: file, line: line)
        XCTAssertEqual(finding.severity, .warning, file: file, line: line)
        XCTAssertEqual(finding.status, .open, file: file, line: line)
        XCTAssertEqual(finding.note, "Not at the waterer", file: file, line: line)
        XCTAssertEqual(finding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(finding.animalDisplayTagNumber, "401", file: file, line: line)
        XCTAssertEqual(finding.pastureName, "Finding North", file: file, line: line)
        XCTAssertEqual(finding.sessionID, sessionID, file: file, line: line)
        XCTAssertTrue(afterAdd.animalChecks.first { $0.animalID == animal.id }?.isMissing == true, "An open missing-animal finding must synchronize the roster missing state.", file: file, line: line)
        XCTAssertFalse(afterAdd.animalChecks.first { $0.animalID == reassignedAnimal.id }?.isMissing == true, file: file, line: line)

        let reassignedDate = date(year: 2026, month: 4, day: 10, hour: 10)
        try repository.updateFinding(
            sessionID: sessionID,
            findingID: finding.id,
            input: FieldCheckFindingInput(
                recordedAt: reassignedDate,
                type: .missingAnimal,
                severity: .critical,
                status: .monitoring,
                note: "  Reassigned missing animal  ",
                animalID: reassignedAnimal.id
            )
        )
        let afterReassignment = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let reassignedFinding = try XCTUnwrap(
            afterReassignment.findings.first { $0.id == finding.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reassignedFinding.id, finding.id, "Finding application UUID must survive reassignment.", file: file, line: line)
        XCTAssertEqual(reassignedFinding.animalID, reassignedAnimal.id, file: file, line: line)
        XCTAssertEqual(reassignedFinding.animalDisplayTagNumber, "402", file: file, line: line)
        XCTAssertFalse(
            afterReassignment.animalChecks.first { $0.animalID == animal.id }?.isMissing == true,
            "Reassigning the only unresolved missing finding must clear the previous roster animal's missing state.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            afterReassignment.animalChecks.first { $0.animalID == reassignedAnimal.id }?.isMissing == true,
            "Reassigning an unresolved missing finding must mark the newly linked roster animal missing.",
            file: file,
            line: line
        )

        let updatedDate = date(year: 2026, month: 4, day: 10, hour: 11)
        try repository.updateFinding(
            sessionID: sessionID,
            findingID: finding.id,
            input: FieldCheckFindingInput(
                recordedAt: updatedDate,
                type: .limping,
                severity: .critical,
                status: .monitoring,
                note: "  Rear leg  ",
                animalID: reassignedAnimal.id
            )
        )
        let afterUpdate = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let updated = try XCTUnwrap(afterUpdate.findings.first { $0.id == finding.id }, file: file, line: line)
        XCTAssertEqual(updated.id, finding.id, "Finding application UUID must survive updates.", file: file, line: line)
        XCTAssertEqual(updated.recordedAt, updatedDate, file: file, line: line)
        XCTAssertEqual(updated.type, .limping, file: file, line: line)
        XCTAssertEqual(updated.severity, .critical, file: file, line: line)
        XCTAssertEqual(updated.status, .monitoring, file: file, line: line)
        XCTAssertEqual(updated.note, "Rear leg", file: file, line: line)
        XCTAssertEqual(updated.animalID, reassignedAnimal.id, file: file, line: line)
        XCTAssertFalse(afterUpdate.animalChecks.first { $0.animalID == reassignedAnimal.id }?.isMissing == true, "Changing the only open missing-animal finding to another type must clear synchronized missing state.", file: file, line: line)

        let pastureFindingDate = date(year: 2026, month: 4, day: 10, hour: 12)
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: pastureFindingDate,
                type: .fenceIssue,
                severity: .warning,
                status: .open,
                note: "North fence",
                animalID: nil
            )
        )
        let openReader = fixture.makeFieldCheckRepository()
        let openFindings = try openReader.fetchOpenFindings(limit: 0)
        XCTAssertEqual(openFindings.filter { $0.sessionID == sessionID }.count, 2, file: file, line: line)
        let limited = try openReader.fetchOpenFindings(limit: 1)
        XCTAssertEqual(limited.count, 1, file: file, line: line)
        XCTAssertEqual(limited.first?.recordedAt, pastureFindingDate, "Open findings should be returned newest first before applying the limit.", file: file, line: line)

        try repository.updateFindingStatus(sessionID: sessionID, findingID: finding.id, status: .resolved)
        let afterResolveRepository = fixture.makeFieldCheckRepository()
        XCTAssertFalse(
            try afterResolveRepository.fetchOpenFindings(limit: 0).contains { $0.id == finding.id },
            file: file,
            line: line
        )
        let summary = try XCTUnwrap(
            afterResolveRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.openFindingsCount, 1, file: file, line: line)

        let remainingFinding = try XCTUnwrap(
            try afterResolveRepository.fetchSessionDetail(id: sessionID)?.findings.first { $0.id != finding.id },
            file: file,
            line: line
        )
        try repository.deleteFinding(sessionID: sessionID, findingID: remainingFinding.id)
        let afterDelete = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertFalse(afterDelete.findings.contains { $0.id == remainingFinding.id }, file: file, line: line)
        XCTAssertTrue(afterDelete.findings.contains { $0.id == finding.id && $0.status == .resolved }, file: file, line: line)
    }

    static func assertHistoricalSnapshotsSurviveLiveRecordChanges(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let originalColorID = try makeColor(named: "Snapshot Amber", prefix: "SA", using: fixture)
        let replacementColorID = try makeColor(named: "Snapshot Blue", prefix: "SB", using: fixture)
        let pasture = try makePasture(named: "Snapshot North", using: fixture)
        let dam = try makeAnimal(
            name: "Snapshot Dam",
            tagNumber: "D50",
            tagColorID: originalColorID,
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let calf = try makeAnimal(
            name: "Snapshot Calf",
            tagNumber: "C50",
            tagColorID: originalColorID,
            sex: .female,
            pastureID: pasture.id,
            damID: dam.id,
            using: fixture
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 5, day: 10, hour: 8),
                notes: "Snapshot contract"
            )
        )
        let before = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let calfBefore = try XCTUnwrap(before.animalChecks.first { $0.animalID == calf.id }, file: file, line: line)
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: date(year: 2026, month: 5, day: 10, hour: 9),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Snapshot finding",
                animalID: calf.id
            )
        )

        _ = try fixture.makePastureRepository().update(
            id: pasture.id,
            input: PastureInput(name: "Snapshot South", acreage: 20, usableAcreage: 18, targetAcresPerHead: 1.5)
        )
        _ = try fixture.makeAnimalRepository().update(
            id: dam.id,
            input: makeAnimalInput(
                name: "Changed Dam",
                tagNumber: "D99",
                tagColorID: replacementColorID,
                sex: .female,
                pastureID: pasture.id
            )
        )
        _ = try fixture.makeAnimalRepository().update(
            id: calf.id,
            input: makeAnimalInput(
                name: "Changed Calf",
                tagNumber: "C99",
                tagColorID: replacementColorID,
                sex: .male,
                pastureID: pasture.id,
                damID: dam.id
            )
        )

        let reloaded = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.pastureName, "Snapshot North", file: file, line: line)
        XCTAssertEqual(reloaded.pastureID, pasture.id, file: file, line: line)
        let calfAfter = try XCTUnwrap(reloaded.animalChecks.first { $0.id == calfBefore.id }, file: file, line: line)
        XCTAssertEqual(calfAfter.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(calfAfter.displayTagNumber, "C50", file: file, line: line)
        XCTAssertEqual(calfAfter.displayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(calfAfter.damDisplayTagNumber, "D50", file: file, line: line)
        XCTAssertEqual(calfAfter.damDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(calfAfter.animalName, "Snapshot Calf", file: file, line: line)
        XCTAssertEqual(calfAfter.animalSex, .female, file: file, line: line)
        XCTAssertEqual(calfAfter.animalType, calfBefore.animalType, file: file, line: line)

        let finding = try XCTUnwrap(reloaded.findings.first, file: file, line: line)
        XCTAssertEqual(finding.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(finding.animalDisplayTagNumber, "C50", file: file, line: line)
        XCTAssertEqual(finding.animalDisplayTagColorID, originalColorID, file: file, line: line)
        XCTAssertEqual(finding.pastureName, "Snapshot North", file: file, line: line)
    }

    static func assertCompletionReopenAndEditLocking(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try makePasture(named: "Completion North", using: fixture)
        let animal = try makeAnimal(
            name: "Completion Animal",
            tagNumber: "601",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 6, day: 10, hour: 8),
                notes: "Completion notes"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: date(year: 2026, month: 6, day: 10, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Completion finding",
                animalID: animal.id
            )
        )
        let beforeCompletion = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let findingID = try XCTUnwrap(beforeCompletion.findings.first?.id, file: file, line: line)
        let animalCheckID = try XCTUnwrap(beforeCompletion.animalChecks.first?.id, file: file, line: line)

        try repository.completeSession(id: sessionID)

        let completedRepository = fixture.makeFieldCheckRepository()
        let completed = try XCTUnwrap(completedRepository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let completedAt = try XCTUnwrap(completed.completedAt, file: file, line: line)
        XCTAssertEqual(completed.notes, "Completion notes", file: file, line: line)
        XCTAssertEqual(completed.findings.first?.id, findingID, file: file, line: line)
        let summary = try XCTUnwrap(
            completedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.completedAt, completedAt, file: file, line: line)

        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.updateNotes(sessionID: sessionID, notes: "Blocked")
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 1])
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.setAnimalCheckCounted(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isCounted: true
            )
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.setAnimalCheckMissing(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isMissing: true
            )
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: animal.id,
                checkedAt: date(year: 2026, month: 6, day: 10, hour: 10)
            )
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: date(year: 2026, month: 6, day: 10, hour: 11),
                    type: .waterIssue,
                    severity: .warning,
                    status: .open,
                    note: "Blocked finding",
                    animalID: nil
                )
            )
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.updateFinding(
                sessionID: sessionID,
                findingID: findingID,
                input: FieldCheckFindingInput(
                    recordedAt: date(year: 2026, month: 6, day: 10, hour: 12),
                    type: .limping,
                    severity: .warning,
                    status: .monitoring,
                    note: "Blocked update",
                    animalID: animal.id
                )
            )
        }
        assertThrowsRepositoryError(.sessionCompleted, file: file, line: line) {
            try completedRepository.deleteFinding(sessionID: sessionID, findingID: findingID)
        }

        try completedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingID,
            status: .resolved
        )
        let statusUpdated = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(statusUpdated.completedAt, file: file, line: line)
        XCTAssertEqual(
            statusUpdated.findings.first { $0.id == findingID }?.status,
            .resolved,
            "Finding status remains intentionally editable after session completion.",
            file: file,
            line: line
        )

        try completedRepository.reopenSession(id: sessionID)
        let reopenedRepository = fixture.makeFieldCheckRepository()
        let reopened = try XCTUnwrap(reopenedRepository.fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertNil(reopened.completedAt, file: file, line: line)
        XCTAssertEqual(reopened.id, sessionID, file: file, line: line)
        XCTAssertEqual(reopened.findings.first { $0.id == findingID }?.status, .resolved, file: file, line: line)

        try reopenedRepository.updateNotes(sessionID: sessionID, notes: "Reopened notes")
        XCTAssertEqual(
            try fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID)?.notes,
            "Reopened notes",
            file: file,
            line: line
        )
    }

    static func assertMissingRecordErrors(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeFieldCheckRepository()
        let missingSessionID = UUID()
        XCTAssertNil(try repository.fetchSessionDetail(id: missingSessionID), file: file, line: line)

        assertThrowsRepositoryError(.pastureNotFound, file: file, line: line) {
            _ = try repository.createSession(
                input: FieldCheckSessionStartInput(
                    pastureID: UUID(),
                    startedAt: date(year: 2026, month: 7, day: 10, hour: 8),
                    notes: "Missing pasture"
                )
            )
        }
        assertThrowsRepositoryError(.sessionNotFound, file: file, line: line) {
            try repository.updateNotes(sessionID: missingSessionID, notes: "Missing")
        }

        let pasture = try makePasture(named: "Error North", using: fixture)
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: date(year: 2026, month: 7, day: 10, hour: 9),
                notes: "Error contract"
            )
        )
        assertThrowsRepositoryError(.animalNotFound, file: file, line: line) {
            try repository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: UUID(),
                checkedAt: date(year: 2026, month: 7, day: 10, hour: 10)
            )
        }

        let archivedAnimal = try makeAnimal(
            name: "Archived Error Animal",
            tagNumber: "701",
            sex: .female,
            pastureID: pasture.id,
            using: fixture
        )
        try fixture.makeAnimalRepository().archive(ids: [archivedAnimal.id])
        assertThrowsRepositoryError(.animalNotActive, file: file, line: line) {
            try repository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: archivedAnimal.id,
                checkedAt: date(year: 2026, month: 7, day: 10, hour: 11)
            )
        }
    }

    private static func makePasture(
        named name: String,
        using fixture: FieldCheckRepositoryContractFixture
    ) throws -> PastureDetailSnapshot {
        try fixture.makePastureRepository().create(
            input: PastureInput(
                name: name,
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
    }

    private static func makeColor(
        named name: String,
        prefix: String,
        using fixture: FieldCheckRepositoryContractFixture
    ) throws -> UUID {
        let color = TagColorSnapshot(
            id: UUID(),
            name: name,
            prefix: prefix,
            rgba: RGBAColor(r: 0.25, g: 0.5, b: 0.75)
        )
        try fixture.makeTagColorRepository().upsert(color)
        return color.id
    }

    private static func makeAnimal(
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        sex: Sex,
        pastureID: UUID,
        damID: UUID? = nil,
        using fixture: FieldCheckRepositoryContractFixture
    ) throws -> AnimalDetailSnapshot {
        try fixture.makeAnimalRepository().create(
            input: makeAnimalInput(
                name: name,
                tagNumber: tagNumber,
                tagColorID: tagColorID,
                sex: sex,
                pastureID: pastureID,
                damID: damID
            )
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        sex: Sex,
        pastureID: UUID,
        damID: UUID? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: sex,
            birthDate: date(year: 2020, month: 1, day: 1),
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

    private static func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private static func isMovementEvent(
        _ event: AnimalTimelineEvent,
        from sourcePasture: String,
        to destinationPasture: String
    ) -> Bool {
        guard case .movement = event.type else { return false }
        return event.title == "Pasture Movement"
            && event.details == "\(sourcePasture) → \(destinationPasture)"
    }

    private static func assertThrowsRepositoryError(
        _ expected: FieldCheckRepositoryError,
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let repositoryError = error as? FieldCheckRepositoryError else {
                XCTFail("Expected FieldCheckRepositoryError but received \(error).", file: file, line: line)
                return
            }
            XCTAssertTrue(
                errorsMatch(repositoryError, expected),
                "Expected \(expected) but received \(repositoryError).",
                file: file,
                line: line
            )
        }
    }

    private static func errorsMatch(
        _ lhs: FieldCheckRepositoryError,
        _ rhs: FieldCheckRepositoryError
    ) -> Bool {
        switch (lhs, rhs) {
        case (.sessionNotFound, .sessionNotFound),
             (.animalCheckNotFound, .animalCheckNotFound),
             (.findingNotFound, .findingNotFound),
             (.pastureNotFound, .pastureNotFound),
             (.animalNotFound, .animalNotFound),
             (.animalNotActive, .animalNotActive),
             (.sessionCompleted, .sessionCompleted):
            true
        default:
            false
        }
    }
}
