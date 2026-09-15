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

        let reloaded = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
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

        let findingAfterDelete = try XCTUnwrap(
            reloaded.findings.first { $0.id == findingBeforeDelete.id },
            "Hard-deleting a live animal must not cascade-delete its Field Check finding history.",
            file: file,
            line: line
        )
        XCTAssertEqual(findingAfterDelete.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.animalDisplayTagNumber, findingBeforeDelete.animalDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.animalDisplayTagColorID, findingBeforeDelete.animalDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.animalName, findingBeforeDelete.animalName, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.pastureName, findingBeforeDelete.pastureName, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.sessionID, sessionID, file: file, line: line)
        XCTAssertEqual(findingAfterDelete.note, "Snapshot must survive hard delete", file: file, line: line)
    }

    static func assertCompletedSessionRejectsAllDataMutations(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Completed Locking Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Completed Locking Animal",
                tagNumber: "CL801",
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
                startedAt: Date(timeIntervalSince1970: 1_780_100_000),
                notes: "Completed locking contract"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_780_103_600),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Existing finding",
                animalID: animal.id
            )
        )
        let beforeCompletion = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let animalCheckID = try XCTUnwrap(
            beforeCompletion.animalChecks.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        let findingID = try XCTUnwrap(
            beforeCompletion.findings.first?.id,
            file: file,
            line: line
        )

        try repository.completeSession(id: sessionID)
        let completedRepository = fixture.makeFieldCheckRepository()

        func assertSessionCompleted(_ operation: () throws -> Void) {
            XCTAssertThrowsError(try operation(), file: file, line: line) { error in
                guard let repositoryError = error as? FieldCheckRepositoryError else {
                    XCTFail("Expected FieldCheckRepositoryError.sessionCompleted but received \(error).", file: file, line: line)
                    return
                }
                guard case .sessionCompleted = repositoryError else {
                    XCTFail("Expected FieldCheckRepositoryError.sessionCompleted but received \(repositoryError).", file: file, line: line)
                    return
                }
            }
        }

        assertSessionCompleted {
            try completedRepository.updateNotes(sessionID: sessionID, notes: "Blocked")
        }
        assertSessionCompleted {
            try completedRepository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 1])
        }
        assertSessionCompleted {
            try completedRepository.setAnimalCheckCounted(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isCounted: true
            )
        }
        assertSessionCompleted {
            try completedRepository.setAnimalCheckMissing(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isMissing: true
            )
        }
        assertSessionCompleted {
            try completedRepository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: animal.id,
                checkedAt: Date(timeIntervalSince1970: 1_780_107_200)
            )
        }
        assertSessionCompleted {
            try completedRepository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: Date(timeIntervalSince1970: 1_780_110_800),
                    type: .waterIssue,
                    severity: .warning,
                    status: .open,
                    note: "Blocked add",
                    animalID: nil
                )
            )
        }
        assertSessionCompleted {
            try completedRepository.updateFinding(
                sessionID: sessionID,
                findingID: findingID,
                input: FieldCheckFindingInput(
                    recordedAt: Date(timeIntervalSince1970: 1_780_114_400),
                    type: .limping,
                    severity: .warning,
                    status: .monitoring,
                    note: "Blocked update",
                    animalID: animal.id
                )
            )
        }
        assertSessionCompleted {
            try completedRepository.deleteFinding(sessionID: sessionID, findingID: findingID)
        }

        try completedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingID,
            status: .resolved
        )
        let afterStatusUpdate = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(afterStatusUpdate.completedAt, file: file, line: line)
        XCTAssertEqual(
            afterStatusUpdate.findings.first { $0.id == findingID }?.status,
            .resolved,
            "Finding status remains intentionally editable after session completion.",
            file: file,
            line: line
        )
    }
}
