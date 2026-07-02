import XCTest
import SwiftData
@testable import yaHerd

final class SwiftDataFieldCheckRepositoryQuickCountTests: XCTestCase {
    func testCountingAnimalNormalizesStoredQuickCountForSameAnimalType() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 3, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 3])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheckID = try XCTUnwrap(initialDetail.animalChecks.first?.id)

        try repository.setAnimalCheckCounted(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isCounted: true
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(updatedDetail.quickHeiferCount, 2)
        XCTAssertEqual(updatedDetail.quickAnimalTypeCounts[.heifer], 2)
        XCTAssertEqual(updatedDetail.individuallyVerifiedCount, 1)
        XCTAssertEqual(updatedDetail.totalSeen, 3)
        XCTAssertEqual(updatedDetail.countVariance, 0)
    }

    func testMarkingAnimalMissingNormalizesStoredQuickCountForSameAnimalType() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 3, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 3])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheckID = try XCTUnwrap(initialDetail.animalChecks.first?.id)

        try repository.setAnimalCheckMissing(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isMissing: true
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(updatedDetail.quickHeiferCount, 2)
        XCTAssertEqual(updatedDetail.quickAnimalTypeCounts[.heifer], 2)
        XCTAssertEqual(updatedDetail.individuallyVerifiedCount, 0)
        XCTAssertEqual(updatedDetail.totalSeen, 2)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 1)
    }

    func testMissingAnimalFindingMarksRosterEntryMissingAndNormalizesQuickCount() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 3, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 3])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .missingAnimal,
                severity: .critical,
                status: .open,
                note: "Gate was open.",
                animalID: animalID
            )
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedAnimalCheck = try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertTrue(updatedAnimalCheck.isMissing)
        XCTAssertTrue(updatedAnimalCheck.needsAttention)
        XCTAssertFalse(updatedAnimalCheck.wasCounted)
        XCTAssertEqual(updatedDetail.quickHeiferCount, 2)
        XCTAssertEqual(updatedDetail.quickAnimalTypeCounts[.heifer], 2)
        XCTAssertEqual(updatedDetail.totalSeen, 2)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 1)
    }

    func testResolvingLastUnresolvedFindingClearsNeedsAttention() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Watch.",
                animalID: animalID
            )
        )

        let detailWithOpenFinding = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detailWithOpenFinding.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(detailWithOpenFinding.animalChecks.first { $0.id == animalCheck.id }).needsAttention)

        try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)

        let resolvedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(try XCTUnwrap(resolvedDetail.animalChecks.first { $0.id == animalCheck.id }).needsAttention)
        XCTAssertEqual(resolvedDetail.flaggedAnimalCount, 0)
    }

    func testMonitoringFindingKeepsNeedsAttention() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .limping,
                severity: .warning,
                status: .monitoring,
                note: "Watch.",
                animalID: animalID
            )
        )

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertTrue(try XCTUnwrap(detail.animalChecks.first { $0.id == animalCheck.id }).needsAttention)
        XCTAssertEqual(detail.flaggedAnimalCount, 1)
    }

    func testDeletingLastUnresolvedFindingClearsNeedsAttention() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .limping,
                severity: .warning,
                status: .open,
                note: "Watch.",
                animalID: animalID
            )
        )

        let detailWithFinding = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detailWithFinding.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(detailWithFinding.animalChecks.first { $0.id == animalCheck.id }).needsAttention)

        try repository.deleteFinding(sessionID: sessionID, findingID: findingID)

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id }).needsAttention)
        XCTAssertEqual(updatedDetail.flaggedAnimalCount, 0)
    }

    func testDeletingOneFindingKeepsNeedsAttentionWhenAnotherUnresolvedFindingRemains() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .limping,
                severity: .warning,
                status: .open,
                note: "Watch.",
                animalID: animalID
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 20),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Watch.",
                animalID: animalID
            )
        )

        let detailWithFindings = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let firstFindingID = try XCTUnwrap(detailWithFindings.findings.first?.id)

        try repository.deleteFinding(sessionID: sessionID, findingID: firstFindingID)

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertTrue(try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id }).needsAttention)
        XCTAssertEqual(updatedDetail.flaggedAnimalCount, 1)
    }



    func testCompletedSessionRejectsFieldCheckEditsUntilReopened() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 2, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Watch.",
                animalID: animalID
            )
        )

        let detailWithFinding = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detailWithFinding.findings.first?.id)

        try repository.completeSession(id: sessionID)

        assertSessionCompletedThrown {
            try repository.updateNotes(sessionID: sessionID, notes: "Should not save")
        }
        assertSessionCompletedThrown {
            try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 1])
        }
        assertSessionCompletedThrown {
            try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheck.id, isCounted: true)
        }
        assertSessionCompletedThrown {
            try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheck.id, isMissing: true)
        }
        assertSessionCompletedThrown {
            try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)
        }
        assertSessionCompletedThrown {
            try repository.deleteFinding(sessionID: sessionID, findingID: findingID)
        }
        assertSessionCompletedThrown {
            try repository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: Date(timeIntervalSince1970: 20),
                    type: .limping,
                    severity: .warning,
                    status: .open,
                    note: "",
                    animalID: animalID
                )
            )
        }

        let lockedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(lockedDetail.notes, "")
        XCTAssertEqual(lockedDetail.quickAnimalTypeCounts.values.reduce(0, +), 0)
        XCTAssertFalse(try XCTUnwrap(lockedDetail.animalChecks.first { $0.id == animalCheck.id }).wasCounted)
        XCTAssertEqual(lockedDetail.findings.count, 1)
        XCTAssertEqual(try XCTUnwrap(lockedDetail.findings.first).status, .open)

        try repository.reopenSession(id: sessionID)
        try repository.updateNotes(sessionID: sessionID, notes: "Unlocked")

        let reopenedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(reopenedDetail.isCompleted)
        XCTAssertEqual(reopenedDetail.notes, "Unlocked")
    }

    private func assertSessionCompletedThrown(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ action: () throws -> Void
    ) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            guard case FieldCheckRepositoryError.sessionCompleted = error else {
                return XCTFail("Expected sessionCompleted, got \(error)", file: file, line: line)
            }
        }
    }

    private func makePastureWithAnimals(
        context: ModelContext,
        animalCount: Int,
        sex: Sex
    ) throws -> Pasture {
        let pasture = Pasture(name: "North")
        context.insert(pasture)

        for index in 1...animalCount {
            let animal = Animal(
                name: "Heifer \(index)",
                tagNumber: "\(index)",
                birthDate: Date(timeIntervalSince1970: 0),
                status: .active,
                pasture: pasture,
                sex: sex
            )
            animal.pasture = pasture
            context.insert(animal)
        }

        try context.save()
        return pasture
    }
}
