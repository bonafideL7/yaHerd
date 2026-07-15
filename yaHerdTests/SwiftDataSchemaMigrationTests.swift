import Foundation
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataSchemaMigrationTests: XCTestCase {
    func testMigrationPlanHasAtLeastOneReleasedSchema() {
        XCTAssertFalse(YaHerdMigrationPlan.schemas.isEmpty)
    }

    func testEveryReleasedSchemaHasAFixtureStore() {
        XCTAssertEqual(
            YaHerdMigrationPlan.schemas.map { $0.versionIdentifier },
            YaHerdMigrationFixtureStores.versionIdentifiers
        )
    }

    func testMigrationPlanHasAStageBetweenEveryReleasedSchema() {
        XCTAssertEqual(
            YaHerdMigrationPlan.stages.count,
            max(YaHerdMigrationPlan.schemas.count - 1, 0)
        )
    }

    func testEveryReleasedFixtureStoreUpgradesThroughProductionMigrationPlan() throws {
        for releasedSchema in YaHerdMigrationPlan.schemas {
            try assertFixtureUpgrades(
                from: releasedSchema.versionIdentifier
            )
        }
    }

    private func assertFixtureUpgrades(
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

        let upgradedContainer = try ModelContainerFactory.makeContainer(
            syncMode: .localOnly,
            storeURL: storeURL
        )

        try YaHerdMigrationFixtureStores.validateUpgradedStore(
            from: versionIdentifier,
            in: upgradedContainer.mainContext
        )
    }
}
