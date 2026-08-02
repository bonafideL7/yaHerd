//
//  HerdSharingSwiftDataImportEngine+DetachedRecords.swift
//  yaHerd
//

@preconcurrency import CoreData

extension HerdSharingSwiftDataImportEngine {
  private static func retainedDetachedRecords<Record: NSManagedObject>(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as _: Record.Type
  ) throws -> [Record] {
    guard let entityName = step.coreDataEntityName else { return [] }

    // NSEntityDescription does not keep its model alive. Retain the complete
    // model until every detached managed object has been initialized.
    let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
    guard let entity = model.entitiesByName[entityName] else {
      throw HerdSharingBridgeSnapshotError.missingEntityDescription(entityName)
    }

    return try withExtendedLifetime(model) {
      try snapshot.records(for: step)
        .sorted(by: bridgeRecordSnapshotSort)
        .map { recordSnapshot in
          let record = Record(entity: entity, insertInto: nil)
          try recordSnapshot.apply(to: record)
          return record
        }
    }
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedHerdRecord.Type
  ) throws -> [SharedHerdRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedTagColorDefinitionRecord.Type
  ) throws -> [SharedTagColorDefinitionRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedAnimalStatusReferenceRecord.Type
  ) throws -> [SharedAnimalStatusReferenceRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedPastureGroupRecord.Type
  ) throws -> [SharedPastureGroupRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedPastureRecord.Type
  ) throws -> [SharedPastureRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedAnimalRecord.Type
  ) throws -> [SharedAnimalRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedAnimalTagRecord.Type
  ) throws -> [SharedAnimalTagRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedMovementRecord.Type
  ) throws -> [SharedMovementRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedStatusRecord.Type
  ) throws -> [SharedStatusRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedWorkingProtocolTemplateRecord.Type
  ) throws -> [SharedWorkingProtocolTemplateRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedWorkingSessionRecord.Type
  ) throws -> [SharedWorkingSessionRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedWorkingQueueItemRecord.Type
  ) throws -> [SharedWorkingQueueItemRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedWorkingTreatmentRecord.Type
  ) throws -> [SharedWorkingTreatmentRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedHealthRecord.Type
  ) throws -> [SharedHealthRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedPregnancyCheckRecord.Type
  ) throws -> [SharedPregnancyCheckRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedFieldCheckSessionRecord.Type
  ) throws -> [SharedFieldCheckSessionRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedFieldCheckAnimalCheckRecord.Type
  ) throws -> [SharedFieldCheckAnimalCheckRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedFieldCheckFindingRecord.Type
  ) throws -> [SharedFieldCheckFindingRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  static func detachedRecords(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as type: SharedDeletedRecord.Type
  ) throws -> [SharedDeletedRecord] {
    try retainedDetachedRecords(from: snapshot, step: step, as: type)
  }

  private static func bridgeRecordSnapshotSort(
    _ lhs: HerdSharingBridgeRecordSnapshot,
    _ rhs: HerdSharingBridgeRecordSnapshot
  ) -> Bool {
    if lhs.lastMirroredAt != rhs.lastMirroredAt {
      return lhs.lastMirroredAt > rhs.lastMirroredAt
    }
    return lhs.sourceObjectURI < rhs.sourceObjectURI
  }
}
