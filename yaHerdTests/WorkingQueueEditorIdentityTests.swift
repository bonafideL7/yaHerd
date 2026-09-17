import Foundation
import XCTest
@testable import yaHerd

final class WorkingQueueEditorIdentityTests: XCTestCase {
    func testChangedSourcePastureRequiresReviewWhenUsingSourcePasture() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testRemovedSourcePastureRequiresReviewWhenUsingSourcePasture() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: nil
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testChangedSourcePasturePreservesExplicitDestinationSelection() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertFalse(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: UUID()
            )
        )
    }

    func testMissingSourcePastureBaselineRequiresReviewWhenUsingSourcePasture() {
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "Current"
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: nil,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testSourcePastureRenameDoesNotRequireReviewWhenIdentityIsStable() {
        let id = UUID()
        let presented = WorkingQueueEditorSourcePastureReference(
            id: id,
            name: "Old Name"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: id,
            name: "New Name"
        )

        XCTAssertFalse(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testAvailableSourcePastureCanBeUsed() {
        XCTAssertTrue(
            WorkingQueueEditorIdentity.canUseSourcePasture(
                WorkingQueueEditorSourcePastureReference(
                    id: UUID(),
                    name: "North"
                )
            )
        )
    }

    func testRemovedSourcePastureCannotBeUsed() {
        XCTAssertFalse(
            WorkingQueueEditorIdentity.canUseSourcePasture(
                WorkingQueueEditorSourcePastureReference(
                    id: nil,
                    name: nil
                )
            )
        )
    }

    func testUnverifiedSourcePastureCannotBeUsed() {
        XCTAssertFalse(
            WorkingQueueEditorIdentity.canUseSourcePasture(nil)
        )
    }

    func testPersistedCurrentSourceNormalizesToSourceSelection() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "North"
        )

        XCTAssertNil(
            WorkingQueueEditorIdentity.destinationPastureSelection(
                persistedDestinationPastureID: sourceID,
                sourcePasture: source
            )
        )
    }

    func testPersistedOldSourceRemainsExplicitWhenSessionSourceChanges() {
        let oldSourceID = UUID()
        let currentSource = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureSelection(
                persistedDestinationPastureID: oldSourceID,
                sourcePasture: currentSource
            ),
            oldSourceID
        )
    }

    func testSourcePastureSelectionSavesExactPresentedSourceIdentity() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "North"
        )

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureIDForSave(
                selectedDestinationPastureID: nil,
                sourcePasture: source
            ),
            sourceID
        )
    }

    func testExplicitDestinationOverridesSourcePastureForSave() {
        let source = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let destinationID = UUID()

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureIDForSave(
                selectedDestinationPastureID: destinationID,
                sourcePasture: source
            ),
            destinationID
        )
    }
}
