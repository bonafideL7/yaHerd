import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckAnimalDetailSelectionIsolationTests: XCTestCase {
    func testOnlyOpeningSelectionMayDisplayFieldCheckAnimalDetails() {
        let openingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: openingHerdID)
        let openingRevision = selection.selectionRevision
        let model = FieldCheckAnimalDetailViewModel()

        XCTAssertTrue(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: openingHerdID,
            originatingSelectionRevision: openingRevision
        ))

        selection.select(UUID())
        XCTAssertFalse(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: openingHerdID,
            originatingSelectionRevision: openingRevision
        ))

        selection.select(openingHerdID)
        XCTAssertFalse(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: openingHerdID,
            originatingSelectionRevision: openingRevision
        ), "Returning to the same Herd must not revive a stale animal detail view.")
    }

    func testUnavailableOrUncapturedOriginMustNeverShowAnimalDetails() {
        let openingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: openingHerdID)
        let model = FieldCheckAnimalDetailViewModel()

        XCTAssertFalse(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: nil,
            originatingSelectionRevision: nil
        ))

        XCTAssertFalse(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: openingHerdID,
            originatingSelectionRevision: nil
        ))

        let openingRevision = selection.selectionRevision
        selection.select(nil)
        XCTAssertFalse(model.isOriginatingSelectionCurrent(
            selection,
            originatingHerdID: openingHerdID,
            originatingSelectionRevision: openingRevision
        ))
    }
}
