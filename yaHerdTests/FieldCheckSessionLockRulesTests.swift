import XCTest
@testable import yaHerd

final class FieldCheckSessionLockRulesTests: XCTestCase {
    func testSessionIsEditableOnlyWhenItIsNotCompleted() {
        XCTAssertTrue(FieldCheckSessionLockRules.isEditable(completedAt: nil))
        XCTAssertFalse(FieldCheckSessionLockRules.isEditable(completedAt: Date(timeIntervalSince1970: 0)))
    }
}
