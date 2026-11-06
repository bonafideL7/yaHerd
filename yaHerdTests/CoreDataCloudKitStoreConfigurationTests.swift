import CloudKit
import CoreData
import Foundation
import XCTest
@testable import yaHerd

final class CoreDataCloudKitStoreConfigurationTests: XCTestCase {
    func testCloudKitStoresReuseExistingSQLiteAsPrivateAndSeparateSharedURL() {
        let originalStore = URL(fileURLWithPath: "/tmp/yaHerd-existing/yaHerd.sqlite")
        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: originalStore
        )

        XCTAssertEqual(descriptions.count, 2)
        XCTAssertEqual(descriptions[0].url, originalStore)
        XCTAssertEqual(descriptions[1].url, originalStore.deletingLastPathComponent()
            .appendingPathComponent("yaHerd-shared.sqlite"))
        XCTAssertNotEqual(descriptions[0].url, descriptions[1].url)

        XCTAssertEqual(descriptions[0].cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertEqual(descriptions[1].cloudKitContainerOptions?.databaseScope, .shared)
        for description in descriptions {
            XCTAssertEqual(description.type, NSSQLiteStoreType)
            XCTAssertEqual(
                description.cloudKitContainerOptions?.containerIdentifier,
                CoreDataPersistentContainer.cloudKitContainerIdentifier
            )
            XCTAssertTrue(description.shouldMigrateStoreAutomatically)
            XCTAssertTrue(description.shouldInferMappingModelAutomatically)
            XCTAssertEqual(
                description.options[NSPersistentHistoryTrackingKey] as? NSNumber,
                NSNumber(value: true)
            )
            XCTAssertEqual(
                description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber,
                NSNumber(value: true)
            )
        }
    }

    func testCloudKitStoreConfigurationDoesNotTouchLocalDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existingStore = directory.appendingPathComponent("yaHerd.sqlite")
        let original = Data("existing database sentinel".utf8)
        try original.write(to: existingStore)

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: existingStore
        )

        XCTAssertEqual(descriptions.first?.url, existingStore)
        XCTAssertEqual(try Data(contentsOf: existingStore), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("yaHerd-shared.sqlite").path
        ))
    }
}
