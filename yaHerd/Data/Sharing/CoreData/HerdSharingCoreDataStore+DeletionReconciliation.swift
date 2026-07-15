//
//  HerdSharingCoreDataStore+DeletionReconciliation.swift
//  yaHerd
//

import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
  func acceptPreventedSharedDeletes(
    _ conflicts: [HerdSharingPreventedDeleteConflict],
    context: ModelContext
  ) throws -> Int {
    var deletedCount = 0
    let orderedConflicts = conflicts.sorted { lhs, rhs in
      deletionPriority(for: lhs.sourceEntityName) < deletionPriority(for: rhs.sourceEntityName)
    }

    for conflict in orderedConflicts {
      if try deleteSwiftDataRecord(
        sourceEntityName: conflict.sourceEntityName,
        publicID: conflict.publicID,
        in: context
      ) {
        deletedCount += 1
      }
    }

    try saveBridgeContextIfNeeded()

    return deletedCount
  }

  func deleteSwiftDataRecords(
    from tombstones: [SharedDeletedRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (deletedCount: Int, preventedDeleteConflicts: [HerdSharingBridgeConflictDetail]) {
    var deletedCount = 0
    var preventedDeleteConflicts: [HerdSharingBridgeConflictDetail] = []
    let orderedTombstones = tombstones.sorted { lhs, rhs in
      deletionPriority(for: lhs.sourceEntityName) < deletionPriority(for: rhs.sourceEntityName)
    }

    for tombstone in orderedTombstones {
      guard let publicID = tombstone.parsedPublicID,
        let sourceEntityName = tombstone.sourceEntityName
      else { continue }

      if let conflict = try preventedDeleteConflict(
        sourceEntityName: sourceEntityName,
        publicID: publicID,
        tombstoneDeletedAt: tombstone.deletedAt,
        in: context
      ) {
        preventedDeleteConflicts.append(conflict)
        continue
      }

      if try deleteSwiftDataRecord(
        sourceEntityName: sourceEntityName,
        publicID: publicID,
        herd: herd,
        in: context
      ) {
        deletedCount += 1
      }
    }

    return (deletedCount, preventedDeleteConflicts)
  }

  private func preventedDeleteConflict(
    sourceEntityName: String,
    publicID: UUID,
    tombstoneDeletedAt: Date?,
    in context: ModelContext
  ) throws -> HerdSharingBridgeConflictDetail? {
    guard let tombstoneDeletedAt,
      let localModifiedAt = try localModificationDate(
        sourceEntityName: sourceEntityName,
        publicID: publicID,
        in: context
      ),
      localModifiedAt > tombstoneDeletedAt
    else { return nil }

    return HerdSharingBridgeConflictDetail(
      kind: .preventedSharedDelete,
      sourceEntityName: sourceEntityName,
      publicID: publicID,
      localModifiedAt: localModifiedAt,
      sharedModifiedAt: tombstoneDeletedAt
    )
  }

  private func localModificationDate(
    sourceEntityName: String,
    publicID: UUID,
    in context: ModelContext
  ) throws -> Date? {
    switch sourceEntityName {
    case SharedTagColorDefinitionRecord.entityName:
      return try fetchSwiftDataRecord(
        TagColorDefinition.self,
        publicID: publicID,
        keyPath: \.id,
        in: context
      )?.updatedAt
    case SharedAnimalStatusReferenceRecord.entityName:
      return try fetchSwiftDataRecord(
        AnimalStatusReference.self,
        publicID: publicID,
        keyPath: \.id,
        in: context
      )?.createdAt
    case SharedAnimalTagRecord.entityName:
      return try fetchSwiftDataRecord(
        AnimalTag.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ).flatMap { latestDate($0.assignedAt, $0.removedAt) }
    case SharedMovementRecord.entityName:
      return try fetchSwiftDataRecord(
        MovementRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedStatusRecord.entityName:
      return try fetchSwiftDataRecord(
        StatusRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedHealthRecord.entityName:
      return try fetchSwiftDataRecord(
        HealthRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedPregnancyCheckRecord.entityName:
      return try fetchSwiftDataRecord(
        PregnancyCheck.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedWorkingQueueItemRecord.entityName:
      return try fetchSwiftDataRecord(
        WorkingQueueItem.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.completedAt
    case SharedWorkingTreatmentRecord.entityName:
      return try fetchSwiftDataRecord(
        WorkingTreatmentRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedFieldCheckAnimalCheckRecord.entityName:
      return try fetchSwiftDataRecord(
        FieldCheckAnimalCheck.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ).flatMap { latestDate($0.countedAt, $0.missingConfirmedAt) }
    case SharedFieldCheckFindingRecord.entityName:
      return try fetchSwiftDataRecord(
        FieldCheckFinding.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.recordedAt
    case SharedFieldCheckSessionRecord.entityName:
      return try fetchSwiftDataRecord(
        FieldCheckSession.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ).flatMap { latestDate($0.startedAt, $0.completedAt) }
    case SharedWorkingSessionRecord.entityName:
      return try fetchSwiftDataRecord(
        WorkingSession.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.date
    case SharedAnimalRecord.entityName:
      return nil
    case SharedPastureRecord.entityName:
      return try fetchSwiftDataRecord(
        Pasture.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      )?.lastGrazedDate
    case SharedPastureGroupRecord.entityName:
      return nil
    case SharedWorkingProtocolTemplateRecord.entityName:
      return nil
    default:
      return nil
    }
  }

  private func latestDate(_ dates: Date?...) -> Date? {
    dates.compactMap { $0 }.max()
  }

  private func deleteSwiftDataRecord(
    sourceEntityName: String,
    publicID: UUID,
    herd: Herd,
    in context: ModelContext
  ) throws -> Bool {
    try deleteSwiftDataRecord(
      sourceEntityName: sourceEntityName,
      publicID: publicID,
      in: context
    )
  }

  private func deleteSwiftDataRecord(
    sourceEntityName: String,
    publicID: UUID,
    in context: ModelContext
  ) throws -> Bool {
    switch sourceEntityName {
    case SharedAnimalTagRecord.entityName:
      return try deleteSwiftDataRecord(
        AnimalTag.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedMovementRecord.entityName:
      return try deleteSwiftDataRecord(
        MovementRecord.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedStatusRecord.entityName:
      return try deleteSwiftDataRecord(
        StatusRecord.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedHealthRecord.entityName:
      return try deleteSwiftDataRecord(
        HealthRecord.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedPregnancyCheckRecord.entityName:
      return try deleteSwiftDataRecord(
        PregnancyCheck.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedWorkingQueueItemRecord.entityName:
      return try deleteSwiftDataRecord(
        WorkingQueueItem.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedWorkingTreatmentRecord.entityName:
      return try deleteSwiftDataRecord(
        WorkingTreatmentRecord.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedFieldCheckAnimalCheckRecord.entityName:
      return try deleteSwiftDataRecord(
        FieldCheckAnimalCheck.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedFieldCheckFindingRecord.entityName:
      return try deleteSwiftDataRecord(
        FieldCheckFinding.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedFieldCheckSessionRecord.entityName:
      return try deleteSwiftDataRecord(
        FieldCheckSession.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedWorkingSessionRecord.entityName:
      return try deleteSwiftDataRecord(
        WorkingSession.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedWorkingProtocolTemplateRecord.entityName:
      return try deleteSwiftDataRecord(
        WorkingProtocolTemplate.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedAnimalRecord.entityName:
      return try deleteSwiftDataRecord(
        Animal.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedPastureRecord.entityName:
      return try deleteSwiftDataRecord(
        Pasture.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedPastureGroupRecord.entityName:
      return try deleteSwiftDataRecord(
        PastureGroup.self, publicID: publicID, keyPath: \.publicID, in: context)
    case SharedAnimalStatusReferenceRecord.entityName:
      return try deleteSwiftDataRecord(
        AnimalStatusReference.self, publicID: publicID, keyPath: \.id, in: context)
    case SharedTagColorDefinitionRecord.entityName:
      return try deleteSwiftDataRecord(
        TagColorDefinition.self, publicID: publicID, keyPath: \.id, in: context)
    default:
      return false
    }
  }

  private func deleteSwiftDataRecord<T: PersistentModel>(
    _ modelType: T.Type,
    publicID: UUID,
    keyPath: KeyPath<T, UUID>,
    in context: ModelContext
  ) throws -> Bool {
    guard
      let record = try fetchSwiftDataRecord(
        modelType,
        publicID: publicID,
        keyPath: keyPath,
        in: context
      )
    else { return false }

    context.delete(record)
    return true
  }

  func fetchSwiftDataRecord<T: PersistentModel>(
    _ modelType: T.Type,
    publicID: UUID,
    keyPath: KeyPath<T, UUID>,
    in context: ModelContext
  ) throws -> T? {
    try context.fetch(FetchDescriptor<T>()).first { record in
      record[keyPath: keyPath] == publicID
    }
  }

  private func deletionPriority(for sourceEntityName: String?) -> Int {
    switch sourceEntityName {
    case SharedAnimalTagRecord.entityName,
      SharedMovementRecord.entityName,
      SharedStatusRecord.entityName,
      SharedHealthRecord.entityName,
      SharedPregnancyCheckRecord.entityName,
      SharedWorkingQueueItemRecord.entityName,
      SharedWorkingTreatmentRecord.entityName,
      SharedFieldCheckAnimalCheckRecord.entityName,
      SharedFieldCheckFindingRecord.entityName:
      return 0
    case SharedFieldCheckSessionRecord.entityName,
      SharedWorkingSessionRecord.entityName:
      return 1
    case SharedWorkingProtocolTemplateRecord.entityName:
      return 2
    case SharedAnimalRecord.entityName:
      return 3
    case SharedPastureRecord.entityName:
      return 4
    case SharedPastureGroupRecord.entityName,
      SharedAnimalStatusReferenceRecord.entityName,
      SharedTagColorDefinitionRecord.entityName:
      return 5
    default:
      return 10
    }
  }

  func fetchSwiftDataHerd(
    publicID: UUID,
    in context: ModelContext
  ) throws -> Herd? {
    try context.fetch(FetchDescriptor<Herd>()).first { herd in
      herd.publicID == publicID
    }
  }
}
