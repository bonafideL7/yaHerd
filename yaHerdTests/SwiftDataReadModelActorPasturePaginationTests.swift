import Foundation
import SwiftData
import XCTest

@testable import yaHerd

extension SwiftDataReadModelActorTests {
    func testPastureOptionsReturnEveryPastureWhenSortValuesTie() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        var expectedIDs = Set<UUID>()

        for _ in 0..<620 {
            let pasture = Pasture(
                name: "Duplicate pasture",
                sortOrder: 0
            )
            expectedIDs.insert(pasture.publicID)
            context.insert(pasture)
        }
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        let options = try await reader.fetchAnimalPastureOptions(limit: 250)

        XCTAssertEqual(options.count, 620)
        XCTAssertEqual(Set(options.map(\.id)), expectedIDs)
    }
}
