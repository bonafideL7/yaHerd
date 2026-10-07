import CoreData
import XCTest
@testable import yaHerd

final class CoreDataAppHerdBootstrapperTests: XCTestCase {
    func testBootstrapCreatesOneLocalHerdAndReusesItsApplicationID() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        let createdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp
        )
        let resolvedID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp.addingTimeInterval(60)
        )

        XCTAssertEqual(resolvedID, createdID)

        let context = assembly.contextFactory.makeReadContext()
        let herds = try context.performAndWait {
            try context.fetch(
                NSFetchRequest<CDHerd>(
                    entityName: CDHerd.coreDataEntityName
                )
            )
        }

        XCTAssertEqual(herds.count, 1)
        XCTAssertEqual(herds.first?.id, createdID)
        XCTAssertEqual(herds.first?.name, CoreDataAppHerdBootstrapper.defaultHerdName)
        XCTAssertEqual(herds.first?.createdAt, timestamp)
        XCTAssertEqual(herds.first?.updatedAt, timestamp)
    }

    func testBootstrapRejectsAmbiguousMultipleHerdRootsAndReportsActualCount() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()

        try await assembly.transactionExecutor.performWrite { context in
            for index in 0..<3 {
                let herd = CDHerd(context: context)
                herd.id = UUID()
                herd.name = "Herd \(index)"
                herd.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
                herd.updatedAt = herd.createdAt
            }
        }

        do {
            _ = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
                assembly: assembly
            )
            XCTFail("Expected multiple-herd bootstrap failure")
        } catch let error as CoreDataAppHerdBootstrapError {
            XCTAssertEqual(error, .multipleLocalHerds(count: 3))
        }
    }

    @MainActor
    func testAppCurrentHerdSelectionExposesOnlyTheSelectedApplicationID() {
        let firstID = UUID()
        let secondID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)

        XCTAssertEqual(selection.currentHerdID, firstID)

        selection.select(secondID)
        XCTAssertEqual(selection.currentHerdID, secondID)

        selection.select(nil)
        XCTAssertNil(selection.currentHerdID)
    }
}
