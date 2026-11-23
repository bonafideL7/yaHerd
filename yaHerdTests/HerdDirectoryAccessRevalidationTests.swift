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

    func testPendingHerdRetryStopsWhenTheRootDisappears() {
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository(available: [herd(pendingID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()

        // A previously selectable root can disappear after shared access is revoked.
        // A failed readiness check must not retry this missing UUID forever.
        repository.available = []

        XCTAssertFalse(directory.shouldContinueWaitingForHerd(id: pendingID))
        XCTAssertEqual(directory.inventoryState, .available)
        XCTAssertTrue(directory.herds.isEmpty)
        XCTAssertNil(directory.selectedHerdID)
    }

    func testPendingHerdRetryPreservesWaitingOnTransientInventoryFailure() {
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository(available: [herd(pendingID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()

        // A failed inventory read is not proof that the Herd was revoked.
        repository.shouldFail = true

        XCTAssertTrue(directory.shouldContinueWaitingForHerd(id: pendingID))
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertEqual(directory.herds.map(\.id), [pendingID])
        XCTAssertNil(directory.errorMessage)
    }

    func testPendingHerdRetryContinuesForAccessibleHerd() {
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository(available: [herd(pendingID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        XCTAssertTrue(directory.shouldContinueWaitingForHerd(id: pendingID))
        XCTAssertEqual(directory.inventoryState, .available)
        XCTAssertEqual(directory.herds.map(\.id), [pendingID])
    }

    func testPendingHerdRetryDoesNotMistakeIncompleteImportForRemoval() {
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository()
        repository.hasIncompleteRoots = true
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        // Import metadata may be missing before the root becomes selectable.
        XCTAssertTrue(directory.shouldContinueWaitingForHerd(id: pendingID))
        XCTAssertEqual(directory.inventoryState, .incomplete)
        XCTAssertTrue(directory.herds.isEmpty)
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

    func testDirectHerdSelectionFailsClosedWhenActiveRootIdentityCollides() throws {
        let selectedID = UUID()
        let otherID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID), herd(otherID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()
        let revision = selection.selectionRevision

        repository.inventoryError = .duplicateApplicationID(
            entity: CDHerd.coreDataEntityName, id: selectedID, herdID: nil
        )
        XCTAssertThrowsError(try directory.selectHerd(id: otherID)) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, repository.inventoryError)
        }

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(selection.selectionRevision, revision + 1)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testAsyncHerdOpeningFailsClosedWhenActiveStoreCannotBeResolved() async throws {
        let selectedID = UUID()
        let otherID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID), herd(otherID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()
        let revision = selection.selectionRevision

        repository.inventoryError = .unresolvedHerdStore(id: selectedID)
        do {
            try await directory.selectHerdWhenReady(id: otherID)
            XCTFail("An unsafe active Herd store must prevent opening another Herd.")
        } catch {
            XCTAssertEqual(error as? CoreDataPersistenceError, repository.inventoryError)
        }

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(selection.selectionRevision, revision + 1)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testAsyncOpeningFailsClosedWhenRootCollidesAfterReadinessCheck() async throws {
        let selectedID = UUID()
        let otherID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID), herd(otherID)])
        var pendingReadiness: CheckedContinuation<Void, Never>?
        let directory = HerdDirectoryController(
            repository: repository,
            selection: selection,
            validateReadiness: { _ in
                await withCheckedContinuation { pendingReadiness = $0 }
            }
        )
        directory.refresh()
        let revision = selection.selectionRevision

        let opening = Task { try await directory.selectHerdWhenReady(id: otherID) }
        while pendingReadiness == nil {
            await Task.yield()
        }
        repository.inventoryError = .duplicateApplicationID(
            entity: CDHerd.coreDataEntityName, id: selectedID, herdID: nil
        )
        pendingReadiness?.resume()

        do {
            try await opening.value
            XCTFail("An import collision after readiness must invalidate the active Herd.")
        } catch {
            XCTAssertEqual(error as? CoreDataPersistenceError, repository.inventoryError)
        }
        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(selection.selectionRevision, revision + 1)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testCreateHerdPreflightFailsClosedWhenActiveRootIdentityCollides() async throws {
        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()

        repository.inventoryError = .duplicateApplicationID(
            entity: CDHerd.coreDataEntityName, id: selectedID, herdID: nil
        )
        do {
            _ = try await directory.createOwnedHerd(named: "Must Not Create")
            XCTFail("An unsafe inventory must not start a Herd creation.")
        } catch {
            XCTAssertEqual(error as? CoreDataPersistenceError, repository.inventoryError)
        }

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(repository.createInvocationCount, 0)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testDuplicateSelectedHerdRootInvalidatesSelectionWithoutErasingPreference() throws {
        let suite = "stage3-duplicate-root-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
        selection.select(selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()
        let previousRevision = selection.selectionRevision

        // CloudKit imports a second root with the same application UUID.
        repository.inventoryError = .duplicateApplicationID(
            entity: CDHerd.coreDataEntityName, id: selectedID, herdID: nil
        )
        directory.refresh(reportErrors: false)

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(selection.selectionRevision, previousRevision + 1)
        XCTAssertEqual(defaults.string(forKey: "selected"), selectedID.uuidString)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
        XCTAssertNil(directory.errorMessage)

        // A successful later inventory does not silently reactivate an unverified root.
        repository.inventoryError = nil
        directory.refresh(reportErrors: false)
        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(directory.herds.map(\.id), [selectedID])
    }

    func testUnresolvedSelectedHerdStoreInvalidatesSelection() {
        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()

        repository.inventoryError = .unresolvedHerdStore(id: selectedID)
        directory.refresh(reportErrors: false)

        XCTAssertNil(directory.selectedHerdID)
        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testOtherHerdCollisionDoesNotInvalidateSelectedHerd() {
        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()

        repository.inventoryError = .duplicateApplicationID(
            entity: CDHerd.coreDataEntityName, id: UUID(), herdID: nil
        )
        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.selectedHerdID, selectedID)
        XCTAssertEqual(directory.herds.map(\.id), [selectedID])
    }

    func testRefreshInvalidatesSelectedHerdWhoseStoreOwnershipChanges() async throws {
        for originalCategory: AccessibleHerd.Category in [.owned, .shared] {
            let suite = "stage3-store-ownership-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let selectedID = UUID()
            let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
            let original = AccessibleHerd(
                summary: herd(selectedID).summary,
                category: originalCategory
            )
            // A shared Herd is only a valid active selection after explicit
            // store-qualified selection; a legacy UUID alone represents owned.
            try selection.selectAccessibleHerd(selectedID, from: [original])
            let repository = StubHerdRepository(available: [original])
            let directory = HerdDirectoryController(repository: repository, selection: selection)

            directory.refresh()
            let originalRevision = selection.selectionRevision
            let replacement = AccessibleHerd(
                summary: original.summary,
                category: originalCategory == .owned ? .shared : .owned
            )
            repository.available = [replacement]

            directory.refresh(reportErrors: false)

            XCTAssertNil(directory.selectedHerdID)
            XCTAssertEqual(selection.selectionRevision, originalRevision + 1)
            XCTAssertEqual(defaults.string(forKey: "selected"), selectedID.uuidString)
            XCTAssertEqual(directory.herds.first?.category, replacement.category)
            XCTAssertEqual(directory.inventoryState, .available)

            // Only a new explicit opening may activate the replacement root.
            try await directory.selectHerdWhenReady(id: selectedID)
            XCTAssertEqual(directory.selectedHerdID, selectedID)
        }
    }

    func testRefreshInvalidatesSameStoreReplacementBeforeOpeningItsRecords() async throws {
        for category: AccessibleHerd.Category in [.owned, .shared] {
            let suite = "stage3-root-replacement-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let selectedID = UUID()
            let original = AccessibleHerd(
                summary: herd(selectedID).summary,
                category: category
            )
            let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
            try selection.selectAccessibleHerd(selectedID, from: [original])
            let repository = StubHerdRepository(available: [original])
            let directory = HerdDirectoryController(repository: repository, selection: selection)
            directory.refresh()
            let originalRevision = selection.selectionRevision

            // A revoked or replaced root can reuse an application UUID and
            // store category, but it is not the previously opened Herd.
            let replacement = AccessibleHerd(
                summary: HerdSummary(
                    publicID: selectedID,
                    name: "Replacement Herd",
                    createdAt: original.summary.createdAt.addingTimeInterval(60),
                    updatedAt: original.summary.updatedAt.addingTimeInterval(60)
                ),
                category: category
            )
            repository.available = [replacement]

            directory.refresh(reportErrors: false)

            XCTAssertNil(directory.selectedHerdID)
            XCTAssertEqual(selection.selectionRevision, originalRevision + 1)
            XCTAssertEqual(defaults.string(forKey: "selected"), selectedID.uuidString)
            XCTAssertEqual(directory.herds, [replacement])

            // The replacement remains discoverable, but may only become
            // active after a fresh explicit readiness-checked opening.
            try await directory.selectHerdWhenReady(id: selectedID)
            XCTAssertEqual(directory.selectedHerdID, selectedID)
        }
    }

    func testRefreshPreservesSelectedHerdAfterSameStoreRename() {
        let selectedID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let original = herd(selectedID)
        let repository = StubHerdRepository(available: [original])
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.refresh()
        let originalRevision = selection.selectionRevision
        repository.available = [
            AccessibleHerd(
                summary: HerdSummary(
                    publicID: selectedID,
                    name: "Renamed Herd",
                    createdAt: original.summary.createdAt,
                    updatedAt: original.summary.updatedAt.addingTimeInterval(1)
                ),
                category: original.category
            )
        ]

        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.selectedHerdID, selectedID)
        XCTAssertEqual(selection.selectionRevision, originalRevision)
        XCTAssertEqual(directory.herds.first?.name, "Renamed Herd")
    }

    func testInitialInventoryFailureIsNotReportedAsAConfirmedEmptyInventory() {
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository()
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        XCTAssertEqual(directory.inventoryState, .loading)

        repository.shouldFail = true
        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertTrue(directory.herds.isEmpty)
        XCTAssertNil(directory.errorMessage)
        XCTAssertNil(directory.selectedHerdID)

        repository.shouldFail = false
        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.inventoryState, .available)
        XCTAssertTrue(directory.herds.isEmpty)
    }

    func testFailedInventoryPreflightCannotCreateAnotherHerd() async throws {
        let selection = AppCurrentHerdSelection()
        let repository = StubHerdRepository()
        repository.createdHerd = herd(UUID())
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        repository.shouldFail = true
        do {
            _ = try await directory.createOwnedHerd(named: "Unexpected Herd")
            XCTFail("An unreadable inventory must not permit new Herd creation.")
        } catch let error as HerdRepositoryError {
            XCTAssertEqual(error, .missingHerd)
        }

        XCTAssertEqual(directory.inventoryState, .unavailable)
        XCTAssertEqual(repository.createInvocationCount, 0)
        XCTAssertNil(directory.selectedHerdID)
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

    func testSelectionRoundTripCannotReactivateObsoleteHerdCreation() async throws {
        let originalID = UUID()
        let otherID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(available: [herd(originalID), herd(otherID)])
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let creation = Task { try await directory.createOwnedHerd(named: "New Herd") }
        await repository.waitForPendingCreation()
        try directory.selectHerd(id: otherID)
        try directory.selectHerd(id: originalID)
        repository.completeCreation()

        let created = try await creation.value
        XCTAssertEqual(created.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, originalID)
        XCTAssertEqual(Set(directory.herds.map(\.id)), [originalID, otherID, createdID])
    }

    func testSelectionRoundTripCancelsObsoleteHerdReadinessCheck() async throws {
        let originalID = UUID()
        let otherID = UUID()
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(
            available: [herd(originalID), herd(otherID), herd(pendingID)]
        )
        var pendingReadiness: CheckedContinuation<Void, Never>?
        let directory = HerdDirectoryController(
            repository: repository,
            selection: selection,
            validateReadiness: { _ in
                await withCheckedContinuation { pendingReadiness = $0 }
            }
        )

        let opening = Task { try await directory.selectHerdWhenReady(id: pendingID) }
        while pendingReadiness == nil {
            await Task.yield()
        }
        try directory.selectHerd(id: otherID)
        try directory.selectHerd(id: originalID)
        pendingReadiness?.resume()

        do {
            try await opening.value
            XCTFail("An obsolete readiness check must not change the active Herd.")
        } catch is CancellationError {
            // The user's newer selection takes precedence.
        }
        XCTAssertEqual(directory.selectedHerdID, originalID)
    }

    func testDirectSelectionRoundTripCannotReactivateObsoleteCreation() async throws {
        let originalID = UUID()
        let otherID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(available: [herd(originalID), herd(otherID)])
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let creation = Task { try await directory.createOwnedHerd(named: "New Herd") }
        await repository.waitForPendingCreation()

        // External callers use the authoritative selection rather than the
        // directory, so the directory's own generation does not change.
        selection.select(otherID)
        selection.select(originalID)
        repository.completeCreation()

        let created = try await creation.value
        XCTAssertEqual(created.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, originalID)
        XCTAssertEqual(Set(directory.herds.map(\.id)), [originalID, otherID, createdID])
    }

    func testDirectSelectionRoundTripCancelsObsoleteReadinessCheck() async throws {
        let originalID = UUID()
        let otherID = UUID()
        let pendingID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(
            available: [herd(originalID), herd(otherID), herd(pendingID)]
        )
        var pendingReadiness: CheckedContinuation<Void, Never>?
        let directory = HerdDirectoryController(
            repository: repository,
            selection: selection,
            validateReadiness: { _ in
                await withCheckedContinuation { pendingReadiness = $0 }
            }
        )

        let opening = Task { try await directory.selectHerdWhenReady(id: pendingID) }
        while pendingReadiness == nil {
            await Task.yield()
        }
        selection.select(otherID)
        selection.select(originalID)
        pendingReadiness?.resume()

        do {
            try await opening.value
            XCTFail("An obsolete readiness check must not overwrite a newer selection.")
        } catch is CancellationError {
            // The newer selection wins, even when its UUID matches the original.
        }
        XCTAssertEqual(directory.selectedHerdID, originalID)
    }

    func testReadinessDoesNotActivateDifferentStoreOwnershipForSameHerdID() async throws {
        for originalCategory: AccessibleHerd.Category in [.owned, .shared] {
            let activeID = UUID()
            let candidateID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: activeID)
            let candidate = AccessibleHerd(
                summary: herd(candidateID).summary,
                category: originalCategory
            )
            let repository = StubHerdRepository(available: [herd(activeID), candidate])
            var pendingReadiness: CheckedContinuation<Void, Never>?
            let directory = HerdDirectoryController(
                repository: repository,
                selection: selection,
                validateReadiness: { _ in
                    await withCheckedContinuation { pendingReadiness = $0 }
                }
            )

            let opening = Task { try await directory.selectHerdWhenReady(id: candidateID) }
            while pendingReadiness == nil {
                await Task.yield()
            }

            // The old root disappears while its graph is being validated. A
            // different store now exposes the same application UUID.
            repository.available = [
                herd(activeID),
                AccessibleHerd(
                    summary: candidate.summary,
                    category: originalCategory == .owned ? .shared : .owned
                )
            ]
            pendingReadiness?.resume()

            do {
                try await opening.value
                XCTFail("Readiness for one store must not activate another store's Herd.")
            } catch is CancellationError {
                // A fresh readiness check is required for the replacement root.
            }
            XCTAssertEqual(directory.selectedHerdID, activeID)
        }
    }

    func testReadinessDoesNotActivateReplacementRootInSameStoreCategory() async throws {
        for category: AccessibleHerd.Category in [.owned, .shared] {
            let activeID = UUID()
            let candidateID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: activeID)
            let candidate = AccessibleHerd(
                summary: herd(candidateID).summary,
                category: category
            )
            let repository = StubHerdRepository(available: [herd(activeID), candidate])
            var pendingReadiness: CheckedContinuation<Void, Never>?
            let directory = HerdDirectoryController(
                repository: repository,
                selection: selection,
                validateReadiness: { _ in
                    await withCheckedContinuation { pendingReadiness = $0 }
                }
            )

            let opening = Task { try await directory.selectHerdWhenReady(id: candidateID) }
            while pendingReadiness == nil {
                await Task.yield()
            }

            let originalRevision = selection.selectionRevision
            // A revoked/imported root can be replaced before the readiness
            // probe completes, even when its UUID and store category match.
            repository.available = [
                herd(activeID),
                AccessibleHerd(
                    summary: HerdSummary(
                        publicID: candidateID,
                        name: "Replacement",
                        createdAt: candidate.summary.createdAt.addingTimeInterval(60),
                        updatedAt: candidate.summary.updatedAt.addingTimeInterval(60)
                    ),
                    category: category
                )
            ]
            pendingReadiness?.resume()

            do {
                try await opening.value
                XCTFail("The replacement root must receive its own readiness check.")
            } catch is CancellationError {
                // An obsolete readiness result cannot authorize the replacement.
            }
            XCTAssertEqual(directory.selectedHerdID, activeID)
            XCTAssertEqual(selection.selectionRevision, originalRevision)

            // The replacement remains discoverable for an explicit new
            // opening; only the stale readiness result is discarded.
            directory.refresh(reportErrors: false)
            XCTAssertEqual(directory.herds.first { $0.id == candidateID }?.name, "Replacement")
        }
    }

    func testReadinessStillOpensSameStoreHerdAfterRemoteRename() async throws {
        let activeID = UUID()
        let candidateID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: activeID)
        let candidate = AccessibleHerd(
            summary: herd(candidateID).summary,
            category: .shared
        )
        let repository = StubHerdRepository(available: [herd(activeID), candidate])
        var pendingReadiness: CheckedContinuation<Void, Never>?
        let directory = HerdDirectoryController(
            repository: repository,
            selection: selection,
            validateReadiness: { _ in
                await withCheckedContinuation { pendingReadiness = $0 }
            }
        )

        let opening = Task { try await directory.selectHerdWhenReady(id: candidateID) }
        while pendingReadiness == nil {
            await Task.yield()
        }
        repository.available = [
            herd(activeID),
            AccessibleHerd(
                summary: HerdSummary(
                    publicID: candidateID,
                    name: "Updated Name",
                    createdAt: candidate.summary.createdAt,
                    updatedAt: candidate.summary.updatedAt.addingTimeInterval(1)
                ),
                category: .shared
            )
        ]
        pendingReadiness?.resume()

        try await opening.value
        XCTAssertEqual(directory.selectedHerdID, candidateID)
        XCTAssertEqual(directory.herds.first { $0.id == candidateID }?.name, "Updated Name")
    }

    func testCommittedCreationIsNotReportedAsFailedWhenInventoryRefreshThrows() async throws {
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
        // The new root has committed, but the follow-up inventory read fails.
        repository.shouldFail = true
        repository.completeCreation()

        let created = try await creation.value
        XCTAssertEqual(created.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, selectedID)
        XCTAssertTrue(directory.errorMessage?.contains("was created") == true)
        XCTAssertTrue(directory.errorMessage?.contains("Refresh") == true)

        repository.shouldFail = false
        directory.refresh()
        try directory.selectHerd(id: createdID)
        XCTAssertEqual(directory.selectedHerdID, createdID)
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

    func testConcurrentCreateIsRejectedBeforeSecondRepositoryWrite() async throws {
        let selectedID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = StubHerdRepository(available: [herd(selectedID)])
        repository.createdHerd = herd(createdID)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        let firstCreation = Task { try await directory.createOwnedHerd(named: "First") }
        await repository.waitForPendingCreation()

        do {
            _ = try await directory.createOwnedHerd(named: "Second")
            XCTFail("Only one Create Herd transaction may be in progress.")
        } catch let error as HerdDirectoryError {
            XCTAssertEqual(error, .creationInProgress)
        } catch {
            XCTFail("Expected the directory's in-progress error, received: \(error)")
        }
        XCTAssertEqual(repository.createInvocationCount, 1)

        repository.completeCreation()
        let result = try await firstCreation.value
        XCTAssertEqual(result.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, createdID)
        XCTAssertEqual(repository.createInvocationCount, 1)
    }

    func testCreateGuardReleasesAfterRepositoryFailure() async throws {
        let originalID = UUID()
        let createdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let repository = StubHerdRepository(available: [herd(originalID)])
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        do {
            _ = try await directory.createOwnedHerd(named: "Failed")
            XCTFail("Expected the repository failure.")
        } catch let error as HerdRepositoryError {
            XCTAssertEqual(error, .missingHerd)
        }
        repository.createdHerd = herd(createdID)
        let retry = Task { try await directory.createOwnedHerd(named: "Retry") }
        await repository.waitForPendingCreation()
        repository.completeCreation()

        let result = try await retry.value
        XCTAssertEqual(result.id, createdID)
        XCTAssertEqual(directory.selectedHerdID, createdID)
        XCTAssertEqual(repository.createInvocationCount, 2)
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
        var hasIncompleteRoots = false
        var inventoryError: CoreDataPersistenceError?
        var createdHerd: AccessibleHerd?
        var createInvocationCount = 0
        private var pendingCreation: CheckedContinuation<HerdSummary, Never>?

        init(available: [AccessibleHerd] = []) {
            self.available = available
        }

        func fetchCurrentHerd() throws -> HerdSummary {
            throw HerdRepositoryError.missingHerd
        }

        func fetchAccessibleHerds() throws -> [AccessibleHerd] {
            if let inventoryError { throw inventoryError }
            if shouldFail { throw HerdRepositoryError.missingHerd }
            return available
        }

        func fetchHerdInventory() throws -> HerdInventory {
            HerdInventory(herds: try fetchAccessibleHerds(), hasIncompleteRoots: hasIncompleteRoots)
        }

        func createOwnedHerd(named name: String) async throws -> HerdSummary {
            createInvocationCount += 1
            guard createdHerd != nil, pendingCreation == nil else {
                throw HerdRepositoryError.missingHerd
            }
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

@MainActor
final class HerdDirectoryOpeningStateTests: XCTestCase {
    func testCancelledImportAttemptImmediatelyAllowsAnotherHerdToOpen() throws {
        var state = HerdDirectoryOpeningState()
        let original = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.isOpening)

        state.cancel()

        XCTAssertFalse(state.isOpening)
        let replacement = try XCTUnwrap(state.begin())
        XCTAssertNotEqual(original, replacement)
        XCTAssertTrue(state.isCurrent(replacement))

        // The canceled validation can finish after the replacement starts.
        XCTAssertFalse(state.finish(original))
        XCTAssertTrue(state.isCurrent(replacement))
        XCTAssertTrue(state.isOpening)

        XCTAssertTrue(state.finish(replacement))
        XCTAssertFalse(state.isOpening)
    }

    func testOnlyActiveAttemptCanCompleteAndReleaseChooser() throws {
        var state = HerdDirectoryOpeningState()
        let active = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertFalse(state.finish(UUID()))
        XCTAssertTrue(state.isOpening)

        XCTAssertTrue(state.finish(active))
        XCTAssertFalse(state.isOpening)
        XCTAssertNotNil(state.begin())
    }
}
