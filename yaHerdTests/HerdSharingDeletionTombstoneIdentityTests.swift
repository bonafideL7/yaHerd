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

  func testExportCanonicalizationKeepsDeletionTombstonesDistinctByEntity() throws {
    let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    try coordinator.addPersistentStore(
      ofType: NSInMemoryStoreType,
      configurationName: nil,
      at: nil
    )
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herdID = UUID()
    let sharedRecordID = UUID()

    func makeTombstone(
      sourceEntityName: String,
      mirroredAt: Date
    ) -> SharedDeletedRecord {
      let tombstone = SharedDeletedRecord(context: context)
      tombstone.mirrorDeletion(
        publicID: sharedRecordID.uuidString,
        herdPublicID: herdID,
        sourceEntityName: sourceEntityName,
        deletedAt: now,
        mirroredAt: mirroredAt
      )
      return tombstone
    }

    let olderAnimalTombstone = makeTombstone(
      sourceEntityName: SharedAnimalRecord.entityName,
      mirroredAt: now
    )
    let newerAnimalTombstone = makeTombstone(
      sourceEntityName: SharedAnimalRecord.entityName,
      mirroredAt: now.addingTimeInterval(1)
    )
    let pastureTombstone = makeTombstone(
      sourceEntityName: SharedPastureRecord.entityName,
      mirroredAt: now.addingTimeInterval(2)
    )

    let canonical = HerdSharingCoreDataStore.canonicalRecordsByPublicID(
      [olderAnimalTombstone, newerAnimalTombstone, pastureTombstone],
      in: context
    )

    XCTAssertEqual(canonical.count, 2)
    let survivingTombstones = canonical.values.compactMap { $0 as? SharedDeletedRecord }
    XCTAssertEqual(
      Set(survivingTombstones.compactMap(\.sourceEntityName)),
      Set([SharedAnimalRecord.entityName, SharedPastureRecord.entityName])
    )
    let survivingAnimalTombstone = try XCTUnwrap(
      survivingTombstones.first {
        $0.sourceEntityName == SharedAnimalRecord.entityName
      }
    )
    XCTAssertEqual(
      survivingAnimalTombstone.lastMirroredAt,
      newerAnimalTombstone.lastMirroredAt
    )
    XCTAssertTrue(olderAnimalTombstone.isDeleted)
  }
}
