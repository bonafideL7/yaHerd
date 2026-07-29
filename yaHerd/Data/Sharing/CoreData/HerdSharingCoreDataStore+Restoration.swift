//
//  HerdSharingCoreDataStore+Restoration.swift
//  yaHerd
//

import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    from review: HerdSharingConflictReview,
    context: ModelContext
  ) throws -> HerdSharingLocalFieldRestoreResult {
    let indexedChanges = Dictionary(
      uniqueKeysWithValues: review.updatedRecordConflicts.flatMap { conflict in
        conflict.fieldChanges.map { fieldChange in
          (
            restoreSelectionKey(
              sourceEntityName: conflict.sourceEntityName,
              publicID: conflict.publicID,
              fieldName: fieldChange.fieldName
            ),
            (conflict, fieldChange)
          )
        }
      }
    )

    var restoredFieldCount = 0

    for selection in selections {
      guard
        let (_, fieldChange) = indexedChanges[
          restoreSelectionKey(
            sourceEntityName: selection.sourceEntityName,
            publicID: selection.publicID,
            fieldName: selection.fieldName
          )
        ]
      else { continue }

      if try restoreLocalField(
        sourceEntityName: selection.sourceEntityName,
        publicID: selection.publicID,
        fieldName: selection.fieldName,
        value: fieldChange.localValue,
        in: context
      ) {
        restoredFieldCount += 1
      }
    }

    try saveBridgeContextIfNeeded()

    return HerdSharingLocalFieldRestoreResult(
      requestedFieldCount: selections.count,
      restoredFieldCount: restoredFieldCount,
      skippedFieldCount: max(0, selections.count - restoredFieldCount)
    )
  }

  private func restoreSelectionKey(
    sourceEntityName: String,
    publicID: UUID,
    fieldName: String
  ) -> String {
    "\(sourceEntityName)-\(publicID.uuidString)-\(fieldName)"
  }

  private func restoreLocalField(
    sourceEntityName: String,
    publicID: UUID,
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    in context: ModelContext
  ) throws -> Bool {
    switch sourceEntityName {
    case SharedAnimalRecord.entityName:
      guard
        let animal = try fetchSwiftDataRecord(
          Animal.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreAnimalLocalField(fieldName: fieldName, value: value, animal: animal)
    case SharedPastureRecord.entityName:
      guard
        let pasture = try fetchSwiftDataRecord(
          Pasture.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restorePastureLocalField(fieldName: fieldName, value: value, pasture: pasture)
    case SharedHealthRecord.entityName:
      guard
        let healthRecord = try fetchSwiftDataRecord(
          HealthRecord.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreHealthRecordLocalField(
        fieldName: fieldName,
        value: value,
        healthRecord: healthRecord
      )
    case SharedMovementRecord.entityName:
      guard
        let movement = try fetchSwiftDataRecord(
          MovementRecord.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreMovementRecordLocalField(fieldName: fieldName, value: value, movement: movement)
    case SharedPregnancyCheckRecord.entityName:
      guard
        let check = try fetchSwiftDataRecord(
          PregnancyCheck.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restorePregnancyCheckLocalField(fieldName: fieldName, value: value, check: check)
    case SharedStatusRecord.entityName:
      guard
        let statusRecord = try fetchSwiftDataRecord(
          StatusRecord.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreStatusRecordLocalField(
        fieldName: fieldName,
        value: value,
        statusRecord: statusRecord
      )
    case SharedAnimalTagRecord.entityName:
      guard
        let tag = try fetchSwiftDataRecord(
          AnimalTag.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreAnimalTagLocalField(fieldName: fieldName, value: value, tag: tag)
    case SharedTagColorDefinitionRecord.entityName:
      guard
        let definition = try fetchSwiftDataRecord(
          TagColorDefinition.self,
          publicID: publicID,
          keyPath: \.id,
          in: context
        )
      else { return false }
      return restoreTagColorDefinitionLocalField(
        fieldName: fieldName,
        value: value,
        definition: definition
      )
    case SharedAnimalStatusReferenceRecord.entityName:
      guard
        let reference = try fetchSwiftDataRecord(
          AnimalStatusReference.self,
          publicID: publicID,
          keyPath: \.id,
          in: context
        )
      else { return false }
      return restoreAnimalStatusReferenceLocalField(
        fieldName: fieldName,
        value: value,
        reference: reference
      )
    case SharedPastureGroupRecord.entityName:
      guard
        let group = try fetchSwiftDataRecord(
          PastureGroup.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restorePastureGroupLocalField(fieldName: fieldName, value: value, group: group)
    case SharedWorkingProtocolTemplateRecord.entityName:
      guard
        let template = try fetchSwiftDataRecord(
          WorkingProtocolTemplate.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreWorkingProtocolTemplateLocalField(
        fieldName: fieldName,
        value: value,
        template: template
      )
    case SharedWorkingSessionRecord.entityName:
      guard
        let session = try fetchSwiftDataRecord(
          WorkingSession.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreWorkingSessionLocalField(fieldName: fieldName, value: value, session: session)
    case SharedWorkingQueueItemRecord.entityName:
      guard
        let queueItem = try fetchSwiftDataRecord(
          WorkingQueueItem.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreWorkingQueueItemLocalField(
        fieldName: fieldName,
        value: value,
        queueItem: queueItem
      )
    case SharedWorkingTreatmentRecord.entityName:
      guard
        let treatmentRecord = try fetchSwiftDataRecord(
          WorkingTreatmentRecord.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreWorkingTreatmentRecordLocalField(
        fieldName: fieldName,
        value: value,
        treatmentRecord: treatmentRecord
      )
    case SharedFieldCheckSessionRecord.entityName:
      guard
        let session = try fetchSwiftDataRecord(
          FieldCheckSession.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreFieldCheckSessionLocalField(
        fieldName: fieldName, value: value, session: session)
    case SharedFieldCheckAnimalCheckRecord.entityName:
      guard
        let check = try fetchSwiftDataRecord(
          FieldCheckAnimalCheck.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreFieldCheckAnimalCheckLocalField(
        fieldName: fieldName, value: value, check: check)
    case SharedFieldCheckFindingRecord.entityName:
      guard
        let finding = try fetchSwiftDataRecord(
          FieldCheckFinding.self,
          publicID: publicID,
          keyPath: \.publicID,
          in: context
        )
      else { return false }
      return restoreFieldCheckFindingLocalField(
        fieldName: fieldName, value: value, finding: finding)
    default:
      return false
    }
  }

  private func restoreTagColorDefinitionLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    definition: TagColorDefinition
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      definition.name = stringValue
    case "prefix":
      guard let stringValue = value.stringValue else { return false }
      definition.prefix = stringValue
    case "red":
      guard let doubleValue = value.doubleValue else { return false }
      definition.red = doubleValue
    case "green":
      guard let doubleValue = value.doubleValue else { return false }
      definition.green = doubleValue
    case "blue":
      guard let doubleValue = value.doubleValue else { return false }
      definition.blue = doubleValue
    case "alpha":
      guard let doubleValue = value.doubleValue else { return false }
      definition.alpha = doubleValue
    case "sortOrder":
      guard let intValue = value.intValue else { return false }
      definition.sortOrder = intValue
    case "isHidden":
      guard let boolValue = value.boolValue else { return false }
      definition.isHidden = boolValue
    case "isDefault":
      guard let boolValue = value.boolValue else { return false }
      definition.isDefault = boolValue
    case "createdAt":
      guard let dateValue = value.dateValue else { return false }
      definition.createdAt = dateValue
    case "updatedAt":
      guard let dateValue = value.dateValue else { return false }
      definition.updatedAt = dateValue
    default:
      return false
    }

    return true
  }

  private func restoreAnimalStatusReferenceLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    reference: AnimalStatusReference
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      reference.name = stringValue
    case "baseStatus":
      guard let rawValue = value.stringValue, let status = AnimalStatus(rawValue: rawValue) else {
        return false
      }
      reference.baseStatus = status
    case "createdAt":
      guard let dateValue = value.dateValue else { return false }
      reference.createdAt = dateValue
    default:
      return false
    }

    return true
  }

  private func restorePastureGroupLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    group: PastureGroup
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      group.name = stringValue
    case "grazeDays":
      guard let intValue = value.intValue else { return false }
      group.grazeDays = intValue
    case "restDays":
      guard let intValue = value.intValue else { return false }
      group.restDays = intValue
    default:
      return false
    }

    return true
  }

  private func restoreWorkingProtocolTemplateLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    template: WorkingProtocolTemplate
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      template.name = stringValue
    default:
      return false
    }

    return true
  }

  private func restoreAnimalLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    animal: Animal
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      animal.name = stringValue
    case "tagNumber":
      guard let stringValue = value.stringValue else { return false }
      animal.tagNumber = stringValue
    case "tagColorID":
      if value.isNull {
        animal.tagColorID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        animal.tagColorID = uuidValue
      }
    case "sex":
      guard let rawValue = value.stringValue, let sex = Sex(rawValue: rawValue) else {
        return false
      }
      animal.sex = sex
    case "birthDate":
      guard let dateValue = value.dateValue else { return false }
      animal.birthDate = dateValue
    case "status":
      guard let rawValue = value.stringValue, let status = AnimalStatus(rawValue: rawValue) else {
        return false
      }
      animal.status = status
    case "saleDate":
      if value.isNull {
        animal.saleDate = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        animal.saleDate = dateValue
      }
    case "salePrice":
      if value.isNull {
        animal.salePrice = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        animal.salePrice = doubleValue
      }
    case "reasonSold":
      if value.isNull {
        animal.reasonSold = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        animal.reasonSold = stringValue
      }
    case "deathDate":
      if value.isNull {
        animal.deathDate = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        animal.deathDate = dateValue
      }
    case "causeOfDeath":
      if value.isNull {
        animal.causeOfDeath = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        animal.causeOfDeath = stringValue
      }
    case "statusReferenceID":
      if value.isNull {
        animal.statusReferenceID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        animal.statusReferenceID = uuidValue
      }
    case "isSoftDeleted":
      guard let boolValue = value.boolValue else { return false }
      animal.isSoftDeleted = boolValue
    case "softDeletedAt":
      if value.isNull {
        animal.softDeletedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        animal.softDeletedAt = dateValue
      }
    case "softDeleteReason":
      if value.isNull {
        animal.softDeleteReason = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        animal.softDeleteReason = stringValue
      }
    case "location":
      guard let rawValue = value.stringValue, let location = AnimalLocation(rawValue: rawValue)
      else {
        return false
      }
      animal.location = location
    default:
      return false
    }

    return true
  }

  private func restorePastureLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    pasture: Pasture
  ) -> Bool {
    switch fieldName {
    case "name":
      guard let stringValue = value.stringValue else { return false }
      pasture.name = stringValue
    case "sortOrder":
      guard let intValue = value.intValue else { return false }
      pasture.sortOrder = intValue
    case "acreage":
      if value.isNull {
        pasture.acreage = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        pasture.acreage = doubleValue
      }
    case "usableAcreage":
      if value.isNull {
        pasture.usableAcreage = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        pasture.usableAcreage = doubleValue
      }
    case "targetAcresPerHead":
      if value.isNull {
        pasture.targetAcresPerHead = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        pasture.targetAcresPerHead = doubleValue
      }
    case "lastGrazedDate":
      if value.isNull {
        pasture.lastGrazedDate = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        pasture.lastGrazedDate = dateValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreHealthRecordLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    healthRecord: HealthRecord
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      healthRecord.date = dateValue
    case "treatment":
      guard let stringValue = value.stringValue else { return false }
      healthRecord.treatment = stringValue
    case "notes":
      if value.isNull {
        healthRecord.notes = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        healthRecord.notes = stringValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreMovementRecordLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    movement: MovementRecord
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      movement.date = dateValue
    case "fromPasture":
      if value.isNull {
        movement.fromPasture = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        movement.fromPasture = stringValue
      }
    case "toPasture":
      if value.isNull {
        movement.toPasture = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        movement.toPasture = stringValue
      }
    default:
      return false
    }

    return true
  }

  private func restorePregnancyCheckLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    check: PregnancyCheck
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      check.date = dateValue
    case "result":
      guard let rawValue = value.stringValue, let result = PregnancyResult(rawValue: rawValue)
      else {
        return false
      }
      check.result = result
    case "technician":
      if value.isNull {
        check.technician = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        check.technician = stringValue
      }
    case "estimatedDaysPregnant":
      if value.isNull {
        check.estimatedDaysPregnant = nil
      } else {
        guard let intValue = value.intValue else { return false }
        check.estimatedDaysPregnant = intValue
      }
    case "dueDate":
      if value.isNull {
        check.dueDate = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        check.dueDate = dateValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreStatusRecordLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    statusRecord: StatusRecord
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      statusRecord.date = dateValue
    case "oldStatus":
      guard let rawValue = value.stringValue, let status = AnimalStatus(rawValue: rawValue) else {
        return false
      }
      statusRecord.oldStatus = status
    case "newStatus":
      guard let rawValue = value.stringValue, let status = AnimalStatus(rawValue: rawValue) else {
        return false
      }
      statusRecord.newStatus = status
    case "oldStatusReferenceID":
      if value.isNull {
        statusRecord.oldStatusReferenceID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        statusRecord.oldStatusReferenceID = uuidValue
      }
    case "newStatusReferenceID":
      if value.isNull {
        statusRecord.newStatusReferenceID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        statusRecord.newStatusReferenceID = uuidValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreAnimalTagLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    tag: AnimalTag
  ) -> Bool {
    switch fieldName {
    case "number":
      guard let stringValue = value.stringValue else { return false }
      tag.number = stringValue
    case "colorID":
      if value.isNull {
        tag.colorID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        tag.colorID = uuidValue
      }
    case "isPrimary":
      guard let boolValue = value.boolValue else { return false }
      tag.isPrimary = boolValue
    case "isActive":
      guard let boolValue = value.boolValue else { return false }
      tag.isActive = boolValue
    case "assignedAt":
      guard let dateValue = value.dateValue else { return false }
      tag.assignedAt = dateValue
    case "removedAt":
      if value.isNull {
        tag.removedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        tag.removedAt = dateValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreWorkingSessionLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    session: WorkingSession
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      session.date = dateValue
    case "status":
      guard let rawValue = value.stringValue, let status = WorkingSessionStatus(rawValue: rawValue)
      else {
        return false
      }
      session.status = status
    case "protocolName":
      guard let stringValue = value.stringValue else { return false }
      session.protocolName = stringValue
    case "currentQueueIndex":
      guard let intValue = value.intValue else { return false }
      session.currentQueueIndex = intValue
    case "notes":
      if value.isNull {
        session.notes = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        session.notes = stringValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreWorkingQueueItemLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    queueItem: WorkingQueueItem
  ) -> Bool {
    switch fieldName {
    case "queueOrder":
      guard let intValue = value.intValue else { return false }
      queueItem.queueOrder = intValue
    case "status":
      guard let rawValue = value.stringValue, let status = WorkingQueueStatus(rawValue: rawValue)
      else {
        return false
      }
      queueItem.status = status
    case "completedAt":
      if value.isNull {
        queueItem.completedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        queueItem.completedAt = dateValue
      }
    case "workNotes":
      if value.isNull {
        queueItem.workNotes = nil
      } else {
        guard let stringValue = value.stringValue else { return false }
        queueItem.workNotes = stringValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreWorkingTreatmentRecordLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    treatmentRecord: WorkingTreatmentRecord
  ) -> Bool {
    switch fieldName {
    case "date":
      guard let dateValue = value.dateValue else { return false }
      treatmentRecord.date = dateValue
    case "itemName":
      guard let stringValue = value.stringValue else { return false }
      treatmentRecord.itemName = stringValue
    case "given":
      guard let boolValue = value.boolValue else { return false }
      treatmentRecord.given = boolValue
    case "quantity", "doseAmount":
      if value.isNull {
        treatmentRecord.doseAmount = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        treatmentRecord.doseAmount = doubleValue
      }
    case "doseUnit":
      if value.isNull {
        treatmentRecord.doseUnit = nil
      } else {
        guard
          let rawValue = value.stringValue,
          let doseUnit = WorkingTreatmentDoseUnit(rawValue: rawValue)
        else { return false }
        treatmentRecord.doseUnit = doseUnit
      }
    case "administrationRoute":
      if value.isNull {
        treatmentRecord.administrationRoute = nil
      } else {
        guard
          let rawValue = value.stringValue,
          let route = WorkingTreatmentAdministrationRoute(rawValue: rawValue)
        else { return false }
        treatmentRecord.administrationRoute = route
      }
    default:
      return false
    }

    return true
  }

  private func restoreFieldCheckSessionLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    session: FieldCheckSession
  ) -> Bool {
    switch fieldName {
    case "startedAt":
      guard let dateValue = value.dateValue else { return false }
      session.startedAt = dateValue
    case "completedAt":
      if value.isNull {
        session.completedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        session.completedAt = dateValue
      }
    case "notes":
      guard let stringValue = value.stringValue else { return false }
      session.notes = stringValue
    case "expectedHeadCountSnapshot":
      guard let intValue = value.intValue else { return false }
      session.expectedHeadCountSnapshot = intValue
    case "quickCowCount":
      guard let intValue = value.intValue else { return false }
      session.quickCowCount = intValue
    case "quickHeiferCount":
      guard let intValue = value.intValue else { return false }
      session.quickHeiferCount = intValue
    case "quickCalfCount":
      guard let intValue = value.intValue else { return false }
      session.quickCalfCount = intValue
    case "quickBullCount":
      guard let intValue = value.intValue else { return false }
      session.quickBullCount = intValue
    case "quickSteerCount":
      guard let intValue = value.intValue else { return false }
      session.quickSteerCount = intValue
    case "pastureNameSnapshot":
      guard let stringValue = value.stringValue else { return false }
      session.pastureNameSnapshot = stringValue
    case "pastureArchivedAt":
      if value.isNull {
        session.pastureArchivedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        session.pastureArchivedAt = dateValue
      }
    case "pastureID":
      if value.isNull {
        session.pastureID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        session.pastureID = uuidValue
      }
    default:
      return false
    }

    return true
  }

  private func restoreFieldCheckAnimalCheckLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    check: FieldCheckAnimalCheck
  ) -> Bool {
    switch fieldName {
    case "animalIDSnapshot":
      if value.isNull {
        check.animalIDSnapshot = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        check.animalIDSnapshot = uuidValue
      }
    case "rosterTagNumber":
      guard let stringValue = value.stringValue else { return false }
      check.rosterTagNumber = stringValue
    case "rosterTagColorID":
      if value.isNull {
        check.rosterTagColorID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        check.rosterTagColorID = uuidValue
      }
    case "damRosterTagNumber":
      guard let stringValue = value.stringValue else { return false }
      check.damRosterTagNumber = stringValue
    case "damRosterTagColorID":
      if value.isNull {
        check.damRosterTagColorID = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        check.damRosterTagColorID = uuidValue
      }
    case "animalName":
      guard let stringValue = value.stringValue else { return false }
      check.animalName = stringValue
    case "animalSex":
      guard let rawValue = value.stringValue, let sex = Sex(rawValue: rawValue) else {
        return false
      }
      check.animalSex = sex
    case "animalTypeSnapshot":
      guard let rawValue = value.stringValue, let animalType = AnimalType(rawValue: rawValue) else {
        return false
      }
      check.animalTypeSnapshot = animalType
    case "wasExpectedAtStart":
      guard let boolValue = value.boolValue else { return false }
      check.wasExpectedAtStart = boolValue
    case "countedAt":
      if value.isNull {
        check.countedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        check.countedAt = dateValue
      }
    case "missingConfirmedAt":
      if value.isNull {
        check.missingConfirmedAt = nil
      } else {
        guard let dateValue = value.dateValue else { return false }
        check.missingConfirmedAt = dateValue
      }
    case "note":
      guard let stringValue = value.stringValue else { return false }
      check.note = stringValue
    default:
      return false
    }

    return true
  }

  private func restoreFieldCheckFindingLocalField(
    fieldName: String,
    value: HerdSharingConflictStoredValue,
    finding: FieldCheckFinding
  ) -> Bool {
    switch fieldName {
    case "recordedAt":
      guard let dateValue = value.dateValue else { return false }
      finding.recordedAt = dateValue
    case "type":
      guard let rawValue = value.stringValue, let type = FieldCheckFindingType(rawValue: rawValue)
      else {
        return false
      }
      finding.type = type
    case "severity":
      guard let rawValue = value.stringValue,
        let severity = FieldCheckFindingSeverity(rawValue: rawValue)
      else {
        return false
      }
      finding.severity = severity
    case "status":
      guard let rawValue = value.stringValue,
        let status = FieldCheckFindingStatus(rawValue: rawValue)
      else {
        return false
      }
      finding.status = status
    case "note":
      guard let stringValue = value.stringValue else { return false }
      finding.note = stringValue
    case "animalIDSnapshot":
      if value.isNull {
        finding.animalIDSnapshot = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        finding.animalIDSnapshot = uuidValue
      }
    case "animalDisplayTagNumberSnapshot":
      guard let stringValue = value.stringValue else { return false }
      finding.animalDisplayTagNumberSnapshot = stringValue
    case "animalDisplayTagColorIDSnapshot":
      if value.isNull {
        finding.animalDisplayTagColorIDSnapshot = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        finding.animalDisplayTagColorIDSnapshot = uuidValue
      }
    case "animalNameSnapshot":
      guard let stringValue = value.stringValue else { return false }
      finding.animalNameSnapshot = stringValue
    case "pastureNameSnapshot":
      guard let stringValue = value.stringValue else { return false }
      finding.pastureNameSnapshot = stringValue
    case "sessionIDSnapshot":
      if value.isNull {
        finding.sessionIDSnapshot = nil
      } else {
        guard let uuidValue = value.uuidValue else { return false }
        finding.sessionIDSnapshot = uuidValue
      }
    default:
      return false
    }

    return true
  }
}
