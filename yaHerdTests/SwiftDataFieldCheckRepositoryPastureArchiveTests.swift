import XCTest
import SwiftData
@testable import yaHerd

@MainActor
final class SwiftDataFieldCheckRepositoryPastureArchiveTests: XCTestCase {
    func testArchivingDeletedPasturePreservesFieldCheckHistoryAfterPastureIsDeleted() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = Pasture(name: "North", sortOrder: 0)
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: Date(timeIntervalSince1970: 0),
            pasture: pasture,
            sex: .female
        )
        context.insert(pasture)
        context.insert(animal)
        try context.save()
        let pastureID = pasture.publicID

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pastureID,
                startedAt: Date(timeIntervalSince1970: 10),
                notes: "Before deletion"
            )
        )
        let archivedAt = Date(timeIntervalSince1970: 20)

        try repository.archiveSessionsForDeletedPastures([pastureID], archivedAt: archivedAt)
        context.delete(pasture)
        try context.save()

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(detail.pastureID, pastureID)
        XCTAssertEqual(detail.pastureName, "North")
        XCTAssertEqual(detail.pastureArchivedAt, archivedAt)
        XCTAssertTrue(detail.isPastureArchived)
        XCTAssertEqual(detail.expectedHeadCountSnapshot, 1)
        XCTAssertEqual(detail.animalChecks.first?.displayTagNumber, "12")
    }

    func testArchivingDeletedPastureBackfillsLegacySessionPastureSnapshots() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = Pasture(name: "Legacy", sortOrder: 0)
        let session = FieldCheckSession(
            startedAt: Date(timeIntervalSince1970: 10),
            pastureNameSnapshot: "",
            pastureID: nil,
            pasture: pasture
        )
        context.insert(pasture)
        context.insert(session)
        try context.save()
        let pastureID = pasture.publicID

        let archivedAt = Date(timeIntervalSince1970: 30)
        try repository.archiveSessionsForDeletedPastures([pastureID], archivedAt: archivedAt)

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: session.publicID))
        XCTAssertEqual(detail.pastureID, pastureID)
        XCTAssertEqual(detail.pastureName, "Legacy")
        XCTAssertEqual(detail.pastureArchivedAt, archivedAt)
        XCTAssertTrue(detail.isPastureArchived)
    }
}
