import Foundation
import XCTest
@testable import yaHerd

@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
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
