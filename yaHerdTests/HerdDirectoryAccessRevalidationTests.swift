import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class HerdDirectoryAccessRevalidationTests: XCTestCase {
    func testMissingSelectedHerdLeavesChooserActiveWithoutChangingSavedPreference() throws {
        let suite = "stage3-access-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let selectedID = UUID()
        let otherID = UUID()
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )
        selection.select(selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID), herd(otherID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.refresh()
        XCTAssertEqual(directory.selectedHerdID, selectedID)

        repository.available = [herd(otherID)]
        directory.refresh(reportErrors: false)
        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(directory.herds.map(\.id), [otherID])
        XCTAssertEqual(defaults.string(forKey: "selected"), selectedID.uuidString)

        // A different available Herd is never selected without user consent.
        directory.refresh()
        XCTAssertNil(directory.selectedHerdID)

        // Reappearance alone is not sufficient: imported related records may
        // still be incomplete. The chooser performs readiness validation.
        repository.available = [herd(selectedID), herd(otherID)]
        directory.refresh(reportErrors: false)
        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), selectedID.uuidString)

    }

    func testTransientInventoryFailureRetainsActiveHerd() {
        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.refresh()
        repository.shouldFail = true
        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.selectedHerdID, selectedID)
        XCTAssertEqual(directory.herds.map(\.id), [selectedID])
        XCTAssertNil(directory.errorMessage)
    }

    func testBackgroundSuccessDoesNotDismissManualInventoryError() {
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository()
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        repository.shouldFail = true
        directory.refresh()
        XCTAssertNotNil(directory.errorMessage)

        repository.shouldFail = false
        directory.refresh(reportErrors: false)
        XCTAssertNotNil(directory.errorMessage)

        directory.refresh()
        XCTAssertNil(directory.errorMessage)
    }

    func testNewImportedHerdDoesNotBypassUnselectedChooser() {
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository()
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.refresh()
        repository.available = [herd(UUID())]
        directory.refresh(reportErrors: false)

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(directory.herds.count, 1)
    }

    func testCompletedActiveCreationSelectsTheNewHerd() async throws {
        let originalID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(available: [herd(originalID)])
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let creation = Task {
            try await directory.createOwnedHerd(named: "New Herd")
        }
        await repository.waitForPendingCreation()
        repository.completeCreation()

        let result = try await creation.value
        XCTAssertEqual(result.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, createdID)
        XCTAssertEqual(Set(directory.herds.map(\.id)), [originalID, createdID])
    }

    func testCompletedCreationDoesNotReplaceASelectionMadeWhileSaving() async throws {
        let initialID = UUID()
        let subsequentlySelectedID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: initialID)
        let repository = StubHerdRepository(
            available: [herd(initialID), herd(subsequentlySelectedID)]
        )
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let creation = Task {
            try await directory.createOwnedHerd(named: "New Herd")
        }
        await repository.waitForPendingCreation()
        selection.select(subsequentlySelectedID)
        repository.completeCreation()

        let result = try await creation.value
        XCTAssertEqual(result.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, subsequentlySelectedID)
        XCTAssertEqual(Set(directory.herds.map(\.id)), [initialID, subsequentlySelectedID, createdID])
    }

    func testCancelledCreationPreservesSelectionAfterTheRootWasSaved() async throws {
        let selectedID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let creation = Task {
            try await directory.createOwnedHerd(named: "New Herd")
        }
        await repository.waitForPendingCreation()
        creation.cancel()
        repository.completeCreation()

        let result = try await creation.value
        XCTAssertEqual(result.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, selectedID)
        XCTAssertEqual(Set(directory.herds.map(\.id)), [selectedID, createdID])
    }

    private func herd(_ id: UUID) -> AccessibleHerd {
        AccessibleHerd(
            summary: HerdSummary(
                publicID: id,
                name: "Test Herd",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            category: .owned
        )
    }

    private final class StubHerdRepository: HerdRepository {
        var available: [AccessibleHerd]
        var shouldFail = false
        var createdHerd: AccessibleHerd?
        private var pendingCreation: CheckedContinuation<HerdSummary, Never>?

        init(available: [AccessibleHerd] = []) {
            self.available = available
        }

        func fetchCurrentHerd() throws -> HerdSummary {
            throw HerdRepositoryError.missingHerd
        }

        func fetchAccessibleHerds() throws -> [AccessibleHerd] {
            if shouldFail { throw HerdRepositoryError.missingHerd }
            return available
        }

        func createOwnedHerd(named name: String) async throws -> HerdSummary {
            guard createdHerd != nil else { throw HerdRepositoryError.missingHerd }
            return await withCheckedContinuation { continuation in
                pendingCreation = continuation
            }
        }

        func waitForPendingCreation() async {
            while pendingCreation == nil {
                await Task.yield()
            }
        }

        func completeCreation() {
            guard let createdHerd, let pendingCreation else {
                preconditionFailure("No pending Herd creation")
            }
            available.append(createdHerd)
            self.pendingCreation = nil
            pendingCreation.resume(returning: createdHerd.summary)
        }

        func renameCurrentHerd(to name: String) async throws -> HerdSummary {
            throw HerdRepositoryError.missingHerd
        }
    }
}
