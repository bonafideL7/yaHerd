import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckSessionLockRulesTests: XCTestCase {
    func testSessionDataIsEditableOnlyWhenItIsNotCompleted() {
        XCTAssertTrue(FieldCheckSessionLockRules.canEditSessionData(completedAt: nil))
        XCTAssertFalse(FieldCheckSessionLockRules.canEditSessionData(completedAt: Date(timeIntervalSince1970: 0)))
    }

    func testFindingStatusCanBeUpdatedAfterCompletion() {
        XCTAssertTrue(FieldCheckSessionLockRules.canUpdateFindingStatus(completedAt: nil))
        XCTAssertTrue(FieldCheckSessionLockRules.canUpdateFindingStatus(completedAt: Date(timeIntervalSince1970: 0)))
    }
}
