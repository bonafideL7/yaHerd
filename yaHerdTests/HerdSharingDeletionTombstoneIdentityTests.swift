import CoreData
import Foundation
import SwiftData
import XCTest

@testable import yaHerd

extension SwiftDataHerdSharingActorTests {
  func testImportKeepsDeletionTombstonesDistinctByEntity() throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herdID = UUID()
    let sharedRecordID = UUID()

    let herd = Herd(
      publicID: herdID,
      name: "Composite tombstone herd",
      createdAt: now,
      updatedAt: now
    )
    let pasture = Pasture(
      publicID: sharedRecordID,
      name: "Shared-ID pasture"
    )
    pasture.herd = herd
    let animal = Animal(
      publicID: sharedRecordID,
      name: "",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      pasture: pasture,
      sex: .female
    )
    animal.herd = herd

    context.insert(herd)
    context.insert(pasture)
    context.insert(animal)
    try context.save()

    let bridgeModel = HerdSharingCoreDataModelFactory.makeCurrentModel()
    let herdEntity = try XCTUnwrap(
      bridgeModel.entitiesByName[SharedHerdRecord.entityName]
    )
    let deletionEntity = try XCTUnwrap(
      bridgeModel.entitiesByName[SharedDeletedRecord.entityName]
    )

    let sharedHerd = SharedHerdRecord(entity: herdEntity, insertInto: nil)
    sharedHerd.mirror(herd.toSummary(), mirroredAt: now)

    func makeTombstone(
      sourceEntityName: String,
      mirroredAt: Date
    ) throws -> HerdSharingBridgeRecordSnapshot {
      let tombstone = SharedDeletedRecord(entity: deletionEntity, insertInto: nil)
      tombstone.mirrorDeletion(
        publicID: sharedRecordID.uuidString,
        herdPublicID: herdID,
        sourceEntityName: sourceEntityName,
        deletedAt: now,
        mirroredAt: mirroredAt
      )
      return try HerdSharingBridgeRecordSnapshot(record: tombstone)
    }

    let snapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdID,
      storeDescription: "composite tombstone test",
      recordsByStep: [
        .herd: [try HerdSharingBridgeRecordSnapshot(record: sharedHerd)],
        .deletions: [
          try makeTombstone(
            sourceEntityName: SharedAnimalRecord.entityName,
            mirroredAt: now.addingTimeInterval(1)
          ),
          try makeTombstone(
            sourceEntityName: SharedPastureRecord.entityName,
            mirroredAt: now.addingTimeInterval(2)
          ),
        ],
      ]
    )

    let application = try HerdSharingSwiftDataImportEngine.apply(
      snapshot,
      pendingConflictReport: nil,
      failureInjector: .disabled,
      in: context
    )

    XCTAssertEqual(application.result.deletedRecordCount, 2)
    XCTAssertFalse(
      try context.fetch(FetchDescriptor<Animal>()).contains {
        $0.publicID == sharedRecordID
      }
    )
    XCTAssertFalse(
      try context.fetch(FetchDescriptor<Pasture>()).contains {
        $0.publicID == sharedRecordID
      }
    )
  }

  func testExportKeepsDeletionTombstonesDistinctByEntity() async throws {
    let storeDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HerdSharingDeletionTombstoneIdentityTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: storeDirectory) }

    let store = HerdSharingCoreDataStore(
      storeDirectoryURL: storeDirectory,
      journalFileURL: storeDirectory.appendingPathComponent("journal.json")
    )
    try await store.loadIfNeeded()
    let privateStore = try XCTUnwrap(store.privateStore)

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herdID = UUID()
    let sharedRecordID = UUID()
    let herd = HerdSummary(
      publicID: herdID,
      name: "Composite export tombstone herd",
      createdAt: now,
      updatedAt: now,
      schemaVersion: 1
    )
    let pasture = Pasture(
      publicID: sharedRecordID,
      name: "Shared-ID pasture"
    )
    let animal = Animal(
      publicID: sharedRecordID,
      name: "",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      pasture: pasture,
      sex: .female
    )

    let bridgeModel = HerdSharingCoreDataModelFactory.makeCurrentModel()
    let herdEntity = try XCTUnwrap(
      bridgeModel.entitiesByName[SharedHerdRecord.entityName]
    )
    let pastureEntity = try XCTUnwrap(
      bridgeModel.entitiesByName[SharedPastureRecord.entityName]
    )
    let animalEntity = try XCTUnwrap(
      bridgeModel.entitiesByName[SharedAnimalRecord.entityName]
    )

    let sharedHerd = SharedHerdRecord(entity: herdEntity, insertInto: nil)
    sharedHerd.mirror(herd, mirroredAt: now)
    let sharedPasture = SharedPastureRecord(entity: pastureEntity, insertInto: nil)
    sharedPasture.mirror(pasture, herdPublicID: herdID, mirroredAt: now)
    let sharedAnimal = SharedAnimalRecord(entity: animalEntity, insertInto: nil)
    sharedAnimal.mirror(animal, herdPublicID: herdID, mirroredAt: now)

    let herdSnapshot = try HerdSharingBridgeRecordSnapshot(record: sharedHerd)
    let initialSnapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdID,
      storeDescription: "composite export tombstone test",
      recordsByStep: [
        .herd: [herdSnapshot],
        .pastures: [try HerdSharingBridgeRecordSnapshot(record: sharedPasture)],
        .animals: [try HerdSharingBridgeRecordSnapshot(record: sharedAnimal)],
      ]
    )
    _ = try await store.writeBridgeSnapshot(initialSnapshot, to: privateStore)

    let removalSnapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdID,
      storeDescription: "composite export tombstone test",
      recordsByStep: [.herd: [herdSnapshot]]
    )
    let result = try await store.writeBridgeSnapshot(removalSnapshot, to: privateStore)
    let tombstones = result.snapshot.records(for: .deletions)

    XCTAssertEqual(tombstones.count, 2)
    let identities = Set(tombstones.compactMap { snapshot -> String? in
      guard case .string(let sourceEntityName) = snapshot.attributes["sourceEntityName"] else {
        return nil
      }
      return "\(sourceEntityName)|\(snapshot.publicID)"
    })
    XCTAssertEqual(
      identities,
      Set([
        "\(SharedAnimalRecord.entityName)|\(sharedRecordID.uuidString)",
        "\(SharedPastureRecord.entityName)|\(sharedRecordID.uuidString)",
      ])
    )
  }
}
