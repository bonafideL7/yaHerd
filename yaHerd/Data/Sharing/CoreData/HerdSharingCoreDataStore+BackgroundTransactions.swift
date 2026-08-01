//
//  HerdSharingCoreDataStore+BackgroundTransactions.swift
//  yaHerd
//

@preconcurrency import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func readBridgeSnapshot(
    from store: NSPersistentStore,
    requestedHerdPublicID: UUID?,
    storeDescription: String
  ) async throws -> HerdSharingBridgeStoreSnapshot {
    guard let storeURL = store.url else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The selected Core Data sharing bridge store has no URL."
      )
    }
    let context = persistentContainer.newBackgroundContext()
    context.name = "HerdSharingBridge.ImportRead"
    context.undoManager = nil
    context.mergePolicy = NSMergePolicy(
      merge: .mergeByPropertyObjectTrumpMergePolicyType
    )
    context.transactionAuthor = "yaHerd.bridge.import"

    return try await context.perform {
      let resolvedStore = try Self.resolvePersistentStore(
        at: storeURL,
        in: context
      )
      return try PerformanceLog.measure("CoreData.bridge.backgroundImportRead") {
        try Self.makeBridgeStoreSnapshot(
          in: context,
          store: resolvedStore,
          requestedHerdPublicID: requestedHerdPublicID,
          storeDescription: storeDescription
        )
      }
    }
  }

  func writeBridgeSnapshot(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    to store: NSPersistentStore,
    failureInjector: HerdSharingBridgeFailureInjector = .disabled
  ) async throws -> HerdSharingBridgeWriteResult {
    guard let storeURL = store.url else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The selected Core Data sharing bridge store has no URL."
      )
    }
    let context = persistentContainer.newBackgroundContext()
    context.name = "HerdSharingBridge.ExportWrite"
    context.undoManager = nil
    context.mergePolicy = NSMergePolicy(
      merge: .mergeByPropertyObjectTrumpMergePolicyType
    )
    context.transactionAuthor = "yaHerd.bridge.export"

    return try await context.perform {
      let resolvedStore = try Self.resolvePersistentStore(
        at: storeURL,
        in: context
      )
      return try PerformanceLog.measure("CoreData.bridge.backgroundExportWrite") {
        try Self.applyBridgeStoreSnapshot(
          snapshot,
          in: context,
          store: resolvedStore,
          failureInjector: failureInjector
        )
      }
    }
  }

  func detachedRecords<Record: NSManagedObject>(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as _: Record.Type
  ) throws -> [Record] {
    guard let entityName = step.coreDataEntityName else { return [] }
    guard let entity = HerdSharingCoreDataModelFactory.makeCurrentModel().entitiesByName[entityName]
    else {
      throw HerdSharingBridgeSnapshotError.missingEntityDescription(entityName)
    }

    return try snapshot.records(for: step).map { recordSnapshot in
      let record = Record(entity: entity, insertInto: nil)
      try recordSnapshot.apply(to: record)
      return record
    }
  }

  nonisolated private static func resolvePersistentStore(
    at url: URL,
    in context: NSManagedObjectContext
  ) throws -> NSPersistentStore {
    guard let store = context.persistentStoreCoordinator?.persistentStores.first(where: {
      $0.url?.standardizedFileURL == url.standardizedFileURL
    }) else {
      throw HerdSharingBridgeSnapshotError.missingPersistentStore(url)
    }
    return store
  }

  nonisolated private static func makeBridgeStoreSnapshot(
    in context: NSManagedObjectContext,
    store: NSPersistentStore,
    requestedHerdPublicID: UUID?,
    storeDescription: String
  ) throws -> HerdSharingBridgeStoreSnapshot {
    let herdRecords = try fetchRecords(
      step: .herd,
      herdPublicID: requestedHerdPublicID,
      in: context,
      store: store
    )
    let selectedHerd = try selectHerdRecord(
      from: herdRecords,
      requestedHerdPublicID: requestedHerdPublicID
    )
    guard let herdPublicIDString = selectedHerd.value(forKey: "publicID") as? String,
      let herdPublicID = UUID(uuidString: herdPublicIDString)
    else {
      throw HerdSharingBridgeSnapshotError.missingHerdRecord(requestedHerdPublicID)
    }

    var recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]] = [:]
    for step in HerdSharingBridgeStep.entitySteps {
      let records: [NSManagedObject]
      if step == .herd {
        records = herdRecords.filter {
          ($0.value(forKey: "publicID") as? String) == herdPublicID.uuidString
        }
      } else {
        records = try fetchRecords(
          step: step,
          herdPublicID: herdPublicID,
          in: context,
          store: store
        )
      }
      recordsByStep[step] = try records.map(HerdSharingBridgeRecordSnapshot.init(record:))
    }

    return HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdPublicID,
      storeDescription: storeDescription,
      recordsByStep: recordsByStep
    )
  }

  nonisolated private static func fetchRecords(
    step: HerdSharingBridgeStep,
    herdPublicID: UUID?,
    in context: NSManagedObjectContext,
    store: NSPersistentStore
  ) throws -> [NSManagedObject] {
    guard let entityName = step.coreDataEntityName else { return [] }
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.affectedStores = [store]
    if let herdPublicID {
      if step == .herd {
        request.predicate = NSPredicate(
          format: "publicID == %@",
          herdPublicID.uuidString
        )
      } else {
        request.predicate = NSPredicate(
          format: "herdPublicID == %@",
          herdPublicID.uuidString
        )
      }
    }
    return try PerformanceLog.measure("CoreData.bridge.fetch.\(step.rawValue)") {
      try context.fetch(request)
    }
  }

  nonisolated private static func selectHerdRecord(
    from records: [NSManagedObject],
    requestedHerdPublicID: UUID?
  ) throws -> NSManagedObject {
    let matchingRecords: [NSManagedObject]
    if let requestedHerdPublicID {
      matchingRecords = records.filter {
        ($0.value(forKey: "publicID") as? String) == requestedHerdPublicID.uuidString
      }
    } else {
      matchingRecords = records
    }

    guard let selected = matchingRecords.sorted(by: bridgeRecordSort).first else {
      throw HerdSharingBridgeSnapshotError.missingHerdRecord(requestedHerdPublicID)
    }
    return selected
  }

  nonisolated private static func bridgeRecordSort(
    _ lhs: NSManagedObject,
    _ rhs: NSManagedObject
  ) -> Bool {
    let lhsDate =
      lhs.value(forKey: "lastMirroredAt") as? Date
      ?? lhs.value(forKey: "updatedAt") as? Date
      ?? lhs.value(forKey: "createdAt") as? Date
      ?? .distantPast
    let rhsDate =
      rhs.value(forKey: "lastMirroredAt") as? Date
      ?? rhs.value(forKey: "updatedAt") as? Date
      ?? rhs.value(forKey: "createdAt") as? Date
      ?? .distantPast
    if lhsDate != rhsDate { return lhsDate > rhsDate }
    return lhs.objectID.uriRepresentation().absoluteString
      < rhs.objectID.uriRepresentation().absoluteString
  }

  nonisolated private static func applyBridgeStoreSnapshot(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    in context: NSManagedObjectContext,
    store: NSPersistentStore,
    failureInjector: HerdSharingBridgeFailureInjector
  ) throws -> HerdSharingBridgeWriteResult {
    var recordsByEntityAndPublicID: [String: [String: NSManagedObject]] = [:]
    var completedSteps: [HerdSharingBridgeStep] = []

    for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
      guard let entityName = step.coreDataEntityName else { continue }
      let existingRecords = try fetchRecords(
        step: step,
        herdPublicID: snapshot.herdPublicID,
        in: context,
        store: store
      )
      let canonicalRecords = canonicalRecordsByPublicID(
        existingRecords,
        in: context
      )
      let desiredSnapshots = snapshot.records(for: step)
      let desiredPublicIDs = Set(desiredSnapshots.map(\.publicID))
      var finalRecords = canonicalRecords

      for recordSnapshot in desiredSnapshots {
        let record: NSManagedObject
        if let existing = canonicalRecords[recordSnapshot.publicID] {
          record = existing
        } else {
          guard let entity = context.persistentStoreCoordinator?.managedObjectModel
            .entitiesByName[entityName]
          else {
            throw HerdSharingBridgeSnapshotError.missingEntityDescription(entityName)
          }
          record = NSManagedObject(entity: entity, insertInto: context)
          context.assign(record, to: store)
          finalRecords[recordSnapshot.publicID] = record
        }
        try recordSnapshot.apply(to: record)
      }

      if step != .herd {
        for (publicID, staleRecord) in canonicalRecords where !desiredPublicIDs.contains(publicID) {
          try upsertDeletionTombstone(
            publicID: publicID,
            sourceEntityName: entityName,
            herdPublicID: snapshot.herdPublicID,
            in: context,
            store: store
          )
          context.delete(staleRecord)
          finalRecords.removeValue(forKey: publicID)
        }
      }

      recordsByEntityAndPublicID[entityName] = finalRecords
      try failureInjector.check(after: step)
      completedSteps.append(step)
    }

    try linkBridgeRelationships(
      recordsByEntityAndPublicID: &recordsByEntityAndPublicID,
      herdPublicID: snapshot.herdPublicID,
      in: context,
      store: store
    )
    try failureInjector.check(after: .deletions)
    completedSteps.append(.deletions)

    if context.hasChanges {
      try context.save()
    }
    try failureInjector.check(after: .persistentStoreCommit)
    completedSteps.append(.persistentStoreCommit)

    let finalSnapshot = try makeBridgeStoreSnapshot(
      in: context,
      store: store,
      requestedHerdPublicID: snapshot.herdPublicID,
      storeDescription: snapshot.storeDescription
    )
    let objectURIs = HerdSharingBridgeStep.entitySteps.flatMap { step in
      guard let entityName = step.coreDataEntityName else { return [String]() }
      return recordsByEntityAndPublicID[entityName, default: [:]].values.map {
        $0.objectID.uriRepresentation().absoluteString
      }
    }

    ReliabilityLog.syncEvent(
      "HerdSharingCoreDataStore.backgroundExport.completed",
      detail: completedSteps.map(\.rawValue).joined(separator: ",")
    )
    return HerdSharingBridgeWriteResult(
      snapshot: finalSnapshot,
      managedObjectURIs: objectURIs
    )
  }

  nonisolated private static func canonicalRecordsByPublicID(
    _ records: [NSManagedObject],
    in context: NSManagedObjectContext
  ) -> [String: NSManagedObject] {
    var recordsByPublicID: [String: NSManagedObject] = [:]
    for record in records {
      guard let publicID = record.value(forKey: "publicID") as? String, !publicID.isEmpty else {
        context.delete(record)
        continue
      }
      guard let existing = recordsByPublicID[publicID] else {
        recordsByPublicID[publicID] = record
        continue
      }

      if bridgeRecordSort(record, existing) {
        context.delete(existing)
        recordsByPublicID[publicID] = record
      } else {
        context.delete(record)
      }
      ReliabilityLog.syncEvent(
        "HerdSharingCoreDataStore.duplicateBridgeRecordRepaired",
        detail: "\(record.entity.name ?? "Unknown"):\(publicID)"
      )
    }
    return recordsByPublicID
  }

  nonisolated private static func upsertDeletionTombstone(
    publicID: String,
    sourceEntityName: String,
    herdPublicID: UUID,
    in context: NSManagedObjectContext,
    store: NSPersistentStore
  ) throws {
    let request = NSFetchRequest<NSManagedObject>(entityName: SharedDeletedRecord.entityName)
    request.fetchLimit = 1
    request.affectedStores = [store]
    request.predicate = NSPredicate(
      format: "publicID == %@ AND sourceEntityName == %@ AND herdPublicID == %@",
      publicID,
      sourceEntityName,
      herdPublicID.uuidString
    )
    let existing = try context.fetch(request).first
    let tombstone: NSManagedObject
    if let existing {
      tombstone = existing
    } else {
      guard let entity = context.persistentStoreCoordinator?.managedObjectModel
        .entitiesByName[SharedDeletedRecord.entityName]
      else {
        throw HerdSharingBridgeSnapshotError.missingEntityDescription(
          SharedDeletedRecord.entityName
        )
      }
      tombstone = NSManagedObject(entity: entity, insertInto: context)
      context.assign(tombstone, to: store)
    }

    let now = Date.now
    tombstone.setValue(publicID, forKey: "publicID")
    tombstone.setValue(herdPublicID.uuidString, forKey: "herdPublicID")
    tombstone.setValue(sourceEntityName, forKey: "sourceEntityName")
    tombstone.setValue(now, forKey: "deletedAt")
    tombstone.setValue(now, forKey: "lastMirroredAt")
  }

  nonisolated private static func linkBridgeRelationships(
    recordsByEntityAndPublicID: inout [String: [String: NSManagedObject]],
    herdPublicID: UUID,
    in context: NSManagedObjectContext,
    store: NSPersistentStore
  ) throws {
    let herdRecords = recordsByEntityAndPublicID[SharedHerdRecord.entityName, default: [:]]
    guard let herdRecord = herdRecords[herdPublicID.uuidString] else {
      throw HerdSharingBridgeSnapshotError.missingHerdRecord(herdPublicID)
    }

    let relationSpecs: [BridgeRelationSpec] = [
      .init(
        SharedPastureRecord.entityName,
        "group",
        "groupPublicID",
        SharedPastureGroupRecord.entityName
      ),
      .init(
        SharedAnimalTagRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedMovementRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedStatusRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedHealthRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedPregnancyCheckRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedWorkingQueueItemRecord.entityName,
        "session",
        "sessionPublicID",
        SharedWorkingSessionRecord.entityName
      ),
      .init(
        SharedWorkingQueueItemRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedWorkingTreatmentRecord.entityName,
        "session",
        "sessionPublicID",
        SharedWorkingSessionRecord.entityName
      ),
      .init(
        SharedWorkingTreatmentRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedFieldCheckAnimalCheckRecord.entityName,
        "session",
        "sessionPublicID",
        SharedFieldCheckSessionRecord.entityName
      ),
      .init(
        SharedFieldCheckAnimalCheckRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
      .init(
        SharedFieldCheckFindingRecord.entityName,
        "session",
        "sessionPublicID",
        SharedFieldCheckSessionRecord.entityName
      ),
      .init(
        SharedFieldCheckFindingRecord.entityName,
        "animal",
        "animalPublicID",
        SharedAnimalRecord.entityName
      ),
    ]

    for (entityName, records) in recordsByEntityAndPublicID
    where entityName != SharedHerdRecord.entityName {
      for record in records.values where record.entity.relationshipsByName["herd"] != nil {
        record.setValue(herdRecord, forKey: "herd")
      }
    }

    let tombstones = try fetchRecords(
      step: .deletions,
      herdPublicID: herdPublicID,
      in: context,
      store: store
    )
    for tombstone in tombstones {
      tombstone.setValue(herdRecord, forKey: "herd")
    }
    recordsByEntityAndPublicID[SharedDeletedRecord.entityName] = canonicalRecordsByPublicID(
      tombstones,
      in: context
    )

    for spec in relationSpecs {
      let destinations = recordsByEntityAndPublicID[spec.destinationEntityName, default: [:]]
      for source in recordsByEntityAndPublicID[spec.sourceEntityName, default: [:]].values {
        let destinationPublicID = source.value(forKey: spec.publicIDAttributeName) as? String
        source.setValue(
          destinationPublicID.flatMap { destinations[$0] },
          forKey: spec.relationshipName
        )
      }
    }
  }
}

private struct BridgeRelationSpec {
  let sourceEntityName: String
  let relationshipName: String
  let publicIDAttributeName: String
  let destinationEntityName: String

  init(
    _ sourceEntityName: String,
    _ relationshipName: String,
    _ publicIDAttributeName: String,
    _ destinationEntityName: String
  ) {
    self.sourceEntityName = sourceEntityName
    self.relationshipName = relationshipName
    self.publicIDAttributeName = publicIDAttributeName
    self.destinationEntityName = destinationEntityName
  }
}
