import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataStage3StartupSelectionTests: XCTestCase {
    func testLocalMultiHerdLaunchUsesChooserWithoutCreatingAnotherRoot() async throws {
        let harness = try CoreDataPersistenceHarness()
        let suiteName = "yaHerd.stage3.startup.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        let repository = first.makeDependencies(dataAccessMode: .readWrite).herdRepository
        let original = try repository.fetchCurrentHerd()
        let other = try await repository.createOwnedHerd(named: "Other")

        let reopened = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        XCTAssertNil(reopened.currentHerdSelection.currentHerdID)
        let reopenedRepository = reopened.makeDependencies(dataAccessMode: .readWrite)
            .herdRepository
        XCTAssertEqual(
            Set(try reopenedRepository.fetchAccessibleHerds().map(\.id)),
            [original.id, other.id]
        )

        let directory = HerdDirectoryController(
            repository: reopenedRepository, selection: reopened.currentHerdSelection
        )
        try directory.selectHerd(id: other.id)

        let restored = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        XCTAssertEqual(restored.currentHerdSelection.currentHerdID, other.id)
    }

    func testEmptyCloudKitImportCanShowChooserWithoutCreatingPrivateRoot() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let suiteName = "yaHerd.stage3.cloudkit.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let app = try CoreDataAppPersistenceAssembly.resolveCloudKitHerdForChoice(
            using: assembly, privateStoreURL: harness.storeURL,
            selectionPreferences: defaults
        )
        XCTAssertNil(app.currentHerdSelection.currentHerdID)
        XCTAssertTrue(
            try app.makeDependencies(dataAccessMode: .readWrite)
                .herdRepository.fetchAccessibleHerds().isEmpty
        )
    }

    func testExplicitUnavailableCloudKitHerdCannotFallBackToAnother() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        XCTAssertThrowsError(try CoreDataAppPersistenceAssembly.resolveCloudKitHerdForChoice(
            using: assembly, privateStoreURL: harness.storeURL,
            requestedHerdID: UUID()
        )) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .missingHerd)
        }
    }

    func testRevokedSharedHerdClearsActiveSelectionWithoutChoosingOwnedHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let owned = try await repository.createOwnedHerd(named: "Owned")
        let sharedID = UUID()

        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let sharedStore = try XCTUnwrap(
                context.persistentStoreCoordinator?.persistentStores.first {
                    $0.url?.lastPathComponent == CoreDataPersistentContainer.sharedStoreFileName
                }
            )
            let shared = CDHerd(context: context)
            shared.id = sharedID
            shared.name = "Joined"
            shared.createdAt = Date(timeIntervalSince1970: 100)
            shared.updatedAt = Date(timeIntervalSince1970: 100)
            context.assign(shared, to: sharedStore)
            try context.save()
        }

        let directory = HerdDirectoryController(repository: repository, selection: selection)
        try directory.selectHerd(id: sharedID)
        XCTAssertEqual(directory.selectedHerdID, sharedID)

        // Model the local removal of a revoked share after CloudKit import.
        let removalContext = try assembly.contextFactory.makeWriteContext()
        try removalContext.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            request.predicate = NSPredicate(format: "id == %@", sharedID as NSUUID)
            let shared = try XCTUnwrap(removalContext.fetch(request).first)
            removalContext.delete(shared)
            try removalContext.save()
        }
        directory.refresh(reportErrors: false)

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(directory.herds.map(\.id), [owned.id])
        XCTAssertEqual(directory.herds.first?.category, .owned)
        XCTAssertThrowsError(try repository.fetchCurrentHerd()) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .missingHerd)
        }
    }
}
