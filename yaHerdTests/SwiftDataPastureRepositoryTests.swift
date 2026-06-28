import XCTest
import SwiftData
@testable import yaHerd

final class SwiftDataPastureRepositoryTests: XCTestCase {
    func testNameExistsIsCaseInsensitiveAndIgnoresExcludedID() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        context.insert(pasture)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertTrue(try repository.nameExists(" north ", excluding: nil))
        XCTAssertFalse(try repository.nameExists(" north ", excluding: pasture.publicID))
    }

    func testCreateTrimsNameAndAssignsNextSortOrder() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        context.insert(Pasture(name: "Existing", sortOrder: 4))
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)
        let detail = try repository.create(input: PastureInput(name: "  North  ", acreage: 12, usableAcreage: 10, targetAcresPerHead: 2))

        XCTAssertEqual(detail.name, "North")
        let descriptor = FetchDescriptor<Pasture>()
        let created = try XCTUnwrap(context.fetch(descriptor).first { $0.publicID == detail.id })
        XCTAssertEqual(created.sortOrder, 5)
    }

    func testCreateRejectsDuplicateName() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        context.insert(Pasture(name: "North"))
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertThrowsError(
            try repository.create(input: PastureInput(name: " north ", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("north"))
        }
    }

    func testReorderRejectsDuplicateIDs() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        context.insert(pasture)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertThrowsError(try repository.reorder(ids: [pasture.publicID, pasture.publicID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }
    }

    func testReorderRejectsMissingIDs() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        context.insert(pasture)
        try context.save()

        let missingID = UUID()
        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertThrowsError(try repository.reorder(ids: [pasture.publicID, missingID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .pastureIDsNotFound([missingID]))
        }
    }

    func testReorderPersistsRequestedOrderAndMovesRemainingPasturesAfterThem() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let north = Pasture(name: "North", sortOrder: 0)
        let south = Pasture(name: "South", sortOrder: 1)
        let east = Pasture(name: "East", sortOrder: 2)
        context.insert(north)
        context.insert(south)
        context.insert(east)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)
        try repository.reorder(ids: [east.publicID, north.publicID])

        let pastures = try repository.fetchPastures()
        XCTAssertEqual(pastures.map(\.id), [east.publicID, north.publicID, south.publicID])
        XCTAssertEqual(pastures.map(\.sortOrder), [0, 1, 2])
    }

    func testDeleteRejectsMissingIDsBeforeDeletingFoundPastures() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        context.insert(pasture)
        try context.save()

        let missingID = UUID()
        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertThrowsError(try repository.delete(ids: [pasture.publicID, missingID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .pastureIDsNotFound([missingID]))
        }

        XCTAssertNotNil(try repository.fetchPastureDetail(id: pasture.publicID))
    }

    func testCreateGroupRejectsDuplicateNameCaseInsensitively() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        context.insert(PastureGroup(name: "Spring", grazeDays: 7, restDays: 21))
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertThrowsError(try repository.createGroup(input: PastureGroupInput(name: " spring ", grazeDays: 7, restDays: 21))) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("spring"))
        }
    }

    func testAssignPastureToGroupAndUnassignPasture() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        let group = PastureGroup(name: "Spring", grazeDays: 7, restDays: 21)
        context.insert(pasture)
        context.insert(group)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)
        try repository.assignPasture(id: pasture.publicID, toGroupID: group.publicID)

        var detail = try XCTUnwrap(repository.fetchPastureDetail(id: pasture.publicID))
        XCTAssertEqual(detail.groupID, group.publicID)
        XCTAssertEqual(detail.groupName, "Spring")

        try repository.assignPasture(id: pasture.publicID, toGroupID: nil)

        detail = try XCTUnwrap(repository.fetchPastureDetail(id: pasture.publicID))
        XCTAssertNil(detail.groupID)
        XCTAssertNil(detail.groupName)
    }

    func testDeleteGroupDoesNotDeleteAssignedPasture() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        let group = PastureGroup(name: "Spring", grazeDays: 7, restDays: 21)
        pasture.group = group
        context.insert(group)
        context.insert(pasture)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)
        try repository.deleteGroups(ids: [group.publicID])

        let detail = try XCTUnwrap(repository.fetchPastureDetail(id: pasture.publicID))
        XCTAssertEqual(detail.name, "North")
        XCTAssertNil(detail.groupID)
        XCTAssertNil(detail.groupName)
    }
}
