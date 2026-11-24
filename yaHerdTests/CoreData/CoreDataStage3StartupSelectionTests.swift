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

        let app = CoreDataAppPersistenceAssembly.resolveHerdForChoice(
            using: assembly,
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
        let repository = CoreDataHerdRepository(selection: AppCurrentHerdSelection(), assembly: assembly)
        let existing = try await repository.createOwnedHerd(named: "Existing")
        let app = CoreDataAppPersistenceAssembly.resolveHerdForChoice(
            using: assembly, requestedHerdID: UUID()
        )
        XCTAssertNil(app.currentHerdSelection.currentHerdID)
        XCTAssertEqual(try app.makeDependencies(dataAccessMode: .readWrite).herdRepository.fetchAccessibleHerds().map(\.id), [existing.id])
    }
}
