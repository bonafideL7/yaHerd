//
//  SwiftDataHerdRepositoryTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataHerdRepositoryTests: XCTestCase {
    func testFetchCurrentHerdCreatesDefaultHerdWhenMissing() throws {
        let repository = try makeRepository()

        let herd = try repository.fetchCurrentHerd()

        XCTAssertEqual(herd.name, DefaultHerdBootstrapper.defaultHerdName)
        XCTAssertEqual(herd.schemaVersion, 1)
    }

    func testRenameCurrentHerdTrimsAndPersistsName() throws {
        let repository = try makeRepository()

        let renamedHerd = try repository.renameCurrentHerd(to: "  South Herd  ")
        let fetchedHerd = try repository.fetchCurrentHerd()

        XCTAssertEqual(renamedHerd.name, "South Herd")
        XCTAssertEqual(fetchedHerd.name, "South Herd")
        XCTAssertEqual(fetchedHerd.publicID, renamedHerd.publicID)
    }

    func testRenameCurrentHerdRejectsEmptyName() throws {
        let repository = try makeRepository()

        XCTAssertThrowsError(try repository.renameCurrentHerd(to: "   ")) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName)
        }
    }

    private func makeRepository() throws -> SwiftDataHerdRepository {
        let schema = yaHerdApp.makeSchema()
        let configuration = ModelConfiguration(
            "SwiftDataHerdRepositoryTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, migrationPlan: YaHerdMigrationPlan.self, configurations: [configuration])
        return SwiftDataHerdRepository(context: container.mainContext)
    }
}
