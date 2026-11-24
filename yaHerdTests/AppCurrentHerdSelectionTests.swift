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
            category: .owned, rootIdentity: testHerdRootIdentity(id)
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

        selection.revalidateActiveHerd(from: [herd(idA), herd(UUID())])
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)

        // A temporarily empty import must not erase a previously chosen ID.
        selection.revalidateActiveHerd(from: [])
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

        selection.deferCurrentHerdUntilImportReady()
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(defaults.string(forKey: "selected"), idB.uuidString)
    }

    func testExplicitSelectionWinsOverStoredPreference() throws {
        let suite = "stage3-selection-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let explicitID = UUID()
        let storedID = UUID()
        defaults.set(storedID.uuidString, forKey: "selected")
        let selection = AppCurrentHerdSelection(defaults: defaults, preferenceKey: "selected")
        try selection.selectAccessibleHerd(explicitID, from: [herd(explicitID), herd(storedID)], remember: false)
        XCTAssertEqual(defaults.string(forKey: "selected"), storedID.uuidString)
        XCTAssertEqual(selection.currentHerdID, explicitID)
    }

    func testReplacementRootWithSameApplicationIDInvalidatesSelectionAndCannotRestoreOldPreference() throws {
        let suite = "stage3-replacement-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = herd(id)
        let replacement = AccessibleHerd(summary: original.summary, category: .owned,
                                         rootIdentity: testHerdRootIdentity(UUID()))
        let selection = AppCurrentHerdSelection(defaults: defaults)
        try selection.selectAccessibleHerd(id, from: [original])
        let revision = selection.selectionRevision
        selection.revalidateActiveHerd(from: [replacement])
        XCTAssertNil(selection.currentHerdID)
        XCTAssertGreaterThan(selection.selectionRevision, revision)
        XCTAssertNil(selection.rememberedAccessibleHerd(from: [replacement]))
        selection.restoreAccessibleHerd(from: [original])
        XCTAssertEqual(selection.selectedRootIdentity, original.rootIdentity)
    }

    func testDuplicateInventoryIdentityCannotBeSelected() {
        let id = UUID()
        let selection = AppCurrentHerdSelection()
        XCTAssertThrowsError(try selection.selectAccessibleHerd(id, from: [herd(id), herd(id)])) {
            XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
        }
        XCTAssertNil(selection.currentHerdID)
    }
}
