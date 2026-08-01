import XCTest

@testable import yaHerd

extension HerdSharingBridgeReliabilityTests {
  func testMissingAcceptedHerdSnapshotMapsToPendingSyncImportFailure() {
    let mappedError = HerdSharingCoreDataStore.importBoundaryError(
      HerdSharingBridgeSnapshotError.missingHerdRecord(nil),
      requestedHerd: nil,
      sourceDescription: "accepted shared store"
    )

    XCTAssertEqual(
      mappedError as? HerdSharingActionError,
      .bridgeImportFailed(
        "No accepted shared herd records were found in the Core Data sharing bridge."
      )
    )
  }

  func testOtherSnapshotErrorsRemainSnapshotErrorsAtImportBoundary() {
    let mappedError = HerdSharingCoreDataStore.importBoundaryError(
      HerdSharingBridgeSnapshotError.missingEntityName,
      requestedHerd: nil,
      sourceDescription: "accepted shared store"
    )

    guard let snapshotError = mappedError as? HerdSharingBridgeSnapshotError else {
      return XCTFail("Expected the original snapshot error to remain unchanged.")
    }
    guard case .missingEntityName = snapshotError else {
      return XCTFail("Expected missingEntityName, received \(snapshotError).")
    }
  }
}
