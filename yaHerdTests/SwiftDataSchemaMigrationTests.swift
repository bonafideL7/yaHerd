import Foundation
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataSchemaMigrationTests: XCTestCase {
    func testMigrationPlanContainsCurrentSchema() {
        XCTAssertFalse(YaHerdMigrationPlan.schemas.isEmpty)
        XCTAssertEqual(
            YaHerdMigrationPlan.currentSchema.versionIdentifier,
            YaHerdSchemaV1.versionIdentifier
        )
    }

    func testEveryRegisteredSchemaHasAFixtureStore() {
        XCTAssertEqual(
            YaHerdMigrationPlan.schemas.map { $0.versionIdentifier },
            YaHerdMigrationFixtureStores.versionIdentifiers
        )
    }

    func testMigrationPlanHasAStageBetweenEveryRegisteredSchema() {
        XCTAssertEqual(
            YaHerdMigrationPlan.stages.count,
            max(YaHerdMigrationPlan.schemas.count - 1, 0)
        )
        XCTAssertTrue(YaHerdMigrationPlan.stages.isEmpty)
    }

    func testEveryFixtureStoreOpensThroughProductionMigrationPlan() throws {
        for schema in YaHerdMigrationPlan.schemas {
            try assertFixtureOpensThroughProductionPlan(
                from: schema.versionIdentifier
            )
        }
    }

    private func assertFixtureOpensThroughProductionPlan(
        from versionIdentifier: Schema.Version
    ) throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "YaHerdSchemaMigrationTests")
            .appending(path: UUID().uuidString)
        let storeURL = fixtureDirectory.appending(path: "yaHerdStore.store")

        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }

        try YaHerdMigrationFixtureStores.createStore(
            for: versionIdentifier,
            at: storeURL
        )

        let container = try ModelContainerFactory.makeContainer(
            syncMode: .localOnly,
            storeURL: storeURL
        )

        try YaHerdMigrationFixtureStores.validateStoreOpenedThroughCurrentPlan(
            from: versionIdentifier,
            in: container.mainContext
        )
    }
}
