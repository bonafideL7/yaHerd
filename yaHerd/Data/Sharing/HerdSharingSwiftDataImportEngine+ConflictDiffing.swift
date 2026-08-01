//
//  HerdSharingCoreDataStore+ConflictDiffing.swift
//  yaHerd
//

import Foundation

enum HerdSharingSwiftDataImportEngine {
  typealias HerdSharingConflictFieldSnapshot = [String: HerdSharingBridgeConflictValue]

  static func updatedRecordConflict(
    sourceEntityName: String,
    publicID: UUID,
    localModifiedAt: Date?,
    sharedModifiedAt: Date?,
    before: HerdSharingConflictFieldSnapshot,
    after: HerdSharingConflictFieldSnapshot
  ) -> HerdSharingBridgeConflictDetail {
    updatedRecordConflict(
      sourceEntityName: sourceEntityName,
      publicID: publicID,
      localModifiedAt: localModifiedAt,
      sharedModifiedAt: sharedModifiedAt,
      fieldChanges: conflictFieldChanges(before: before, after: after)
    )
  }

  static func updatedRecordConflict(
    sourceEntityName: String,
    publicID: UUID,
    localModifiedAt: Date?,
    sharedModifiedAt: Date?,
    fieldChanges: [HerdSharingBridgeFieldChange] = []
  ) -> HerdSharingBridgeConflictDetail {
    HerdSharingBridgeConflictDetail(
      kind: .existingLocalRecordUpdate,
      sourceEntityName: sourceEntityName,
      publicID: publicID,
      localModifiedAt: localModifiedAt ?? .distantPast,
      sharedModifiedAt: sharedModifiedAt ?? .distantPast,
      fieldChanges: fieldChanges
    )
  }

  private static func conflictFieldChanges(
    before: HerdSharingConflictFieldSnapshot,
    after: HerdSharingConflictFieldSnapshot
  ) -> [HerdSharingBridgeFieldChange] {
    let fieldNames = Set(before.keys).union(after.keys)
    return fieldNames.sorted().compactMap { fieldName in
      let localValue = before[fieldName] ?? .null
      let sharedValue = after[fieldName] ?? .null
      guard localValue != sharedValue else { return nil }
      return HerdSharingBridgeFieldChange(
        fieldName: fieldName,
        localValue: localValue,
        sharedValue: sharedValue
      )
    }
  }

  private static func conflictValue(_ value: Any?) -> HerdSharingBridgeConflictValue {
    guard let value else { return .null }
    if let date = value as? Date {
      return HerdSharingBridgeConflictValue(
        type: .date,
        encodedValue: ISO8601DateFormatter().string(from: date)
      )
    }
    if let uuid = value as? UUID {
      return HerdSharingBridgeConflictValue(type: .uuid, encodedValue: uuid.uuidString)
    }
    if let bool = value as? Bool {
      return HerdSharingBridgeConflictValue(
        type: .bool,
        encodedValue: bool ? "true" : "false"
      )
    }
    if let int = value as? Int {
      return HerdSharingBridgeConflictValue(type: .int, encodedValue: String(int))
    }
    if let double = value as? Double {
      return HerdSharingBridgeConflictValue(type: .double, encodedValue: String(double))
    }
    if let float = value as? Float {
      return HerdSharingBridgeConflictValue(type: .double, encodedValue: String(Double(float)))
    }
    if let string = value as? String {
      return HerdSharingBridgeConflictValue(type: .string, encodedValue: string)
    }
    return HerdSharingBridgeConflictValue(type: .string, encodedValue: String(describing: value))
  }

  private static func conflictFieldSnapshot(_ values: [String: Any?]) -> HerdSharingConflictFieldSnapshot {
    values.reduce(into: HerdSharingConflictFieldSnapshot()) { result, item in
      result[item.key] = conflictValue(item.value)
    }
  }

  static func conflictFieldSnapshot(for definition: TagColorDefinition) -> HerdSharingConflictFieldSnapshot
  {
    conflictFieldSnapshot([
      "name": definition.name,
      "prefix": definition.prefix,
      "red": definition.red,
      "green": definition.green,
      "blue": definition.blue,
      "alpha": definition.alpha,
      "sortOrder": definition.sortOrder,
      "isHidden": definition.isHidden,
      "isDefault": definition.isDefault,
      "createdAt": definition.createdAt,
      "updatedAt": definition.updatedAt,
    ])
  }

  static func conflictFieldSnapshot(for reference: AnimalStatusReference)
    -> HerdSharingConflictFieldSnapshot
  {
    conflictFieldSnapshot([
      "name": reference.name,
      "baseStatus": reference.baseStatus,
      "createdAt": reference.createdAt,
    ])
  }

