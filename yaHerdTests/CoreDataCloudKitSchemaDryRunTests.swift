@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

final class CoreDataCloudKitSchemaDryRunTests: XCTestCase {
    func testCompiledModelPassesApplesCloudKitSchemaValidation() async throws {
        let modelBundle = Bundle(for: CDHerd.self)
        let modelURL = modelBundle.url(
            forResource: CoreDataPersistentContainer.modelName,
            withExtension: "momd"
        ) ?? modelBundle.url(
            forResource: CoreDataPersistentContainer.modelName,
            withExtension: "mom"
        )
        let model = try XCTUnwrap(modelURL.flatMap(NSManagedObjectModel.init(contentsOf:)))

        // An isolated SQLite store ensures the preflight cannot load or modify
        // the user's existing yaHerd store.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-CloudKitSchemaDryRun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CloudKitSchema.sqlite")
        let container = NSPersistentCloudKitContainer(
            name: CoreDataPersistentContainer.modelName,
            managedObjectModel: model
        )
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: directory)
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        let options = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.ltd.yaherd"
        )
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Apple's dryRun validates/generates the CloudKit schema without
        // uploading representative records or changing CloudKit databases.
        try container.initializeCloudKitSchema(options: [.dryRun])
    }
}
