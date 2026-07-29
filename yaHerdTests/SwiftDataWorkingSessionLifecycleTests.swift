import XCTest
import SwiftData
@testable import yaHerd

@MainActor
final class SwiftDataWorkingSessionLifecycleTests: XCTestCase {
    func testFinishingWithUnworkedAnimalPreservesNotWorkedStatusAndReturnsToSource() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let sourcePasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = sourcePasture
        context.insert(sourcePasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil
            )
        )
        let queueItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingQueueItem>()).first
        )

        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItem.publicID,
                    destinationPastureID: sourcePasture.publicID
                )
            ]
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>())
                .first { $0.publicID == sessionID }
        )
        XCTAssertEqual(session.status, .finished)
        XCTAssertEqual(queueItem.status, .queued)
        XCTAssertNil(queueItem.completedAt)
        XCTAssertEqual(animal.pasture?.publicID, sourcePasture.publicID)
        XCTAssertEqual(animal.location, .pasture)
        XCTAssertNil(animal.activeWorkingSession)
    }

    func testFinishedSessionRejectsAnimalWorkChangesUntilReopened() throws {
        let fixture = try makeFinishedSessionFixture()
        let editInput = WorkingSessionAnimalEditInput(
            status: .done,
            completedAt: fixture.session.date,
            destinationPastureID: fixture.sourcePasture.publicID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            castrationPerformed: false,
            observationNotes: "Historical correction"
        )

        XCTAssertThrowsError(
            try fixture.repository.saveEdits(
                forQueueItemID: fixture.queueItem.publicID,
                inSessionID: fixture.session.publicID,
                input: editInput
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .sessionAlreadyFinished
            )
        }

        XCTAssertThrowsError(
            try fixture.repository.deleteWorkData(
                forQueueItemID: fixture.queueItem.publicID,
                inSessionID: fixture.session.publicID
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .sessionAlreadyFinished
            )
        }
    }

    func testReopenKeepsAnimalsInCurrentPasturesAndAllowsHistoricalEdits() throws {
        let fixture = try makeFinishedSessionFixture()

        try fixture.repository.reopenSession(id: fixture.session.publicID)

        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(
            fixture.animal.pasture?.publicID,
            fixture.sourcePasture.publicID
        )
        XCTAssertEqual(fixture.animal.location, .pasture)
        XCTAssertNil(fixture.animal.activeWorkingSession)
        XCTAssertEqual(
            fixture.queueItem.destinationPasture?.publicID,
            fixture.sourcePasture.publicID
        )

        try fixture.repository.saveEdits(
            forQueueItemID: fixture.queueItem.publicID,
            inSessionID: fixture.session.publicID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: fixture.session.date,
                destinationPastureID: fixture.sourcePasture.publicID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: "Corrected after reopening"
            )
        )

        XCTAssertEqual(fixture.queueItem.status, .done)
        XCTAssertEqual(
            fixture.animal.pasture?.publicID,
            fixture.sourcePasture.publicID
        )
        XCTAssertNil(fixture.animal.activeWorkingSession)
    }

    func testReopenedSessionCannotFinishAnimalOwnedByNewerActiveSession() throws {
        let fixture = try makeFinishedSessionFixture()
        try fixture.repository.reopenSession(id: fixture.session.publicID)

        let alternatePasture = Pasture(name: "South")
        fixture.repository.context.insert(alternatePasture)
        try fixture.repository.context.save()

        let newerSessionID = try fixture.repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )
        let newerSession = try XCTUnwrap(
            fixture.repository.context.fetch(FetchDescriptor<WorkingSession>())
                .first { $0.publicID == newerSessionID }
        )
        let movementCountBefore = try fixture.repository.context.fetch(
            FetchDescriptor<MovementRecord>()
        ).count

        XCTAssertThrowsError(
            try fixture.repository.completeSession(
                id: fixture.session.publicID,
                assignments: [
                    WorkingQueueDestinationAssignment(
                        queueItemID: fixture.queueItem.publicID,
                        destinationPastureID: alternatePasture.publicID
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalAlreadyInAnotherSession
            )
        }

        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(newerSession.status, .active)
        XCTAssertEqual(fixture.animal.activeWorkingSession?.publicID, newerSessionID)
        XCTAssertEqual(fixture.animal.location, .workingPen)
        XCTAssertNil(fixture.animal.pasture)
        XCTAssertEqual(
            fixture.queueItem.destinationPasture?.publicID,
            fixture.sourcePasture.publicID
        )
        XCTAssertEqual(
            try fixture.repository.context.fetch(FetchDescriptor<MovementRecord>()).count,
            movementCountBefore
        )
    }

    func testDeletingReopenedSessionDoesNotReleaseAnimalOwnedByNewerActiveSession() throws {
        let fixture = try makeFinishedSessionFixture()
        try fixture.repository.reopenSession(id: fixture.session.publicID)

        let newerSessionID = try fixture.repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )

        try fixture.repository.deleteSession(id: fixture.session.publicID)

        let remainingSessions = try fixture.repository.context.fetch(
            FetchDescriptor<WorkingSession>()
        )
        XCTAssertFalse(remainingSessions.contains { $0.publicID == fixture.session.publicID })
        XCTAssertTrue(remainingSessions.contains { $0.publicID == newerSessionID })
        XCTAssertEqual(fixture.animal.activeWorkingSession?.publicID, newerSessionID)
        XCTAssertEqual(fixture.animal.location, .workingPen)
        XCTAssertNil(fixture.animal.pasture)
    }

    func testReopenRejectsAlreadyActiveSession() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)
        let pasture = Pasture(name: "North")
        context.insert(pasture)
        try context.save()

        let sessionID = try repository.createSession(
            date: .now,
            sourcePastureID: pasture.publicID,
            protocolName: "Working Session",
            protocolItems: []
        )

        XCTAssertThrowsError(
            try repository.reopenSession(id: sessionID)
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .sessionAlreadyActive
            )
        }
    }

    private func makeFinishedSessionFixture() throws -> FinishedSessionFixture {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let sourcePasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = sourcePasture
        context.insert(sourcePasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil
            )
        )
        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>())
                .first { $0.publicID == sessionID }
        )
        let queueItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingQueueItem>())
                .first { $0.session?.publicID == sessionID }
        )

        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItem.publicID,
                    destinationPastureID: sourcePasture.publicID
                )
            ]
        )

        return FinishedSessionFixture(
            repository: repository,
            session: session,
            queueItem: queueItem,
            animal: animal,
            sourcePasture: sourcePasture
        )
    }
}

@MainActor
private struct FinishedSessionFixture {
    let repository: SwiftDataWorkingRepository
    let session: WorkingSession
    let queueItem: WorkingQueueItem
    let animal: Animal
    let sourcePasture: Pasture
}
