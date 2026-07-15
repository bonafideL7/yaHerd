//
//  HerdSharingCoreDataStore+RecordFetching.swift
//  yaHerd
//

import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func sharedHerdRecordSort(_ lhs: SharedHerdRecord, _ rhs: SharedHerdRecord) -> Bool {
    let lhsDate = lhs.lastMirroredAt ?? lhs.updatedAt ?? lhs.createdAt ?? .distantPast
    let rhsDate = rhs.lastMirroredAt ?? rhs.updatedAt ?? rhs.createdAt ?? .distantPast
    return lhsDate > rhsDate
  }

  private func fetchCoreDataRecords<T: NSFetchRequestResult>(
    _ request: NSFetchRequest<T>,
    operation: String
  ) throws -> [T] {
    try PerformanceLog.measure("CoreData.fetch.\(operation)") {
      try persistentContainer.viewContext.fetch(request)
    }
  }

  func fetchSharedHerdRecords(in store: NSPersistentStore) throws -> [SharedHerdRecord] {
    let request = SharedHerdRecord.fetchRequest()
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedHerdRecords")
  }

  func fetchSharedHerdRecords(
    publicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedHerdRecord] {
    let request = SharedHerdRecord.fetchRequest()
    request.predicate = NSPredicate(format: "publicID == %@", publicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedHerdRecordsByPublicID")
  }

  func fetchSharedHerdRecord(
    publicID: UUID,
    in store: NSPersistentStore
  ) throws -> SharedHerdRecord? {
    try fetchSharedHerdRecords(publicID: publicID, in: store)
      .sorted(by: sharedHerdRecordSort)
      .first
  }

  func fetchSharedTagColorDefinitionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedTagColorDefinitionRecord] {
    let request = SharedTagColorDefinitionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedTagColorDefinitionRecords")
  }

  func fetchSharedAnimalStatusReferenceRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalStatusReferenceRecord] {
    let request = SharedAnimalStatusReferenceRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedAnimalStatusReferenceRecords")
  }

  func fetchSharedAnimalTagRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalTagRecord] {
    let request = SharedAnimalTagRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedAnimalTagRecords")
  }

  func fetchSharedPastureGroupRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPastureGroupRecord] {
    let request = SharedPastureGroupRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedPastureGroupRecords")
  }

  func fetchSharedPastureRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPastureRecord] {
    let request = SharedPastureRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedPastureRecords")
  }

  func fetchSharedAnimalRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalRecord] {
    let request = SharedAnimalRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedAnimalRecords")
  }

  func fetchSharedMovementRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedMovementRecord] {
    let request = SharedMovementRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedMovementRecords")
  }

  func fetchSharedStatusRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedStatusRecord] {
    let request = SharedStatusRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedStatusRecords")
  }

  func fetchSharedHealthRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedHealthRecord] {
    let request = SharedHealthRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedHealthRecords")
  }

  func fetchSharedPregnancyCheckRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPregnancyCheckRecord] {
    let request = SharedPregnancyCheckRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedPregnancyCheckRecords")
  }

  func fetchSharedWorkingProtocolTemplateRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingProtocolTemplateRecord] {
    let request = SharedWorkingProtocolTemplateRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedWorkingProtocolTemplateRecords")
  }

  func fetchSharedWorkingSessionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingSessionRecord] {
    let request = SharedWorkingSessionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedWorkingSessionRecords")
  }

  func fetchSharedWorkingQueueItemRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingQueueItemRecord] {
    let request = SharedWorkingQueueItemRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedWorkingQueueItemRecords")
  }

  func fetchSharedWorkingTreatmentRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingTreatmentRecord] {
    let request = SharedWorkingTreatmentRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedWorkingTreatmentRecords")
  }

  func fetchSharedFieldCheckSessionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckSessionRecord] {
    let request = SharedFieldCheckSessionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedFieldCheckSessionRecords")
  }

  func fetchSharedFieldCheckAnimalCheckRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckAnimalCheckRecord] {
    let request = SharedFieldCheckAnimalCheckRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedFieldCheckAnimalCheckRecords")
  }

  func fetchSharedFieldCheckFindingRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckFindingRecord] {
    let request = SharedFieldCheckFindingRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedFieldCheckFindingRecords")
  }

  func fetchSharedDeletedRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedDeletedRecord] {
    let request = SharedDeletedRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedDeletedRecords")
  }

  func fetchSharedDeletedRecord(
    publicID: String,
    sourceEntityName: String,
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> SharedDeletedRecord? {
    let request = SharedDeletedRecord.fetchRequest()
    request.fetchLimit = 1
    request.predicate = NSPredicate(
      format: "publicID == %@ AND sourceEntityName == %@ AND herdPublicID == %@",
      publicID,
      sourceEntityName,
      herdPublicID.uuidString
    )
    request.affectedStores = [store]
    return try fetchCoreDataRecords(request, operation: "fetchSharedDeletedRecord").first
  }
}