  static func conflictFieldSnapshot(for group: PastureGroup) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": group.name,
      "grazeDays": group.grazeDays,
      "restDays": group.restDays,
    ])
  }

  static func conflictFieldSnapshot(for pasture: Pasture) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": pasture.name,
      "sortOrder": pasture.sortOrder,
      "acreage": pasture.acreage,
      "usableAcreage": pasture.usableAcreage,
      "targetAcresPerHead": pasture.targetAcresPerHead,
      "lastGrazedDate": pasture.lastGrazedDate,
      "groupPublicID": pasture.group?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for animal: Animal) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": animal.name,
      "tagNumber": animal.tagNumber,
      "tagColorID": animal.tagColorID,
      "sex": animal.sex,
      "birthDate": animal.birthDate,
      "status": animal.status,
      "saleDate": animal.saleDate,
      "salePrice": animal.salePrice,
      "reasonSold": animal.reasonSold,
      "deathDate": animal.deathDate,
      "causeOfDeath": animal.causeOfDeath,
      "statusReferenceID": animal.statusReferenceID,
      "isSoftDeleted": animal.isSoftDeleted,
      "softDeletedAt": animal.softDeletedAt,
      "softDeleteReason": animal.softDeleteReason,
      "location": animal.location,
      "pasturePublicID": animal.pasture?.publicID,
      "distinguishingFeatures": animal.distinguishingFeatures,
    ])
  }

  static func conflictFieldSnapshot(for tag: AnimalTag) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "number": tag.number,
      "colorID": tag.colorID,
      "isPrimary": tag.isPrimary,
      "isActive": tag.isActive,
      "assignedAt": tag.assignedAt,
      "removedAt": tag.removedAt,
      "animalPublicID": tag.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for movement: MovementRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": movement.date,
      "fromPasture": movement.fromPasture,
      "toPasture": movement.toPasture,
      "animalPublicID": movement.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for statusRecord: StatusRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": statusRecord.date,
      "oldStatus": statusRecord.oldStatus,
      "newStatus": statusRecord.newStatus,
      "oldStatusReferenceID": statusRecord.oldStatusReferenceID,
      "newStatusReferenceID": statusRecord.newStatusReferenceID,
      "animalPublicID": statusRecord.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for template: WorkingProtocolTemplate)
    -> HerdSharingConflictFieldSnapshot
  {
    conflictFieldSnapshot([
      "name": template.name,
      "items": template.items,
    ])
  }

  static func conflictFieldSnapshot(for session: WorkingSession) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": session.date,
      "status": session.status,
      "sourcePasturePublicID": session.sourcePasture?.publicID,
      "protocolName": session.protocolName,
      "protocolItems": session.protocolItems,
      "currentQueueIndex": session.currentQueueIndex,
      "notes": session.notes,
    ])
  }

  static func conflictFieldSnapshot(for queueItem: WorkingQueueItem) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "queueOrder": queueItem.queueOrder,
      "status": queueItem.status,
      "completedAt": queueItem.completedAt,
      "collectedFromPasturePublicID": queueItem.collectedFromPasture?.publicID,
      "destinationPasturePublicID": queueItem.destinationPasture?.publicID,
      "workNotes": queueItem.workNotes,
      "sessionPublicID": queueItem.session?.publicID,
      "animalPublicID": queueItem.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for treatmentRecord: WorkingTreatmentRecord)
    -> HerdSharingConflictFieldSnapshot
  {
    conflictFieldSnapshot([
      "date": treatmentRecord.date,
      "itemName": treatmentRecord.itemName,
      "given": treatmentRecord.given,
      "quantity": treatmentRecord.quantity,
      "sessionPublicID": treatmentRecord.session?.publicID,
      "animalPublicID": treatmentRecord.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for healthRecord: HealthRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": healthRecord.date,
      "treatment": healthRecord.treatment,
      "notes": healthRecord.notes,
      "workingSessionPublicID": healthRecord.workingSession?.publicID,
      "animalPublicID": healthRecord.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for check: PregnancyCheck) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": check.date,
      "result": check.result,
      "technician": check.technician,
      "estimatedDaysPregnant": check.estimatedDaysPregnant,
      "dueDate": check.dueDate,
      "sireAnimalPublicID": check.sireAnimal?.publicID,
      "workingSessionPublicID": check.workingSession?.publicID,
      "animalPublicID": check.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for session: FieldCheckSession) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "startedAt": session.startedAt,
      "completedAt": session.completedAt,
      "notes": session.notes,
      "expectedHeadCountSnapshot": session.expectedHeadCountSnapshot,
      "quickCowCount": session.quickCowCount,
      "quickHeiferCount": session.quickHeiferCount,
      "quickCalfCount": session.quickCalfCount,
      "quickBullCount": session.quickBullCount,
      "quickSteerCount": session.quickSteerCount,
      "pastureNameSnapshot": session.pastureNameSnapshot,
      "pastureArchivedAt": session.pastureArchivedAt,
      "pastureID": session.pastureID,
      "pasturePublicID": session.pasture?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for check: FieldCheckAnimalCheck) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "animalIDSnapshot": check.animalIDSnapshot,
      "rosterTagNumber": check.rosterTagNumber,
      "rosterTagColorID": check.rosterTagColorID,
      "damRosterTagNumber": check.damRosterTagNumber,
      "damRosterTagColorID": check.damRosterTagColorID,
      "animalName": check.animalName,
      "animalSex": check.animalSex,
      "animalTypeSnapshot": check.animalTypeSnapshot,
      "wasExpectedAtStart": check.wasExpectedAtStart,
      "countedAt": check.countedAt,
      "missingConfirmedAt": check.missingConfirmedAt,
      "note": check.note,
      "sessionPublicID": check.session?.publicID,
      "animalPublicID": check.animal?.publicID,
    ])
  }

  static func conflictFieldSnapshot(for finding: FieldCheckFinding) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "recordedAt": finding.recordedAt,
      "type": finding.type,
      "severity": finding.severity,
      "status": finding.status,
      "note": finding.note,
      "animalIDSnapshot": finding.animalIDSnapshot,
      "animalDisplayTagNumberSnapshot": finding.animalDisplayTagNumberSnapshot,
      "animalDisplayTagColorIDSnapshot": finding.animalDisplayTagColorIDSnapshot,
      "animalNameSnapshot": finding.animalNameSnapshot,
      "pastureNameSnapshot": finding.pastureNameSnapshot,
      "sessionIDSnapshot": finding.sessionIDSnapshot,
      "sessionPublicID": finding.session?.publicID,
      "animalPublicID": finding.animal?.publicID,
    ])
  }
}
