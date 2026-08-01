import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class SwiftDataHerdSharingActorDuplicateIDPagingTests: XCTestCase {
  func testExportRejectsDuplicatePublicIDsBeyondPageBoundary() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herd = Herd(
      name: "Duplicate ID herd",
      createdAt: now,
      updatedAt: now
    )
    context.insert(herd)

    for index in 0..<499 {
      let animal = Animal(
        publicID: stableUUID(index),
        name: "",
        tagNumber: String(index),
        birthDate: now,
        status: .active,
        sex: .female
      )
      animal.herd = herd
      context.insert(animal)
    }

    let duplicatePublicID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!
    for index in 499..<501 {
      let animal = Animal(
        publicID: duplicatePublicID,
        name: "",
        tagNumber: String(index),
        birthDate: now,
        status: .active,
        sex: .female
      )
      animal.herd = herd
      context.insert(animal)
    }
    try context.save()

    let actor = SwiftDataHerdSharingActor(modelContainer: container)

    do {
      _ = try await actor.makeExport(
        for: herd.toSummary(),
        storeDescription: "duplicate-ID paging test"
      )
      XCTFail("Expected duplicate public IDs to block export.")
    } catch HerdSharingActionError.bridgeConsistencyFailed(let message) {
      XCTAssertTrue(
        message.lowercased().contains("duplicate"),
        "Expected a duplicate-ID repair error, received: \(message)"
      )
    } catch {
      XCTFail("Expected bridgeConsistencyFailed, received: \(error)")
    }
  }

  private func stableUUID(_ index: Int) -> UUID {
    let value = String(
      format: "00000000-0000-4000-8000-%012llX",
      Int64(index)
    )
    return UUID(uuidString: value)!
  }
}
