import Foundation
import SwiftData
import XCTest

@testable import yaHerd

extension SwiftDataReadModelActorTests {
    func testAnimalSummaryPaginationReturnsEveryAnimalWhenPrimarySortValuesTie() async throws {
        let schema = yaHerdApp.makeSchema()
        let configuration = ModelConfiguration(
            "SwiftDataReadModelActorPaginationTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: YaHerdMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext

        for _ in 0..<620 {
            context.insert(
                Animal(
                    name: "Duplicate",
                    tagNumber: "",
                    birthDate: .now,
                    status: .active,
                    sex: .female
                )
            )
        }
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        var offset = 0
        var ids: [UUID] = []

        while true {
            let page = try await reader.fetchAnimalSummaryPage(
                ReadPageRequest(offset: offset, limit: 250)
            )
            ids.append(contentsOf: page.animals.map(\.id))

            guard page.hasMore else { break }
            XCTAssertFalse(page.animals.isEmpty)
            offset += page.animals.count
        }

        XCTAssertEqual(ids.count, 620)
        XCTAssertEqual(Set(ids).count, 620)
    }
}
