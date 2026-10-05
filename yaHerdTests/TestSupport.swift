import Foundation
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
enum TestSupport {
    static func makeSchema() -> Schema {
        yaHerdApp.makeSchema()
    }

    static func makeModelContainer() throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: YaHerdMigrationPlan.self,
            configurations: [configuration]
        )
    }
}


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
