import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataStage3StartupSelectionTests: XCTestCase {
    func testEmptyLocalLaunchRequiresExplicitHerdCreation() async throws {
        let harness = try CoreDataPersistenceHarness()
        let suiteName = "yaHerd.stage3.empty-local.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        XCTAssertNil(first.currentHerdSelection.currentHerdID)
        XCTAssertTrue(try first.makeDependencies(dataAccessMode: .readWrite)
            .herdRepository.fetchAccessibleHerds().isEmpty)

        let reopened = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        let repository = reopened.makeDependencies(dataAccessMode: .readWrite).herdRepository
        XCTAssertNil(reopened.currentHerdSelection.currentHerdID)
        XCTAssertTrue(try repository.fetchAccessibleHerds().isEmpty)

        let created = try await repository.createOwnedHerd(named: "My Herd")
        XCTAssertNil(reopened.currentHerdSelection.currentHerdID)
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [created.id])

        let directory = HerdDirectoryController(
            repository: repository, selection: reopened.currentHerdSelection
        )
        try directory.selectHerd(id: created.id)

        let restored = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        XCTAssertEqual(restored.currentHerdSelection.currentHerdID, created.id)
        XCTAssertEqual(try restored.makeDependencies(dataAccessMode: .readWrite)
            .herdRepository.fetchAccessibleHerds().count, 1)
    }

    func testIncompleteLocalRootCannotBeMistakenForAnEmptyInstallation() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.load(
            storeURL: harness.storeURL
        )
        let originalID = UUID()
        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let root = CDHerd(context: writer)
            root.id = originalID
            root.name = nil
            root.createdAt = Date(timeIntervalSince1970: 100)
            root.updatedAt = Date(timeIntervalSince1970: 100)
            try writer.save()
        }

        do {
            _ = try await CoreDataAppPersistenceAssembly.load(at: harness.storeURL)
            XCTFail("An incomplete local Herd must not open the empty-state chooser.")
        } catch {
            XCTAssertEqual(error as? CoreDataHerdMappingError, .missingName(herdID: originalID))
        }

        let reader = assembly.contextFactory.makeReadContext()
        try reader.performAndWait {
            let roots = try reader.fetch(
                NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            )
            XCTAssertEqual(roots.count, 1)
            XCTAssertEqual(roots.first?.id, originalID)
            XCTAssertNil(roots.first?.name)
        }
    }

    func testLocalMultiHerdLaunchUsesChooserWithoutCreatingAnotherRoot() async throws {
        let harness = try CoreDataPersistenceHarness()
        let suiteName = "yaHerd.stage3.startup.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL, selectionPreferences: defaults
        )
        let repository = first.makeDependencies(dataAccessMode: .readWrite).herdRepository
        let original = try await repository.createOwnedHerd(named: "Original")
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
