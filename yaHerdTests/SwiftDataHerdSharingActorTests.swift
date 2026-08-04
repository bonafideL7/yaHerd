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

  func testRelatedExportIncludesUnscopedChildAndExcludesDifferentlyScopedChild() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let requestedHerd = Herd(name: "Requested Herd")
    let otherHerd = Herd(name: "Other Herd")
    let animal = Animal(
      name: "Scoped Animal",
      tagNumber: "101",
      birthDate: Date(timeIntervalSince1970: 1),
      sex: .female
    )
    animal.herd = requestedHerd

    let unscopedTag = AnimalTag(
      number: "101",
      isPrimary: true,
      animal: animal
    )
    let differentlyScopedTag = AnimalTag(
      number: "202",
      animal: animal
    )
    differentlyScopedTag.herd = otherHerd
    animal.tags = [unscopedTag, differentlyScopedTag]

    context.insert(requestedHerd)
    context.insert(otherHerd)
    context.insert(animal)
    context.insert(unscopedTag)
    context.insert(differentlyScopedTag)
    try context.save()

    let actor = SwiftDataHerdSharingActor(modelContainer: container)
    let export = try await actor.makeExport(
      for: requestedHerd.toSummary(),
      storeDescription: "cross-herd child test"
    )

    let exportedTagIDs = Set(export.localPublicIDs[.animalTags] ?? [])
    XCTAssertTrue(exportedTagIDs.contains(unscopedTag.publicID))
    XCTAssertFalse(exportedTagIDs.contains(differentlyScopedTag.publicID))
    XCTAssertEqual(export.snapshot.records(for: .animalTags).count, 1)
  }
}
