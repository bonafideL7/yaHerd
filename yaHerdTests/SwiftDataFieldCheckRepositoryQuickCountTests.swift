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

    func testUpdatingNonMissingFindingDoesNotClearManualMissingStatus() throws {
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

        try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheck.id, isMissing: true)
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

        try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedAnimalCheck = try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertTrue(updatedAnimalCheck.isMissing)
        XCTAssertFalse(updatedAnimalCheck.needsAttention)
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

    func testResolvingMissingAnimalFindingClearsMissingStatusWhenNoUnresolvedMissingFindingRemains() throws {
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

        let missingDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(missingDetail.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(missingDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)
        XCTAssertEqual(missingDetail.missingAnimalCount, 1)

        try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)

        let resolvedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let resolvedAnimalCheck = try XCTUnwrap(resolvedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertFalse(resolvedAnimalCheck.isMissing)
        XCTAssertFalse(resolvedAnimalCheck.needsAttention)
        XCTAssertEqual(resolvedDetail.missingAnimalCount, 0)
        XCTAssertEqual(resolvedDetail.totalSeen, 2)
        XCTAssertEqual(resolvedDetail.remainingExpectedCount, 1)
    }

    func testResolvingOneMissingAnimalFindingKeepsMissingStatusWhenAnotherUnresolvedMissingFindingRemains() throws {
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
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Missing near gate.",
                animalID: animalID
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 20),
                type: .missingAnimal,
                severity: .critical,
                status: .open,
                note: "Still missing.",
                animalID: animalID
            )
        )

        let detailWithFindings = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let firstFindingID = try XCTUnwrap(
            detailWithFindings.findings
                .filter { $0.type == .missingAnimal }
                .sorted { $0.recordedAt < $1.recordedAt }
                .first?.id
        )

        try repository.updateFindingStatus(sessionID: sessionID, findingID: firstFindingID, status: .resolved)

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedAnimalCheck = try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertTrue(updatedAnimalCheck.isMissing)
        XCTAssertTrue(updatedAnimalCheck.needsAttention)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 1)
    }

    func testDeletingLastMissingAnimalFindingClearsMissingStatus() throws {
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
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Missing.",
                animalID: animalID
            )
        )

        let missingDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(missingDetail.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(missingDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)

        try repository.deleteFinding(sessionID: sessionID, findingID: findingID)

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 0)
    }

    func testResolvedMissingAnimalFindingDoesNotMarkRosterEntryMissing() throws {
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
                type: .missingAnimal,
                severity: .warning,
                status: .resolved,
                note: "Was missing, now accounted for.",
                animalID: animalID
            )
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 0)
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




    func testAddingTrackedAnimalFromAnotherPastureMovesAnimalAddsCheckedRosterEntryAndUpdatesExpectedCount() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let north = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)
        let south = Pasture(name: "South")
        context.insert(south)

        let movedAnimal = Animal(
            name: "Wanderer",
            tagNumber: "20",
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            pasture: south,
            sex: .female
        )
        context.insert(movedAnimal)
        try context.save()

        let checkedAt = Date(timeIntervalSince1970: 60)
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: north.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        try repository.addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: movedAnimal.publicID,
            checkedAt: checkedAt
        )

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let addedCheck = try XCTUnwrap(detail.animalChecks.first { $0.animalID == movedAnimal.publicID })
        XCTAssertEqual(detail.expectedHeadCountSnapshot, 2)
        XCTAssertEqual(detail.totalSeen, 1)
        XCTAssertEqual(detail.remainingExpectedCount, 1)
        XCTAssertTrue(addedCheck.wasCounted)
        XCTAssertFalse(addedCheck.wasExpectedAtStart)
        XCTAssertFalse(addedCheck.isMissing)
        XCTAssertEqual(movedAnimal.pasture?.publicID, north.publicID)

        let movements = try context.fetch(FetchDescriptor<MovementRecord>())
        let movement = try XCTUnwrap(movements.first)
        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movement.date, checkedAt)
        XCTAssertEqual(movement.fromPasture, "South")
        XCTAssertEqual(movement.toPasture, "North")
        XCTAssertEqual(movement.animal?.publicID, movedAnimal.publicID)
    }

    func testAddingTrackedAnimalAlreadyInPastureAddsCheckedRosterEntryWithoutMovementRecord() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let north = try makePastureWithAnimals(context: context, animalCount: 1, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: north.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )

        let newCalf = Animal(
            name: "Calf",
            tagNumber: "21",
            birthDate: Date(),
            status: .active,
            pasture: north,
            sex: .unknown
        )
        context.insert(newCalf)
        try context.save()

        try repository.addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: newCalf.publicID,
            checkedAt: Date(timeIntervalSince1970: 90)
        )

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let addedCheck = try XCTUnwrap(detail.animalChecks.first { $0.animalID == newCalf.publicID })
        XCTAssertEqual(detail.expectedHeadCountSnapshot, 2)
        XCTAssertEqual(detail.totalSeen, 1)
        XCTAssertTrue(addedCheck.wasCounted)
        XCTAssertFalse(addedCheck.wasExpectedAtStart)
        XCTAssertEqual(addedCheck.animalType, .calf)

        let movements = try context.fetch(FetchDescriptor<MovementRecord>())
        XCTAssertTrue(movements.isEmpty)
    }

    func testCompletedSessionLocksSessionDataButAllowsFindingStatusUpdates() throws {
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
            try repository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: animalID,
                checkedAt: Date(timeIntervalSince1970: 30)
            )
        }
        try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)

        assertSessionCompletedThrown {
            try repository.updateFinding(
                sessionID: sessionID,
                findingID: findingID,
                input: FieldCheckFindingInput(
                    recordedAt: Date(timeIntervalSince1970: 30),
                    type: .limping,
                    severity: .critical,
                    status: .open,
                    note: "Should not save",
                    animalID: animalID
                )
            )
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
        let resolvedFinding = try XCTUnwrap(lockedDetail.findings.first)
        XCTAssertEqual(resolvedFinding.status, .resolved)
        XCTAssertFalse(try XCTUnwrap(lockedDetail.animalChecks.first { $0.id == animalCheck.id }).needsAttention)

        try repository.reopenSession(id: sessionID)
        try repository.updateNotes(sessionID: sessionID, notes: "Unlocked")

        let reopenedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertFalse(reopenedDetail.isCompleted)
        XCTAssertEqual(reopenedDetail.notes, "Unlocked")
    }

    func testCompletedSessionAllowsResolvingMissingFindingAndClearsMissingStatus() throws {
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
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Missing.",
                animalID: animalID
            )
        )

        let missingDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(missingDetail.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(missingDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)

        try repository.completeSession(id: sessionID)
        try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)

        let resolvedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let resolvedAnimalCheck = try XCTUnwrap(resolvedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertTrue(resolvedDetail.isCompleted)
        XCTAssertFalse(resolvedAnimalCheck.isMissing)
        XCTAssertFalse(resolvedAnimalCheck.needsAttention)
        XCTAssertEqual(resolvedDetail.missingAnimalCount, 0)
    }



    func testUpdatingFindingEditsDetailsAndLinkedAnimal() throws {
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
        let firstAnimalID = try XCTUnwrap(initialDetail.animalChecks.first?.animalID)
        let secondAnimal = try XCTUnwrap(initialDetail.animalChecks.dropFirst().first)
        let secondAnimalID = try XCTUnwrap(secondAnimal.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Left eye.",
                animalID: firstAnimalID
            )
        )

        let detailWithFinding = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detailWithFinding.findings.first?.id)

        try repository.updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 20),
                type: .limping,
                severity: .critical,
                status: .monitoring,
                note: "Favoring rear leg.",
                animalID: secondAnimalID
            )
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedFinding = try XCTUnwrap(updatedDetail.findings.first)
        XCTAssertEqual(updatedFinding.recordedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(updatedFinding.type, .limping)
        XCTAssertEqual(updatedFinding.severity, .critical)
        XCTAssertEqual(updatedFinding.status, .monitoring)
        XCTAssertEqual(updatedFinding.note, "Favoring rear leg.")
        XCTAssertEqual(updatedFinding.animalID, secondAnimalID)
        XCTAssertEqual(updatedFinding.animalDisplayTagNumber, secondAnimal.displayTagNumber)
        XCTAssertFalse(try XCTUnwrap(updatedDetail.animalChecks.first { $0.animalID == firstAnimalID }).needsAttention)
        XCTAssertTrue(try XCTUnwrap(updatedDetail.animalChecks.first { $0.animalID == secondAnimalID }).needsAttention)
    }

    func testUpdatingFindingToMissingAnimalMarksNewAnimalMissingAndNormalizesQuickCount() throws {
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
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 2])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheck = try XCTUnwrap(initialDetail.animalChecks.first)
        let animalID = try XCTUnwrap(animalCheck.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 10),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Saw tracks.",
                animalID: nil
            )
        )

        let detailWithFinding = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(detailWithFinding.findings.first?.id)

        try repository.updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 20),
                type: .missingAnimal,
                severity: .critical,
                status: .open,
                note: "Not found during second pass.",
                animalID: animalID
            )
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedAnimalCheck = try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertTrue(updatedAnimalCheck.isMissing)
        XCTAssertTrue(updatedAnimalCheck.needsAttention)
        XCTAssertEqual(updatedDetail.quickHeiferCount, 1)
        XCTAssertEqual(updatedDetail.totalSeen, 1)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 1)
    }

    func testUpdatingMissingFindingToNonMissingClearsMissingStatusWhenNoUnresolvedMissingFindingRemains() throws {
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
                type: .missingAnimal,
                severity: .critical,
                status: .open,
                note: "Missing.",
                animalID: animalID
            )
        )

        let missingDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let findingID = try XCTUnwrap(missingDetail.findings.first?.id)
        XCTAssertTrue(try XCTUnwrap(missingDetail.animalChecks.first { $0.id == animalCheck.id }).isMissing)

        try repository.updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 20),
                type: .generalObservation,
                severity: .info,
                status: .resolved,
                note: "Found in shade.",
                animalID: animalID
            )
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let updatedAnimalCheck = try XCTUnwrap(updatedDetail.animalChecks.first { $0.id == animalCheck.id })
        XCTAssertFalse(updatedAnimalCheck.isMissing)
        XCTAssertFalse(updatedAnimalCheck.needsAttention)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 0)
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
