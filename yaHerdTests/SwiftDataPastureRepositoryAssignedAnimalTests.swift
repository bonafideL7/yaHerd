import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataPastureRepositoryAssignedAnimalTests: XCTestCase {
    func testFetchAssignedAnimalsIncludesInactiveAndArchivedAnimals() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let pasture = Pasture(name: "North")
        let otherPasture = Pasture(name: "South")
        let birthDate = Date(timeIntervalSince1970: 1)

        let active = Animal(
            name: "Active",
            tagNumber: "100",
            birthDate: birthDate,
            pasture: pasture,
            sex: .female
        )
        let sold = Animal(
            name: "Sold",
            tagNumber: "200",
            birthDate: birthDate,
            status: .sold,
            pasture: pasture,
            sex: .female
        )
        let dead = Animal(
            name: "Dead",
            tagNumber: "300",
            birthDate: birthDate,
            status: .dead,
            pasture: pasture,
            sex: .female
        )
        let archived = Animal(
            name: "Archived",
            tagNumber: "400",
            birthDate: birthDate,
            isSoftDeleted: true,
            softDeletedAt: birthDate,
            pasture: pasture,
            sex: .female
        )
        let other = Animal(
            name: "Other",
            tagNumber: "500",
            birthDate: birthDate,
            pasture: otherPasture,
            sex: .female
        )

        context.insert(pasture)
        context.insert(otherPasture)
        context.insert(active)
        context.insert(sold)
        context.insert(dead)
        context.insert(archived)
        context.insert(other)
        try context.save()

        let repository = SwiftDataPastureRepository(context: context)

        XCTAssertEqual(
            try repository.fetchResidentAnimals(pastureID: pasture.publicID).map(\.id),
            [active.publicID]
        )
        XCTAssertEqual(
            try repository.fetchAssignedAnimals(pastureID: pasture.publicID).map(\.id),
            [active.publicID, sold.publicID, dead.publicID, archived.publicID]
        )
    }
}
