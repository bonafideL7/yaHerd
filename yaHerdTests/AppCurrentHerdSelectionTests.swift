import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AppCurrentHerdSelectionTests: XCTestCase {
    private func herd(_ id: UUID) -> AccessibleHerd {
        AccessibleHerd(
            summary: HerdSummary(
                publicID: id, name: "Herd",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            category: .owned
        )
    }

    func testRestoresSavedHerdWithoutArbitrarilySelectingAnother() throws {
        let suite = "stage3-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let idA = UUID()
        let idB = UUID()
        defaults.set(idB.uuidString, forKey: "selected")

        let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
        selection.restoreAccessibleHerd(from: [herd(idA), herd(idB)])
        XCTAssertEqual(selection.currentHerdID, idB)

        selection.restoreAccessibleHerd(from: [herd(idA), herd(UUID())])
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)

        // A single different available Herd must not override the remembered ID.
        selection.restoreAccessibleHerd(from: [herd(idA)])
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)

        // A temporarily empty import must not erase a previously chosen ID.
        selection.restoreAccessibleHerd(from: [])
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)

        selection.restoreAccessibleHerd(from: [herd(idA), herd(idB)])
        XCTAssertEqual(selection.currentHerdID, idB)
    }

    func testSoleAccessibleHerdIsRememberedWithoutAStoredPreference() throws {
        let suite = "stage3-singleton-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )

        selection.restoreAccessibleHerd(from: [herd(id)])

        XCTAssertEqual(selection.currentHerdID, id)
        XCTAssertEqual(defaults.string(forKey: "selected"), id.uuidString)

        // A newly launched app must restore the original selection even if
        // another Herd became available since the first launch.
        let restored = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )
        restored.restoreAccessibleHerd(from: [herd(id), herd(UUID())])
        XCTAssertEqual(restored.currentHerdID, id)
        XCTAssertEqual(defaults.string(forKey: "selected"), id.uuidString)
    }

    func testRememberedHerdDoesNotRestoreFromDifferentStoreAfterRelaunch() throws {
        for originalCategory: AccessibleHerd.Category in [.owned, .shared] {
            let suite = "stage3-category-restore-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let herdID = UUID()
            let original = AccessibleHerd(
                summary: herd(herdID).summary,
                category: originalCategory
            )
            let replacement = AccessibleHerd(
                summary: original.summary,
                category: originalCategory == .owned ? .shared : .owned
            )
            let selection = AppCurrentHerdSelection(
                defaults: defaults, preferenceKey: "selected"
            )
            try selection.selectAccessibleHerd(herdID, from: [original])

            let relaunched = AppCurrentHerdSelection(
                defaults: defaults, preferenceKey: "selected"
            )
            relaunched.restoreAccessibleHerd(from: [replacement])
            XCTAssertNil(relaunched.currentHerdID)
            XCTAssertEqual(defaults.string(forKey: "selected"), herdID.uuidString)

            // Explicit opening updates the expected store category.
            try relaunched.selectAccessibleHerd(herdID, from: [replacement])
            let reopened = AppCurrentHerdSelection(
                defaults: defaults, preferenceKey: "selected"
            )
            reopened.restoreAccessibleHerd(from: [replacement])
            XCTAssertEqual(reopened.currentHerdID, herdID)
        }
    }

    func testActiveHerdRestorationRejectsStoreCategoryReplacement() throws {
        for originalCategory: AccessibleHerd.Category in [.owned, .shared] {
            let suite = "stage3-active-category-restore-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let herdID = UUID()
            let original = AccessibleHerd(
                summary: herd(herdID).summary,
                category: originalCategory
            )
            let replacement = AccessibleHerd(
                summary: original.summary,
                category: originalCategory == .owned ? .shared : .owned
            )
            let selection = AppCurrentHerdSelection(
                defaults: defaults, preferenceKey: "selected"
            )
            try selection.selectAccessibleHerd(herdID, from: [original])
            let revision = selection.selectionRevision
            if originalCategory == .shared {
                // A legacy persisted UUID may use lowercase hex characters.
                defaults.set(herdID.uuidString.lowercased(), forKey: "selected")
            }

            // An active UUID is not proof that its owning store is unchanged.
            selection.restoreAccessibleHerd(from: [replacement])

            XCTAssertNil(selection.currentHerdID)
            XCTAssertEqual(selection.selectionRevision, revision + 1)
            XCTAssertEqual(
                UUID(uuidString: defaults.string(forKey: "selected") ?? ""),
                herdID
            )
            XCTAssertEqual(
                defaults.string(forKey: "selected.storeCategory"),
                originalCategory == .owned ? "owned" : "shared"
            )

            try selection.selectAccessibleHerd(herdID, from: [replacement])
            XCTAssertEqual(selection.currentHerdID, herdID)
        }
    }

    func testActiveHerdRestorationPreservesSameStoreIdentity() throws {
        let suite = "stage3-active-same-store-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let herdID = UUID()
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )
        try selection.selectAccessibleHerd(herdID, from: [herd(herdID)])
        let revision = selection.selectionRevision

        selection.restoreAccessibleHerd(from: [herd(herdID)])

        XCTAssertEqual(selection.currentHerdID, herdID)
        XCTAssertEqual(selection.selectionRevision, revision)
    }

    func testRestorationAcceptsLowercaseRememberedUUID() throws {
        let suite = "stage3-case-insensitive-restore-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let herdID = UUID()
        defaults.set(herdID.uuidString.lowercased(), forKey: "selected")
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )

        selection.restoreAccessibleHerd(from: [herd(herdID), herd(UUID())])

        XCTAssertEqual(selection.currentHerdID, herdID)
    }

    func testRestorationDoesNotSelectAmbiguousRememberedUUID() throws {
        let suite = "stage3-duplicate-restore-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let herdID = UUID()
        defaults.set(herdID.uuidString, forKey: "selected")
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )

        selection.restoreAccessibleHerd(from: [herd(herdID), herd(herdID)])

        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), herdID.uuidString)
    }

    func testExplicitSameIDStoreReplacementResetsSelectionRevision() throws {
        let suite = "stage3-same-id-store-switch-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let selectedID = UUID()
        let original = herd(selectedID)
        let replacement = AccessibleHerd(
            summary: original.summary,
            category: .shared
        )
        let selection = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )
        try selection.selectAccessibleHerd(selectedID, from: [original])
        let firstRevision = selection.selectionRevision

        // Reopening the same UUID from another store must invalidate the
        // old Herd's routes and drafts, even without an intervening refresh.
        try selection.selectAccessibleHerd(selectedID, from: [replacement])
        XCTAssertEqual(selection.currentHerdID, selectedID)
        XCTAssertGreaterThan(selection.selectionRevision, firstRevision)

        let relaunched = AppCurrentHerdSelection(
            defaults: defaults, preferenceKey: "selected"
        )
        relaunched.restoreAccessibleHerd(from: [replacement])
        XCTAssertEqual(relaunched.currentHerdID, selectedID)
    }

    func testSelectingAccessibleHerdPersistsAndRejectsUnknownIdentity() throws {
        let suite = "stage3-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let idA = UUID()
        let idB = UUID()
        let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")

        try selection.selectAccessibleHerd(idA, from: [herd(idA), herd(idB)])
        XCTAssertEqual(selection.currentHerdID, idA)
        XCTAssertEqual(defaults.string(forKey: "selected"), idA.uuidString)

        XCTAssertThrowsError(try selection.selectAccessibleHerd(UUID(), from: [herd(idA), herd(idB)])) {
            XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
        }
        XCTAssertEqual(selection.currentHerdID, idA)

        try selection.selectAccessibleHerd(idB, from: [herd(idA), herd(idB)])
        XCTAssertEqual(selection.currentHerdID, idB)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)

        selection.select(nil)
        XCTAssertNil(selection.currentHerdID)
        XCTAssertNil(defaults.string(forKey: "selected"))
    }

    func testExplicitSelectionWinsOverStoredPreference() throws {
        let suite = "stage3-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let explicitID = UUID()
        let storedID = UUID()
        defaults.set(storedID.uuidString, forKey: "selected")
        defaults.set("shared", forKey: "selected.storeCategory")
        let selection = AppCurrentHerdSelection(
            currentHerdID: explicitID, defaults: defaults, preferenceKey: "selected"
        )
        selection.restoreAccessibleHerd(from: [herd(explicitID), herd(storedID)])
        XCTAssertEqual(selection.currentHerdID, explicitID)
    }

    func testDuplicateInventoryIdentityCannotBeSelected() {
        let id = UUID()
        let selection = AppCurrentHerdSelection()
        XCTAssertThrowsError(try selection.selectAccessibleHerd(id, from: [herd(id), herd(id)])) {
            XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
        }
        XCTAssertNil(selection.currentHerdID)
    }

    func testPendingImportDoesNotEraseRememberedHerdOrSilentlySelectAnother() throws {
        let suite = "stage3-import-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importedID = UUID()
        let otherID = UUID()
        let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
        selection.select(importedID)

        // The remembered Herd's root is present, but its related records are
        // not ready. The chooser must be accessible without forgetting the ID.
        selection.deferCurrentHerdUntilImportReady()
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), importedID.uuidString)

        // Choosing a different accessible Herd is an explicit preference change.
        try selection.selectAccessibleHerd(otherID, from: [herd(importedID), herd(otherID)])
        XCTAssertEqual(selection.currentHerdID, otherID)
        XCTAssertEqual(defaults.string(forKey: "selected"), otherID.uuidString)
    }
}
