import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingCoreDataModelCachingTests: XCTestCase {
    func testCurrentBridgeModelIsReusedAcrossSnapshotRecords() {
        let firstModel = HerdSharingCoreDataModelFactory.makeCurrentModel()
        let secondModel = HerdSharingCoreDataModelFactory.makeCurrentModel()

        XCTAssertTrue(firstModel === secondModel)
    }
}
