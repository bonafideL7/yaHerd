import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataHerdSharingActorTests: XCTestCase {
  func testLargeHerdExportIsPagedAndScopedToRequestedHerd() async throws {
    let container = try TestSupport.makeModelContainer()
    let fixture = try LargeHerdPersistenceFixture.insert(into: container.mainContext)
    let actor = SwiftDataHerdSharingActor(modelContainer: container)

    let export = try await actor.makeExport(
      for: fixture.herd,
      storeDescription: "large-herd test"
    )

    XCTAssertEqual(export.herd.publicID, fixture.herd.publicID)
    XCTAssertEqual(
      export.snapshot.records(for: .animals).count,
      fixture.expectedCounts.animals
    )
    XCTAssertEqual(
      export.snapshot.records(for: .animalTags).count,
      fixture.expectedCounts.animalTags
    )
    XCTAssertEqual(
      export.snapshot.records(for: .movements).count,
      fixture.expectedCounts.movements
    )
    XCTAssertEqual(
      export.snapshot.records(for: .healthRecords).count,
      fixture.expectedCounts.healthRecords
    )
    XCTAssertEqual(
      export.snapshot.records(for: .pregnancyChecks).count,
      fixture.expectedCounts.pregnancyChecks
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingSessions).count,
      fixture.expectedCounts.workingSessions
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingQueueItems).count,
      fixture.expectedCounts.workingQueueItems
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingTreatmentRecords).count,
      fixture.expectedCounts.workingTreatmentRecords
    )

    let exportedAnimalIDs = Set(export.localPublicIDs[.animals] ?? [])
    XCTAssertEqual(exportedAnimalIDs.count, fixture.expectedCounts.animals)
    XCTAssertFalse(exportedAnimalIDs.contains(fixture.firstExcludedAnimalPublicID))
  }
}
