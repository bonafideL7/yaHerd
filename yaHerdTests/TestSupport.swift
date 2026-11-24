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

/// Stable store-qualified identities for tests that intentionally use a fake inventory.
func testHerdRootIdentity(_ id: UUID) -> URL {
    URL(fileURLWithPath: "/test-herds/" + id.uuidString)
}

func testAccessibleHerd(_ id: UUID, category: AccessibleHerd.Category = .owned) -> AccessibleHerd {
    AccessibleHerd(
        summary: HerdSummary(publicID: id, name: "Herd", createdAt: .distantPast, updatedAt: .distantPast),
        category: category, rootIdentity: testHerdRootIdentity(id)
    )
}
