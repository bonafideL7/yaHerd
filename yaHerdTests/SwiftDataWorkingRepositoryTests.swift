import XCTest
import SwiftData
@testable import yaHerd

final class SwiftDataWorkingRepositoryTests: XCTestCase {
    func testCollectAnimalsRejectsDuplicateCollectionInSameSession() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(name: "Cow 12", tagNumber: "12", sex: .female, birthDate: .distantPast, status: .active)
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(date: .now, sourcePastureID: pasture.publicID, protocolName: "Spring Work", protocolItems: [])
        try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])

        XCTAssertThrowsError(try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateAnimalCollection)
        }
    }

    func testCollectAnimalsRejectsAnimalAlreadyInAnotherActiveSession() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(name: "Cow 12", tagNumber: "12", sex: .female, birthDate: .distantPast, status: .active)
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let firstSessionID = try repository.createSession(date: .now, sourcePastureID: pasture.publicID, protocolName: "Spring Work", protocolItems: [])
        let secondSessionID = try repository.createSession(date: .now.addingTimeInterval(60), sourcePastureID: pasture.publicID, protocolName: "Summer Work", protocolItems: [])
        try repository.collectAnimals(sessionID: firstSessionID, animalIDs: [animal.publicID])

        XCTAssertThrowsError(try repository.collectAnimals(sessionID: secondSessionID, animalIDs: [animal.publicID])) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .animalAlreadyInAnotherSession)
        }
    }

    func testCompleteAddsSingleObservationHealthRecord() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(name: "Cow 12", tagNumber: "12", sex: .female, birthDate: .distantPast, status: .active)
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(date: .now, sourcePastureID: pasture.publicID, protocolName: "Spring Work", protocolItems: [])
        try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])

        let descriptor = FetchDescriptor<WorkingQueueItem>()
        let queueItem = try XCTUnwrap(context.fetch(descriptor).first)

        try repository.complete(
            queueItemID: queueItem.publicID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: "Watch left eye"
        )

        let healthDescriptor = FetchDescriptor<HealthRecord>()
        let healthRecords = try context.fetch(healthDescriptor).filter {
            $0.animal?.publicID == animal.publicID && $0.treatment == "Observation"
        }

        XCTAssertEqual(healthRecords.count, 1)
        XCTAssertEqual(healthRecords.first?.notes, "Watch left eye")
    }
}
