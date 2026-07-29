import XCTest
@testable import yaHerd

final class WorkingAnimalWorkTimestampTests: XCTestCase {
    func testNewWorkUsesCurrentSaveTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            WorkingAnimalWorkTimestamp.resolve(existingCompletedAt: nil, now: now),
            now
        )
    }

    func testHistoricalEditPreservesExistingCompletionTime() {
        let existing = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            WorkingAnimalWorkTimestamp.resolve(existingCompletedAt: existing, now: now),
            existing
        )
    }
}
