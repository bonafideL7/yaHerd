import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class CollaborationRevisionHydrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CollaborationRevisionRegistry.resetForTesting()
    }

    override func tearDown() {
        CollaborationRevisionRegistry.resetForTesting()
        super.tearDown()
    }

    func testActorHydratesDurableRevisionMetadataForImport() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herd = Herd(name: "Hydration Herd")
        context.insert(herd)
        try PersistenceLog.save(
            context,
            operation: "CollaborationRevisionHydrationTests.seed"
        )

        let key = CollaborationAggregateKey(type: .herd, publicID: herd.publicID)
        let expected = try XCTUnwrap(
            context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
                .first { $0.aggregateKey == key.storageKey }?
                .metadata
        )
        CollaborationRevisionRegistry.resetForTesting()
        XCTAssertNil(CollaborationRevisionRegistry.localMetadata(for: key))

        let actor = SwiftDataHerdSharingActor(modelContainer: container)
        try await actor.hydrateCollaborationRevisions(for: herd.publicID)

        XCTAssertEqual(
            CollaborationRevisionRegistry.localMetadata(for: key),
            expected
        )
    }
}
