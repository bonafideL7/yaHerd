import XCTest
@testable import yaHerd

@MainActor
final class WorkingTreatmentTemplateHerdIsolationTests: XCTestCase {
    func testStaleTemplateMutationIsRejectedAfterHerdSwitchAndReturn() throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        var mutationCount = 0

        selection.select(UUID())
        let wrongHerdResult: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(wrongHerdResult)

        selection.select(originalHerdID)
        let returnedHerdResult: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(returnedHerdResult)
        XCTAssertEqual(mutationCount, 0, "An obsolete treatment-template draft must never mutate another selection.")
    }

    func testActiveHerdTemplateMutationExecutesExactlyOnce() throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        var mutationCount = 0

        let result: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }

        XCTAssertEqual(result, 1)
        XCTAssertEqual(mutationCount, 1)
    }

    func testMissingOrRevokedHerdIdentityBlocksTemplateMutation() throws {
        let selection = AppCurrentHerdSelection()
        var mutationCount = 0

        let unselected: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: nil,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(unselected)

        let herdID = UUID()
        selection.select(herdID)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        selection.revalidateActiveHerd(from: [])

        let revoked: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(revoked)
        XCTAssertEqual(mutationCount, 0)
    }
}
