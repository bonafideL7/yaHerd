import XCTest
@testable import yaHerd

final class WorkingQueueItemEditorLookupTests: XCTestCase {
    @MainActor
    func testMissingQueueItemReturnsNil() throws {
        let value: Int? = try workingQueueItemEditorLookup {
            throw WorkingRepositoryError.queueItemNotFound
        }

        XCTAssertNil(value)
    }

    @MainActor
    func testMissingSessionReturnsNil() throws {
        let value: Int? = try workingQueueItemEditorLookup {
            throw WorkingRepositoryError.sessionNotFound
        }

        XCTAssertNil(value)
    }

    @MainActor
    func testTransientReadFailureIsRethrown() {
        XCTAssertThrowsError(
            try workingQueueItemEditorLookup { () -> Int in
                throw StubWorkingQueueLookupError.readFailed
            }
        ) { error in
            XCTAssertTrue(error is StubWorkingQueueLookupError)
        }
    }

    @MainActor
    func testSuccessfulLookupReturnsValue() throws {
        let value = try workingQueueItemEditorLookup { 42 }

        XCTAssertEqual(value, 42)
    }
}

private enum StubWorkingQueueLookupError: Error {
    case readFailed
}
