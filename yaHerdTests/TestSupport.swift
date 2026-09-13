import Foundation
import SwiftData
@testable import yaHerd

@MainActor
enum TestSupport {
    static func makeSchema() -> Schema {
        yaHerdApp.makeSchema()
    }

    static func makeModelContainer() throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: YaHerdMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
