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

extension WorkingQueueEditorIdentityTests {
    func testSessionHistoricalSourceIDDoesNotBecomeUsableWhenLiveSourceIsUnavailable() {
        let historicalSourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: historicalSourceID,
            sourcePastureName: "Deleted Historical Source",
            isSourcePastureAvailable: false,
            treatmentTemplateName: "Historical Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(session: session)

        XCTAssertNil(reference.id)
        XCTAssertEqual(reference.name, "Deleted Historical Source")
        XCTAssertFalse(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }

    func testSessionLiveSourceKeepsHistoricalIdentityUsable() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Live Source",
            isSourcePastureAvailable: true,
            treatmentTemplateName: "Live Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(session: session)

        XCTAssertEqual(reference.id, sourceID)
        XCTAssertEqual(reference.name, "Live Source")
        XCTAssertTrue(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }
}

extension WorkingQueueEditorIdentityTests {
    func testInitialSelectionRequiresReviewWhenHistoricalSourceIsDeleted() {
        let historicalSourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: historicalSourceID,
            sourcePasture: source,
            historicalSourcePastureID: historicalSourceID,
            availablePastureIDs: []
        )

        XCTAssertNil(state.selection)
        XCTAssertTrue(state.requiresReview)
    }

    func testInitialSelectionKeepsLiveExplicitDestinationWhenSourceIsDeleted() {
        let destinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: destinationID,
            sourcePasture: source,
            historicalSourcePastureID: UUID(),
            availablePastureIDs: [destinationID]
        )

        XCTAssertEqual(state.selection, destinationID)
        XCTAssertFalse(state.requiresReview)
    }

    func testInitialSelectionRequiresReviewWhenExplicitDestinationWasDeleted() {
        let sourceID = UUID()
        let deletedDestinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "Live Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: deletedDestinationID,
            sourcePasture: source,
            historicalSourcePastureID: sourceID,
            availablePastureIDs: [sourceID]
        )

        XCTAssertNil(state.selection)
        XCTAssertTrue(state.requiresReview)
    }

    func testInitialSelectionNormalizesLiveSourceWithoutReview() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "Live Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: sourceID,
            sourcePasture: source,
            historicalSourcePastureID: sourceID,
            availablePastureIDs: [sourceID]
        )

        XCTAssertNil(state.selection)
        XCTAssertFalse(state.requiresReview)
    }

    func testInitialSelectionPreservesExplicitDestinationWhenReferenceDataLoadFails() {
        let historicalSourceID = UUID()
        let destinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: destinationID,
            sourcePasture: source,
            historicalSourcePastureID: historicalSourceID,
            availablePastureIDs: nil
        )

        XCTAssertEqual(state.selection, destinationID)
        XCTAssertFalse(state.requiresReview)
    }

}

extension WorkingQueueEditorIdentityTests {
    func testLiveSourceReferenceUsesCurrentPastureNameWhileKeepingHistoricalIdentity() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Historical Source Name",
            isSourcePastureAvailable: true,
            treatmentTemplateName: "Live Name",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(
            session: session,
            livePastures: [
                PastureOption(id: sourceID, name: "Current Source Name")
            ]
        )

        XCTAssertEqual(reference.id, sourceID)
        XCTAssertEqual(reference.name, "Current Source Name")
        XCTAssertEqual(session.sourcePastureName, "Historical Source Name")
    }

    func testUnavailableSourceReferenceKeepsHistoricalNameEvenWithStaleLiveOption() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Historical Deleted Source",
            isSourcePastureAvailable: false,
            treatmentTemplateName: "Deleted Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(
            session: session,
            livePastures: [
                PastureOption(id: sourceID, name: "Stale Reference Name")
            ]
        )

        XCTAssertNil(reference.id)
        XCTAssertEqual(reference.name, "Historical Deleted Source")
        XCTAssertFalse(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }
}

