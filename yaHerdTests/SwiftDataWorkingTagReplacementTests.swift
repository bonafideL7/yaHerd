import XCTest
import SwiftData
@testable import yaHerd

@MainActor
final class SwiftDataWorkingTagReplacementTests: XCTestCase {
    func testReplacePrimaryTagRetiresPreviousTagAndPromotesReplacement() throws {
        let fixture = try makeFixture(tagNumber: "12")

        let updated = try fixture.repository.replacePrimaryTag(
            forQueueItemID: fixture.queueItem.publicID,
            inSessionID: fixture.sessionID,
            input: WorkingTagReplacementInput(number: "99", colorID: nil)
        )

        XCTAssertEqual(updated.animalDisplayTagNumber, "99")
        XCTAssertEqual(fixture.animal.displayTagNumber, "99")
        XCTAssertEqual(fixture.animal.activeTags.map(\.normalizedNumber), ["99"])
        XCTAssertEqual(fixture.animal.inactiveTags.map(\.normalizedNumber), ["12"])
        XCTAssertNotNil(fixture.animal.inactiveTags.first?.removedAt)
    }

    func testLegacyTagIsMaterializedBeforeSharedReplacementTime() throws {
        let fixture = try makeFixture(tagNumber: "12")
        XCTAssertTrue(fixture.animal.tags.isEmpty)

        _ = try fixture.repository.replacePrimaryTag(
            forQueueItemID: fixture.queueItem.publicID,
            inSessionID: fixture.sessionID,
            input: WorkingTagReplacementInput(number: "99", colorID: nil)
        )

        let retiredTag = try XCTUnwrap(fixture.animal.inactiveTags.first)
        let replacementTag = try XCTUnwrap(fixture.animal.activeTags.first)
        let retiredAt = try XCTUnwrap(retiredTag.removedAt)

        XCTAssertLessThanOrEqual(retiredTag.assignedAt, retiredAt)
        XCTAssertEqual(retiredAt, replacementTag.assignedAt)
    }

    func testReplacePrimaryTagDoesNotCreateRetiredPlaceholderForUntaggedAnimal() throws {
        let fixture = try makeFixture(tagNumber: "")

        _ = try fixture.repository.replacePrimaryTag(
            forQueueItemID: fixture.queueItem.publicID,
            inSessionID: fixture.sessionID,
            input: WorkingTagReplacementInput(number: "44", colorID: nil)
        )

        XCTAssertEqual(fixture.animal.activeTags.map(\.normalizedNumber), ["44"])
        XCTAssertTrue(fixture.animal.inactiveTags.isEmpty)
    }

    func testReplacePrimaryTagRejectsEmptyNumber() throws {
        let fixture = try makeFixture(tagNumber: "12")

        XCTAssertThrowsError(
            try fixture.repository.replacePrimaryTag(
                forQueueItemID: fixture.queueItem.publicID,
                inSessionID: fixture.sessionID,
                input: WorkingTagReplacementInput(number: "   ", colorID: nil)
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .invalidTagNumber)
        }

        XCTAssertEqual(fixture.animal.displayTagNumber, "12")
    }

    private func makeFixture(tagNumber: String) throws -> Fixture {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)
        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: tagNumber,
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(
            date: .now,
            sourcePastureID: pasture.publicID,
            protocolName: "Spring Work",
            protocolItems: []
        )
        try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])
        let queueItem = try XCTUnwrap(context.fetch(FetchDescriptor<WorkingQueueItem>()).first)

        return Fixture(
            repository: repository,
            animal: animal,
            queueItem: queueItem,
            sessionID: sessionID
        )
    }

    private struct Fixture {
        let repository: SwiftDataWorkingRepository
        let animal: Animal
        let queueItem: WorkingQueueItem
        let sessionID: UUID
    }
}
