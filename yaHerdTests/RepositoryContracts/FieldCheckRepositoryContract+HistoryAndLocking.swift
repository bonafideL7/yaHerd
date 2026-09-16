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

        let reloadedRepository = fixture.makeFieldCheckRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchSessionDetail(id: sessionID),
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
        XCTAssertTrue(
            checkAfterDelete.needsAttention,
            "An unresolved linked finding must keep the orphaned historical roster check flagged after live-animal deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded.flaggedAnimalCount,
            1,
            "Session detail must continue counting the orphaned roster check as flagged while its unresolved finding remains.",
            file: file,
            line: line
        )

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

        let summaryAfterDelete = try XCTUnwrap(
            reloadedRepository.fetchSessions().first { $0.id == sessionID },
            "Hard-deleting a live animal must not remove its Field Check history from session summaries.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterDelete.openFindingsCount, 1, file: file, line: line)
        let summaryCheck = try XCTUnwrap(
            summaryAfterDelete.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Session summaries must retain the orphaned roster projection after live-animal deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaryCheck.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(summaryCheck.displayTagNumber, checkBeforeDelete.displayTagNumber, file: file, line: line)
        XCTAssertEqual(summaryCheck.displayTagColorID, checkBeforeDelete.displayTagColorID, file: file, line: line)
        XCTAssertTrue(
            summaryCheck.needsAttention,
            "Session summaries must preserve attention for orphaned roster history while an unresolved linked finding remains.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            summaryAfterDelete.flaggedAnimalCount,
            1,
            "Session summaries must continue reporting the orphaned historical roster check as flagged.",
            file: file,
            line: line
        )

        let openFindingAfterDelete = try XCTUnwrap(
            reloadedRepository.fetchOpenFindings(limit: 0).first { $0.id == findingBeforeDelete.id },
            "Open-finding projections must retain findings whose linked live animal was hard-deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(openFindingAfterDelete.sessionID, sessionID, file: file, line: line)
        XCTAssertEqual(openFindingAfterDelete.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(openFindingAfterDelete.animalDisplayTagNumber, findingBeforeDelete.animalDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(openFindingAfterDelete.animalDisplayTagColorID, findingBeforeDelete.animalDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(openFindingAfterDelete.pastureName, findingBeforeDelete.pastureName, file: file, line: line)
        XCTAssertEqual(openFindingAfterDelete.note, findingBeforeDelete.note, file: file, line: line)

        try reloadedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingBeforeDelete.id,
            status: .resolved
        )

        let resolvedRepository = fixture.makeFieldCheckRepository()
        let resolvedDetail = try XCTUnwrap(
            resolvedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let resolvedCheck = try XCTUnwrap(
            resolvedDetail.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Resolving an orphaned finding must not remove its historical roster row.",
            file: file,
            line: line
        )
        XCTAssertEqual(resolvedCheck.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(resolvedCheck.displayTagNumber, checkBeforeDelete.displayTagNumber, file: file, line: line)
        XCTAssertFalse(resolvedCheck.needsAttention, file: file, line: line)
        XCTAssertEqual(resolvedDetail.flaggedAnimalCount, 0, file: file, line: line)
        XCTAssertEqual(
            resolvedDetail.findings.first { $0.id == findingBeforeDelete.id }?.status,
            .resolved,
            file: file,
            line: line
        )

        let resolvedSummary = try XCTUnwrap(
            resolvedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let resolvedSummaryCheck = try XCTUnwrap(
            resolvedSummary.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Resolving an orphaned finding must preserve its summary roster row.",
            file: file,
            line: line
        )
        XCTAssertFalse(resolvedSummaryCheck.needsAttention, file: file, line: line)
        XCTAssertEqual(resolvedSummary.flaggedAnimalCount, 0, file: file, line: line)
        XCTAssertEqual(resolvedSummary.openFindingsCount, 0, file: file, line: line)
        XCTAssertFalse(
            try resolvedRepository.fetchOpenFindings(limit: 0).contains { $0.id == findingBeforeDelete.id },
            "A resolved orphaned finding must leave the open-finding projection.",
            file: file,
            line: line
        )
    }

    static func assertCompletedSessionMissingFindingStatusSynchronization(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Completed Missing Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Completed Missing Animal",
                tagNumber: "CM801",
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

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_781_000_000),
                notes: "Completed missing synchronization"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_781_003_600),
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Missing before completion",
                animalID: animal.id
            )
        )

        let beforeCompletion = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkID = try XCTUnwrap(
            beforeCompletion.animalChecks.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        let findingID = try XCTUnwrap(
            beforeCompletion.findings.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        XCTAssertTrue(beforeCompletion.animalChecks.first { $0.id == checkID }?.isMissing == true, file: file, line: line)
        XCTAssertEqual(beforeCompletion.missingAnimalCount, 1, file: file, line: line)

        try repository.completeSession(id: sessionID)
        let completedRepository = fixture.makeFieldCheckRepository()
        let completed = try XCTUnwrap(
            completedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(completed.completedAt, file: file, line: line)
        XCTAssertTrue(completed.animalChecks.first { $0.id == checkID }?.isMissing == true, file: file, line: line)
        XCTAssertEqual(completed.missingAnimalCount, 1, file: file, line: line)

        try completedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingID,
            status: .resolved
        )

        let resolvedRepository = fixture.makeFieldCheckRepository()
        let resolved = try XCTUnwrap(
            resolvedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(resolved.completedAt, "Resolving a finding must not reopen its completed session.", file: file, line: line)
        let resolvedCheck = try XCTUnwrap(
            resolved.animalChecks.first { $0.id == checkID },
            file: file,
            line: line
        )
        XCTAssertFalse(resolvedCheck.isMissing, "Resolving the completed session's final missing finding must clear synchronized missing state.", file: file, line: line)
        XCTAssertEqual(resolved.missingAnimalCount, 0, file: file, line: line)
        XCTAssertEqual(resolved.findings.first { $0.id == findingID }?.status, .resolved, file: file, line: line)
        XCTAssertFalse(
            try resolvedRepository.fetchOpenFindings(limit: 0).contains { $0.id == findingID },
            file: file,
            line: line
        )

        let resolvedSummary = try XCTUnwrap(
            resolvedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertNotNil(resolvedSummary.completedAt, file: file, line: line)
        let resolvedSummaryCheck = try XCTUnwrap(
            resolvedSummary.animalChecks.first { $0.id == checkID },
            file: file,
            line: line
        )
        XCTAssertFalse(resolvedSummaryCheck.isMissing, file: file, line: line)
        XCTAssertEqual(resolvedSummary.missingAnimalCount, 0, file: file, line: line)

        try resolvedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingID,
            status: .monitoring
        )
        let monitoringRepository = fixture.makeFieldCheckRepository()
        let monitoring = try XCTUnwrap(
            monitoringRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(monitoring.completedAt, "Reopening a finding must not reopen its completed session.", file: file, line: line)
        XCTAssertTrue(monitoring.animalChecks.first { $0.id == checkID }?.isMissing == true, file: file, line: line)
        XCTAssertEqual(monitoring.missingAnimalCount, 1, file: file, line: line)
        XCTAssertTrue(
            try monitoringRepository.fetchOpenFindings(limit: 0).contains { $0.id == findingID && $0.status == .monitoring },
            file: file,
            line: line
        )
        let monitoringSummary = try XCTUnwrap(
            monitoringRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertTrue(monitoringSummary.animalChecks.first { $0.id == checkID }?.isMissing == true, file: file, line: line)
        XCTAssertEqual(monitoringSummary.missingAnimalCount, 1, file: file, line: line)
    }

    static func assertUntaggedFindingNameSnapshotSurvivesLiveRename(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Untagged Snapshot Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Original Untagged Name",
                tagNumber: "",
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

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_782_000_000),
                notes: "Untagged finding snapshot"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_782_003_600),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Untagged historical display",
                animalID: animal.id
            )
        )
        let beforeRename = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingID = try XCTUnwrap(
            beforeRename.findings.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        XCTAssertEqual(
            beforeRename.findings.first { $0.id == findingID }?.animalDisplayTagNumber,
            "Original Untagged Name",
            "An untagged finding must display its captured animal-name fallback.",
            file: file,
            line: line
        )

        _ = try fixture.makeAnimalRepository().update(
            id: animal.id,
            input: AnimalInput(
                name: "Changed Live Untagged Name",
                tagNumber: "",
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

        let snapshotRepository = fixture.makeFieldCheckRepository()
        let reloaded = try XCTUnwrap(
            snapshotRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let reloadedFinding = try XCTUnwrap(
            reloaded.findings.first { $0.id == findingID },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(
            reloadedFinding.animalDisplayTagNumber,
            "Original Untagged Name",
            "Historical detail must use the persisted name snapshot when the captured tag is empty.",
            file: file,
            line: line
        )

        let openFinding = try XCTUnwrap(
            try snapshotRepository.fetchOpenFindings(limit: 0).first { $0.id == findingID },
            file: file,
            line: line
        )
        XCTAssertEqual(openFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(
            openFinding.animalDisplayTagNumber,
            "Original Untagged Name",
            "Open-finding history must not join the renamed live animal when the historical tag is empty.",
            file: file,
            line: line
        )
    }
}
