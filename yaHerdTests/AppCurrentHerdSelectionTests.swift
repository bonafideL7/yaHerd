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
