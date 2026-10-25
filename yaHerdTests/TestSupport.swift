import Foundation
import XCTest
@testable import yaHerd

@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @MainActor () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        let resolvedMessage = message()
        XCTFail(
            resolvedMessage.isEmpty ? "Expected expression to throw an error." : resolvedMessage,
            file: file,
            line: line
        )
    } catch {
        errorHandler(error)
    }
}

// Composite of the protocols implemented by the current Core Data pasture repository.
// Destructive pasture operations remain a separate awaited transaction.
typealias TestPastureRepository =
    PastureListManagingRepository &
    PastureDetailReader &
    PastureResidentAnimalReader &
    PastureReferenceDataReader &
    PastureExistenceChecking &
    PastureNameChecking &
    PastureCreating &
    PastureUpdating &
    PastureGroupListReader &
    PastureGroupDetailReader &
    PastureGroupExistenceChecking &
    PastureGroupNameChecking &
    PastureGroupCreating &
    PastureGroupUpdating &
    PastureGroupDeleting &
    PastureGroupAssignmentWriting
