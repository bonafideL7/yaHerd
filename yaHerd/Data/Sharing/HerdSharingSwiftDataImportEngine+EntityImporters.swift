//
//  HerdSharingCoreDataStore+EntityImporters.swift
//  yaHerd
//

import CoreData
import Foundation
import SwiftData

extension HerdSharingSwiftDataImportEngine {
  static func upsertSwiftDataHerd(
    from sharedRecord: SharedHerdRecord,
    in context: ModelContext
  ) throws -> Herd {
    guard let sharedPublicID = sharedRecord.parsedPublicID else {
      throw HerdSharingActionError.bridgeImportFailed(
        "The shared herd record is missing a valid public ID.")
    }

    if let existingHerd = try HerdSharingSwiftDataMutationEngine.fetchSwiftDataHerd(publicID: sharedPublicID, in: context) {
      apply(sharedRecord, to: existingHerd)
      return existingHerd
    }

    let herd = try DefaultHerdBootstrapper.defaultHerd(in: context)
    herd.publicID = sharedPublicID
    apply(sharedRecord, to: herd)
    return herd
  }

  private static func apply(_ sharedRecord: SharedHerdRecord, to herd: Herd) {
    herd.name =
      sharedRecord.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? DefaultHerdBootstrapper.defaultHerdName
    herd.createdAt = sharedRecord.createdAt ?? herd.createdAt
    herd.updatedAt = sharedRecord.updatedAt ?? Date.now
    herd.schemaVersion = sharedRecord.schemaVersion?.intValue ?? herd.schemaVersion
  }

  static func upsertSwiftDataTagColorDefinitions(
    from sharedRecords: [SharedTagColorDefinitionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedTagColorDefinitionRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var definitionsByPublicID: [UUID: TagColorDefinition] = [:]
    for definition in try context.fetch(FetchDescriptor<TagColorDefinition>())
    where definitionsByPublicID[definition.id] == nil {
      definitionsByPublicID[definition.id] = definition
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let definition: TagColorDefinition
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingDefinition = definitionsByPublicID[publicID] {
        definition = existingDefinition
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: definition)
      } else {
        definition = TagColorDefinition(
          id: publicID,
          name: record.name ?? "",
          prefix: record.prefix,
          rgba: record.parsedRGBA,
          sortOrder: record.sortOrder?.intValue ?? 0,
          isHidden: record.isHidden?.boolValue ?? false,
          isDefault: record.isDefault?.boolValue ?? false,
          createdAt: record.createdAt ?? Date.now,
          updatedAt: record.updatedAt ?? Date.now
        )
        context.insert(definition)
        definitionsByPublicID[publicID] = definition
        inserted += 1
      }

      apply(record, to: definition, herd: herd)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedTagColorDefinitionRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: definition)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedTagColorDefinitionRecord,
    to definition: TagColorDefinition,
    herd: Herd
  ) {
    definition.herd = herd
    definition.name = sharedRecord.name ?? ""
    definition.prefix = sharedRecord.prefix ?? ""
    definition.red = sharedRecord.red?.doubleValue ?? definition.red
    definition.green = sharedRecord.green?.doubleValue ?? definition.green
    definition.blue = sharedRecord.blue?.doubleValue ?? definition.blue
    definition.alpha = sharedRecord.alpha?.doubleValue ?? definition.alpha
    definition.sortOrder = sharedRecord.sortOrder?.intValue ?? definition.sortOrder
    definition.isHidden = sharedRecord.isHidden?.boolValue ?? false
    definition.isDefault = sharedRecord.isDefault?.boolValue ?? false
    definition.createdAt = sharedRecord.createdAt ?? definition.createdAt
    definition.updatedAt = sharedRecord.updatedAt ?? definition.updatedAt
  }

  static func upsertSwiftDataStatusReferences(
    from sharedRecords: [SharedAnimalStatusReferenceRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedAnimalStatusReferenceRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var referencesByPublicID: [UUID: AnimalStatusReference] = [:]
    for reference in try context.fetch(FetchDescriptor<AnimalStatusReference>())
    where referencesByPublicID[reference.id] == nil {
      referencesByPublicID[reference.id] = reference
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let reference: AnimalStatusReference
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingReference = referencesByPublicID[publicID] {
        reference = existingReference
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: reference)
      } else {
        reference = AnimalStatusReference(
          id: publicID,
          name: record.name ?? "",
          baseStatus: record.parsedBaseStatus,
          createdAt: record.createdAt ?? Date.now
        )
        context.insert(reference)
        referencesByPublicID[publicID] = reference
        inserted += 1
      }

      apply(record, to: reference, herd: herd)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedAnimalStatusReferenceRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: reference)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedAnimalStatusReferenceRecord,
    to reference: AnimalStatusReference,
    herd: Herd
  ) {
    reference.herd = herd
    reference.name = sharedRecord.name ?? ""
    reference.baseStatus = sharedRecord.parsedBaseStatus
    reference.createdAt = sharedRecord.createdAt ?? reference.createdAt
  }

  static func upsertSwiftDataPastureGroups(
    from sharedRecords: [SharedPastureGroupRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedPastureGroupRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var groupsByPublicID: [UUID: PastureGroup] = [:]
    for group in try context.fetch(FetchDescriptor<PastureGroup>())
    where groupsByPublicID[group.publicID] == nil {
      groupsByPublicID[group.publicID] = group
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let group: PastureGroup
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingGroup = groupsByPublicID[publicID] {
        group = existingGroup
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: group)
      } else {
        group = PastureGroup(
          publicID: publicID,
          name: record.name ?? "",
          grazeDays: record.grazeDays?.intValue ?? 7,
          restDays: record.restDays?.intValue ?? 21
        )
        context.insert(group)
        groupsByPublicID[publicID] = group
        inserted += 1
      }

      apply(record, to: group, herd: herd)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedPastureGroupRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: group)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedPastureGroupRecord,
    to group: PastureGroup,
    herd: Herd
  ) {
    group.herd = herd
    group.name = sharedRecord.name ?? ""
    group.grazeDays = sharedRecord.grazeDays?.intValue ?? group.grazeDays
    group.restDays = sharedRecord.restDays?.intValue ?? group.restDays
  }

  static func upsertSwiftDataPastures(
    from sharedRecords: [SharedPastureRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap { record -> (SharedPastureRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var pasturesByPublicID: [UUID: Pasture] = [:]
    for pasture in try context.fetch(FetchDescriptor<Pasture>())
    where pasturesByPublicID[pasture.publicID] == nil {
      pasturesByPublicID[pasture.publicID] = pasture
    }

    var groupsByPublicID: [UUID: PastureGroup] = [:]
    for group in try context.fetch(FetchDescriptor<PastureGroup>())
    where groupsByPublicID[group.publicID] == nil {
      groupsByPublicID[group.publicID] = group
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let pasture: Pasture
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingPasture = pasturesByPublicID[publicID] {
        pasture = existingPasture
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: pasture)
      } else {
        pasture = Pasture(
          publicID: publicID,
          name: record.name ?? "",
          acreage: record.acreage?.doubleValue,
          usableAcreage: record.usableAcreage?.doubleValue,
          targetAcresPerHead: record.targetAcresPerHead?.doubleValue,
          sortOrder: record.sortOrder?.intValue ?? 0
        )
        context.insert(pasture)
        pasturesByPublicID[publicID] = pasture
        inserted += 1
      }

      apply(record, to: pasture, herd: herd, groupsByPublicID: groupsByPublicID)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedPastureRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: pasture)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedPastureRecord,
    to pasture: Pasture,
    herd: Herd,
    groupsByPublicID: [UUID: PastureGroup]
  ) {
    pasture.herd = herd
    pasture.name = sharedRecord.name ?? ""
    pasture.sortOrder = sharedRecord.sortOrder?.intValue ?? pasture.sortOrder
    pasture.acreage = sharedRecord.acreage?.doubleValue
    pasture.usableAcreage = sharedRecord.usableAcreage?.doubleValue
    pasture.targetAcresPerHead = sharedRecord.targetAcresPerHead?.doubleValue
    pasture.lastGrazedDate = sharedRecord.lastGrazedDate
    pasture.group = sharedRecord.parsedGroupPublicID.flatMap { groupsByPublicID[$0] }
  }

  static func upsertSwiftDataAnimals(
    from sharedRecords: [SharedAnimalRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap { record -> (SharedAnimalRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var pasturesByPublicID: [UUID: Pasture] = [:]
    for pasture in try context.fetch(FetchDescriptor<Pasture>())
    where pasturesByPublicID[pasture.publicID] == nil {
      pasturesByPublicID[pasture.publicID] = pasture
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let animal: Animal
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingAnimal = animalsByPublicID[publicID] {
        animal = existingAnimal
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: animal)
      } else {
        animal = Animal(
          publicID: publicID,
          name: record.name ?? "",
          tagNumber: record.tagNumber ?? "",
          tagColorID: record.parsedTagColorID,
          birthDate: record.birthDate ?? Date.now,
          status: record.parsedStatus,
          saleDate: record.saleDate,
          salePrice: record.salePrice?.doubleValue,
          reasonSold: record.reasonSold,
          deathDate: record.deathDate,
          causeOfDeath: record.causeOfDeath,
          statusReferenceID: record.parsedStatusReferenceID,
          isSoftDeleted: record.isSoftDeleted?.boolValue ?? false,
          softDeletedAt: record.softDeletedAt,
          softDeleteReason: record.softDeleteReason,
          sex: record.parsedSex,
          distinguishingFeatures: record.parsedDistinguishingFeatures
        )
        context.insert(animal)
        animalsByPublicID[publicID] = animal
        inserted += 1
      }

      apply(record, to: animal, herd: herd, pasturesByPublicID: pasturesByPublicID)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedAnimalRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: animal)
          )
        )
      }
    }

    for (record, publicID) in validSharedRecords {
      guard let animal = animalsByPublicID[publicID] else { continue }
      animal.sireAnimal = record.parsedSireAnimalPublicID.flatMap { animalsByPublicID[$0] }
      animal.damAnimal = record.parsedDamAnimalPublicID.flatMap { animalsByPublicID[$0] }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedAnimalRecord,
    to animal: Animal,
    herd: Herd,
    pasturesByPublicID: [UUID: Pasture]
  ) {
    animal.herd = herd
    animal.name = sharedRecord.name ?? ""
    animal.tagNumber = sharedRecord.tagNumber ?? ""
    animal.tagColorID = sharedRecord.parsedTagColorID
    animal.sex = sharedRecord.parsedSex
    animal.birthDate = sharedRecord.birthDate ?? animal.birthDate
    animal.status = sharedRecord.parsedStatus
    animal.saleDate = sharedRecord.saleDate
    animal.salePrice = sharedRecord.salePrice?.doubleValue
    animal.reasonSold = sharedRecord.reasonSold
    animal.deathDate = sharedRecord.deathDate
    animal.causeOfDeath = sharedRecord.causeOfDeath
    animal.statusReferenceID = sharedRecord.parsedStatusReferenceID
    animal.isSoftDeleted = sharedRecord.isSoftDeleted?.boolValue ?? false
    animal.softDeletedAt = sharedRecord.softDeletedAt
    animal.softDeleteReason = sharedRecord.softDeleteReason
    animal.location = sharedRecord.parsedLocation
    animal.pasture = sharedRecord.parsedPasturePublicID.flatMap { pasturesByPublicID[$0] }
    animal.distinguishingFeatures = sharedRecord.parsedDistinguishingFeatures
  }

  static func upsertSwiftDataAnimalTags(
    from sharedRecords: [SharedAnimalTagRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedAnimalTagRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var tagsByPublicID: [UUID: AnimalTag] = [:]
    for tag in try context.fetch(FetchDescriptor<AnimalTag>())
    where tagsByPublicID[tag.publicID] == nil {
      tagsByPublicID[tag.publicID] = tag
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, animalPublicID) in validSharedRecords {
      guard let animal = animalsByPublicID[animalPublicID] else { continue }

      let tag: AnimalTag
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingTag = tagsByPublicID[publicID] {
        tag = existingTag
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: tag)
      } else {
        tag = AnimalTag(
          publicID: publicID,
          number: record.number ?? "",
          colorID: record.parsedColorID,
          isPrimary: record.isPrimary?.boolValue ?? false,
          isActive: record.isActive?.boolValue ?? true,
          assignedAt: record.assignedAt ?? Date.now,
          removedAt: record.removedAt,
          animal: animal
        )
        context.insert(tag)
        tagsByPublicID[publicID] = tag
        inserted += 1
      }

      apply(record, to: tag, herd: herd, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedAnimalTagRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: tag)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedAnimalTagRecord,
    to tag: AnimalTag,
    herd: Herd,
    animal: Animal
  ) {
    tag.herd = herd
    tag.animal = animal
    tag.number = sharedRecord.number ?? ""
    tag.colorID = sharedRecord.parsedColorID
    tag.isPrimary = sharedRecord.isPrimary?.boolValue ?? false
    tag.isActive = sharedRecord.isActive?.boolValue ?? true
    tag.assignedAt = sharedRecord.assignedAt ?? tag.assignedAt
    tag.removedAt = sharedRecord.removedAt
  }

  static func upsertSwiftDataMovements(
    from sharedRecords: [SharedMovementRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedMovementRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var movementsByPublicID: [UUID: MovementRecord] = [:]
    for movement in try context.fetch(FetchDescriptor<MovementRecord>())
    where movementsByPublicID[movement.publicID] == nil {
      movementsByPublicID[movement.publicID] = movement
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, animalPublicID) in validSharedRecords {
      guard let animal = animalsByPublicID[animalPublicID] else { continue }

      let movement: MovementRecord
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingMovement = movementsByPublicID[publicID] {
        movement = existingMovement
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: movement)
      } else {
        movement = MovementRecord(
          publicID: publicID,
          date: record.date ?? Date.now,
          fromPasture: record.fromPasture,
          toPasture: record.toPasture,
          animal: animal
        )
        context.insert(movement)
        movementsByPublicID[publicID] = movement
        inserted += 1
      }

      apply(record, to: movement, herd: herd, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedMovementRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: movement)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedMovementRecord,
    to movement: MovementRecord,
    herd: Herd,
    animal: Animal
  ) {
    movement.herd = herd
    movement.animal = animal
    movement.date = sharedRecord.date ?? movement.date
    movement.fromPasture = sharedRecord.fromPasture
    movement.toPasture = sharedRecord.toPasture
  }

  static func upsertSwiftDataStatusRecords(
    from sharedRecords: [SharedStatusRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedStatusRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var statusRecordsByPublicID: [UUID: StatusRecord] = [:]
    for statusRecord in try context.fetch(FetchDescriptor<StatusRecord>())
    where statusRecordsByPublicID[statusRecord.publicID] == nil {
      statusRecordsByPublicID[statusRecord.publicID] = statusRecord
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, animalPublicID) in validSharedRecords {
      guard let animal = animalsByPublicID[animalPublicID] else { continue }

      let statusRecord: StatusRecord
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingStatusRecord = statusRecordsByPublicID[publicID] {
        statusRecord = existingStatusRecord
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: statusRecord)
      } else {
        statusRecord = StatusRecord(
          publicID: publicID,
          date: record.date ?? Date.now,
          oldStatus: record.parsedOldStatus,
          newStatus: record.parsedNewStatus,
          oldStatusReferenceID: record.parsedOldStatusReferenceID,
          newStatusReferenceID: record.parsedNewStatusReferenceID,
          animal: animal
        )
        context.insert(statusRecord)
        statusRecordsByPublicID[publicID] = statusRecord
        inserted += 1
      }

      apply(record, to: statusRecord, herd: herd, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedStatusRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: statusRecord)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedStatusRecord,
    to statusRecord: StatusRecord,
    herd: Herd,
    animal: Animal
  ) {
    statusRecord.herd = herd
    statusRecord.animal = animal
    statusRecord.date = sharedRecord.date ?? statusRecord.date
    statusRecord.oldStatus = sharedRecord.parsedOldStatus
    statusRecord.newStatus = sharedRecord.parsedNewStatus
    statusRecord.oldStatusReferenceID = sharedRecord.parsedOldStatusReferenceID
    statusRecord.newStatusReferenceID = sharedRecord.parsedNewStatusReferenceID
  }

  static func upsertSwiftDataWorkingProtocolTemplates(
    from sharedRecords: [SharedWorkingProtocolTemplateRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedWorkingProtocolTemplateRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var templatesByPublicID: [UUID: WorkingProtocolTemplate] = [:]
    for template in try context.fetch(FetchDescriptor<WorkingProtocolTemplate>())
    where templatesByPublicID[template.publicID] == nil {
      templatesByPublicID[template.publicID] = template
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let template: WorkingProtocolTemplate
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingTemplate = templatesByPublicID[publicID] {
        template = existingTemplate
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: template)
      } else {
        template = WorkingProtocolTemplate(
          publicID: publicID,
          name: record.name ?? "",
          items: record.parsedItems
        )
        context.insert(template)
        templatesByPublicID[publicID] = template
        inserted += 1
      }

      apply(record, to: template, herd: herd)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedWorkingProtocolTemplateRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: template)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedWorkingProtocolTemplateRecord,
    to template: WorkingProtocolTemplate,
    herd: Herd
  ) {
    template.herd = herd
    template.name = sharedRecord.name ?? ""
    template.items = sharedRecord.parsedItems
  }

  static func upsertSwiftDataWorkingSessions(
    from sharedRecords: [SharedWorkingSessionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedWorkingSessionRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var sessionsByPublicID: [UUID: WorkingSession] = [:]
    for session in try context.fetch(FetchDescriptor<WorkingSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var pasturesByPublicID: [UUID: Pasture] = [:]
    for pasture in try context.fetch(FetchDescriptor<Pasture>())
    where pasturesByPublicID[pasture.publicID] == nil {
      pasturesByPublicID[pasture.publicID] = pasture
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let session: WorkingSession
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingSession = sessionsByPublicID[publicID] {
        session = existingSession
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: session)
      } else {
        session = WorkingSession(
          publicID: publicID,
          date: record.date ?? Date.now,
          status: record.parsedStatus,
          sourcePasture: record.parsedSourcePasturePublicID.flatMap { pasturesByPublicID[$0] },
          protocolName: record.protocolName ?? "",
          protocolItems: record.parsedProtocolItems,
          notes: record.notes
        )
        context.insert(session)
        sessionsByPublicID[publicID] = session
        inserted += 1
      }

      apply(record, to: session, herd: herd, pasturesByPublicID: pasturesByPublicID)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedWorkingSessionRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: session)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedWorkingSessionRecord,
    to session: WorkingSession,
    herd: Herd,
    pasturesByPublicID: [UUID: Pasture]
  ) {
    session.herd = herd
    session.date = sharedRecord.date ?? session.date
    session.status = sharedRecord.parsedStatus
    session.sourcePasture = sharedRecord.parsedSourcePasturePublicID.flatMap {
      pasturesByPublicID[$0]
    }
    session.protocolName = sharedRecord.protocolName ?? ""
    session.protocolItems = sharedRecord.parsedProtocolItems
    session.currentQueueIndex =
      sharedRecord.currentQueueIndex?.intValue ?? session.currentQueueIndex
    session.notes = sharedRecord.notes
  }

  static func upsertSwiftDataWorkingQueueItems(
    from sharedRecords: [SharedWorkingQueueItemRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedWorkingQueueItemRecord, UUID, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let sessionPublicID = record.parsedSessionPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, sessionPublicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var queueItemsByPublicID: [UUID: WorkingQueueItem] = [:]
    for queueItem in try context.fetch(FetchDescriptor<WorkingQueueItem>())
    where queueItemsByPublicID[queueItem.publicID] == nil {
      queueItemsByPublicID[queueItem.publicID] = queueItem
    }

    var sessionsByPublicID: [UUID: WorkingSession] = [:]
    for session in try context.fetch(FetchDescriptor<WorkingSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var pasturesByPublicID: [UUID: Pasture] = [:]
    for pasture in try context.fetch(FetchDescriptor<Pasture>())
    where pasturesByPublicID[pasture.publicID] == nil {
      pasturesByPublicID[pasture.publicID] = pasture
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, sessionPublicID, animalPublicID) in validSharedRecords {
      guard let session = sessionsByPublicID[sessionPublicID],
        let animal = animalsByPublicID[animalPublicID]
      else { continue }

      let queueItem: WorkingQueueItem
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingQueueItem = queueItemsByPublicID[publicID] {
        queueItem = existingQueueItem
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: queueItem)
      } else {
        queueItem = WorkingQueueItem(
          publicID: publicID,
          queueOrder: record.queueOrder?.intValue ?? 0,
          status: record.parsedStatus,
          collectedFromPasture: record.parsedCollectedFromPasturePublicID.flatMap {
            pasturesByPublicID[$0]
          },
          destinationPasture: record.parsedDestinationPasturePublicID.flatMap {
            pasturesByPublicID[$0]
          },
          workNotes: record.workNotes,
          animal: animal,
          session: session
        )
        context.insert(queueItem)
        queueItemsByPublicID[publicID] = queueItem
        inserted += 1
      }

      apply(
        record,
        to: queueItem,
        herd: herd,
        session: session,
        animal: animal,
        pasturesByPublicID: pasturesByPublicID
      )
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedWorkingQueueItemRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: queueItem)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedWorkingQueueItemRecord,
    to queueItem: WorkingQueueItem,
    herd: Herd,
    session: WorkingSession,
    animal: Animal,
    pasturesByPublicID: [UUID: Pasture]
  ) {
    queueItem.herd = herd
    queueItem.session = session
    queueItem.animal = animal
    queueItem.queueOrder = sharedRecord.queueOrder?.intValue ?? queueItem.queueOrder
    queueItem.status = sharedRecord.parsedStatus
    queueItem.completedAt = sharedRecord.completedAt
    queueItem.collectedFromPasture = sharedRecord.parsedCollectedFromPasturePublicID.flatMap {
      pasturesByPublicID[$0]
    }
    queueItem.destinationPasture = sharedRecord.parsedDestinationPasturePublicID.flatMap {
      pasturesByPublicID[$0]
    }
    queueItem.workNotes = sharedRecord.workNotes

    if session.status == .active {
      animal.activeWorkingSession = session
    } else if animal.activeWorkingSession?.publicID == session.publicID {
      animal.activeWorkingSession = nil
    }
  }

  static func upsertSwiftDataWorkingTreatmentRecords(
    from sharedRecords: [SharedWorkingTreatmentRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedWorkingTreatmentRecord, UUID, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let sessionPublicID = record.parsedSessionPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, sessionPublicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var treatmentRecordsByPublicID: [UUID: WorkingTreatmentRecord] = [:]
    for treatmentRecord in try context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
    where treatmentRecordsByPublicID[treatmentRecord.publicID] == nil {
      treatmentRecordsByPublicID[treatmentRecord.publicID] = treatmentRecord
    }

    var sessionsByPublicID: [UUID: WorkingSession] = [:]
    for session in try context.fetch(FetchDescriptor<WorkingSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, sessionPublicID, animalPublicID) in validSharedRecords {
      guard let session = sessionsByPublicID[sessionPublicID],
        let animal = animalsByPublicID[animalPublicID]
      else { continue }

      let treatmentRecord: WorkingTreatmentRecord
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingTreatmentRecord = treatmentRecordsByPublicID[publicID] {
        treatmentRecord = existingTreatmentRecord
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: treatmentRecord)
      } else {
        treatmentRecord = WorkingTreatmentRecord(
          publicID: publicID,
          date: record.date ?? Date.now,
          itemName: record.itemName ?? "",
          given: record.given?.boolValue ?? false,
          quantity: record.quantity?.doubleValue,
          animal: animal,
          session: session
        )
        context.insert(treatmentRecord)
        treatmentRecordsByPublicID[publicID] = treatmentRecord
        inserted += 1
      }

      apply(record, to: treatmentRecord, herd: herd, session: session, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedWorkingTreatmentRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: treatmentRecord)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedWorkingTreatmentRecord,
    to treatmentRecord: WorkingTreatmentRecord,
    herd: Herd,
    session: WorkingSession,
    animal: Animal
  ) {
    treatmentRecord.herd = herd
    treatmentRecord.session = session
    treatmentRecord.animal = animal
    treatmentRecord.date = sharedRecord.date ?? treatmentRecord.date
    treatmentRecord.itemName = sharedRecord.itemName ?? ""
    treatmentRecord.given = sharedRecord.given?.boolValue ?? false
    treatmentRecord.quantity = sharedRecord.quantity?.doubleValue
  }

  static func upsertSwiftDataHealthRecords(
    from sharedRecords: [SharedHealthRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedHealthRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var healthRecordsByPublicID: [UUID: HealthRecord] = [:]
    for healthRecord in try context.fetch(FetchDescriptor<HealthRecord>())
    where healthRecordsByPublicID[healthRecord.publicID] == nil {
      healthRecordsByPublicID[healthRecord.publicID] = healthRecord
    }

    var sessionsByPublicID: [UUID: WorkingSession] = [:]
    for session in try context.fetch(FetchDescriptor<WorkingSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, animalPublicID) in validSharedRecords {
      guard let animal = animalsByPublicID[animalPublicID] else { continue }

      let healthRecord: HealthRecord
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingHealthRecord = healthRecordsByPublicID[publicID] {
        healthRecord = existingHealthRecord
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: healthRecord)
      } else {
        healthRecord = HealthRecord(
          publicID: publicID,
          date: record.date ?? Date.now,
          treatment: record.treatment ?? "",
          notes: record.notes,
          workingSession: record.parsedWorkingSessionPublicID.flatMap { sessionsByPublicID[$0] },
          animal: animal
        )
        context.insert(healthRecord)
        healthRecordsByPublicID[publicID] = healthRecord
        inserted += 1
      }

      apply(
        record, to: healthRecord, herd: herd, animal: animal, sessionsByPublicID: sessionsByPublicID
      )
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedHealthRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: healthRecord)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedHealthRecord,
    to healthRecord: HealthRecord,
    herd: Herd,
    animal: Animal,
    sessionsByPublicID: [UUID: WorkingSession]
  ) {
    healthRecord.herd = herd
    healthRecord.animal = animal
    healthRecord.date = sharedRecord.date ?? healthRecord.date
    healthRecord.treatment = sharedRecord.treatment ?? ""
    healthRecord.notes = sharedRecord.notes
    healthRecord.workingSession = sharedRecord.parsedWorkingSessionPublicID.flatMap {
      sessionsByPublicID[$0]
    }
  }

  static func upsertSwiftDataPregnancyChecks(
    from sharedRecords: [SharedPregnancyCheckRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedPregnancyCheckRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let animalPublicID = record.parsedAnimalPublicID
      else { return nil }
      return (record, publicID, animalPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var checksByPublicID: [UUID: PregnancyCheck] = [:]
    for check in try context.fetch(FetchDescriptor<PregnancyCheck>())
    where checksByPublicID[check.publicID] == nil {
      checksByPublicID[check.publicID] = check
    }

    var sessionsByPublicID: [UUID: WorkingSession] = [:]
    for session in try context.fetch(FetchDescriptor<WorkingSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, animalPublicID) in validSharedRecords {
      guard let animal = animalsByPublicID[animalPublicID] else { continue }

      let check: PregnancyCheck
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingCheck = checksByPublicID[publicID] {
        check = existingCheck
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: check)
      } else {
        check = PregnancyCheck(
          publicID: publicID,
          date: record.date ?? Date.now,
          result: record.parsedResult,
          technician: record.technician,
          estimatedDaysPregnant: record.estimatedDaysPregnant?.intValue,
          dueDate: record.dueDate,
          sireAnimal: record.parsedSireAnimalPublicID.flatMap { animalsByPublicID[$0] },
          workingSession: record.parsedWorkingSessionPublicID.flatMap { sessionsByPublicID[$0] },
          animal: animal
        )
        context.insert(check)
        checksByPublicID[publicID] = check
        inserted += 1
      }

      apply(
        record, to: check, herd: herd, animal: animal, animalsByPublicID: animalsByPublicID,
        sessionsByPublicID: sessionsByPublicID)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedPregnancyCheckRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: check)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedPregnancyCheckRecord,
    to check: PregnancyCheck,
    herd: Herd,
    animal: Animal,
    animalsByPublicID: [UUID: Animal],
    sessionsByPublicID: [UUID: WorkingSession]
  ) {
    check.herd = herd
    check.animal = animal
    check.date = sharedRecord.date ?? check.date
    check.result = sharedRecord.parsedResult
    check.technician = sharedRecord.technician
    check.estimatedDaysPregnant = sharedRecord.estimatedDaysPregnant?.intValue
    check.dueDate = sharedRecord.dueDate
    check.sireAnimal = sharedRecord.parsedSireAnimalPublicID.flatMap { animalsByPublicID[$0] }
    check.workingSession = sharedRecord.parsedWorkingSessionPublicID.flatMap {
      sessionsByPublicID[$0]
    }
  }

  static func upsertSwiftDataFieldCheckSessions(
    from sharedRecords: [SharedFieldCheckSessionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedFieldCheckSessionRecord, UUID)? in
      guard let publicID = record.parsedPublicID else { return nil }
      return (record, publicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var sessionsByPublicID: [UUID: FieldCheckSession] = [:]
    for session in try context.fetch(FetchDescriptor<FieldCheckSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var pasturesByPublicID: [UUID: Pasture] = [:]
    for pasture in try context.fetch(FetchDescriptor<Pasture>())
    where pasturesByPublicID[pasture.publicID] == nil {
      pasturesByPublicID[pasture.publicID] = pasture
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID) in validSharedRecords {
      let session: FieldCheckSession
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingSession = sessionsByPublicID[publicID] {
        session = existingSession
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: session)
      } else {
        session = FieldCheckSession(
          publicID: publicID,
          startedAt: record.startedAt ?? Date.now,
          completedAt: record.completedAt,
          notes: record.notes ?? "",
          expectedHeadCountSnapshot: record.expectedHeadCountSnapshot?.intValue ?? 0,
          quickCowCount: record.quickCowCount?.intValue ?? 0,
          quickHeiferCount: record.quickHeiferCount?.intValue ?? 0,
          quickCalfCount: record.quickCalfCount?.intValue ?? 0,
          quickBullCount: record.quickBullCount?.intValue ?? 0,
          quickSteerCount: record.quickSteerCount?.intValue ?? 0,
          pastureNameSnapshot: record.pastureNameSnapshot ?? "",
          pastureArchivedAt: record.pastureArchivedAt,
          pastureID: record.parsedPasturePublicID,
          pasture: record.parsedPasturePublicID.flatMap { pasturesByPublicID[$0] }
        )
        context.insert(session)
        sessionsByPublicID[publicID] = session
        inserted += 1
      }

      apply(record, to: session, herd: herd, pasturesByPublicID: pasturesByPublicID)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedFieldCheckSessionRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: session)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedFieldCheckSessionRecord,
    to session: FieldCheckSession,
    herd: Herd,
    pasturesByPublicID: [UUID: Pasture]
  ) {
    session.herd = herd
    session.startedAt = sharedRecord.startedAt ?? session.startedAt
    session.completedAt = sharedRecord.completedAt
    session.notes = sharedRecord.notes ?? ""
    session.expectedHeadCountSnapshot = sharedRecord.expectedHeadCountSnapshot?.intValue ?? 0
    session.quickCowCount = sharedRecord.quickCowCount?.intValue ?? 0
    session.quickHeiferCount = sharedRecord.quickHeiferCount?.intValue ?? 0
    session.quickCalfCount = sharedRecord.quickCalfCount?.intValue ?? 0
    session.quickBullCount = sharedRecord.quickBullCount?.intValue ?? 0
    session.quickSteerCount = sharedRecord.quickSteerCount?.intValue ?? 0
    session.pastureNameSnapshot = sharedRecord.pastureNameSnapshot ?? ""
    session.pastureArchivedAt = sharedRecord.pastureArchivedAt
    session.pastureID = sharedRecord.parsedPasturePublicID
    session.pasture = sharedRecord.parsedPasturePublicID.flatMap { pasturesByPublicID[$0] }
  }

  static func upsertSwiftDataFieldCheckAnimalChecks(
    from sharedRecords: [SharedFieldCheckAnimalCheckRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedFieldCheckAnimalCheckRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let sessionPublicID = record.parsedSessionPublicID
      else { return nil }
      return (record, publicID, sessionPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var checksByPublicID: [UUID: FieldCheckAnimalCheck] = [:]
    for check in try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>())
    where checksByPublicID[check.publicID] == nil {
      checksByPublicID[check.publicID] = check
    }

    var sessionsByPublicID: [UUID: FieldCheckSession] = [:]
    for session in try context.fetch(FetchDescriptor<FieldCheckSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, sessionPublicID) in validSharedRecords {
      guard let session = sessionsByPublicID[sessionPublicID] else { continue }
      let animal = record.parsedAnimalPublicID.flatMap { animalsByPublicID[$0] }

      let check: FieldCheckAnimalCheck
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingCheck = checksByPublicID[publicID] {
        check = existingCheck
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: check)
      } else {
        check = FieldCheckAnimalCheck(
          publicID: publicID,
          animalIDSnapshot: record.parsedAnimalIDSnapshot,
          rosterTagNumber: record.rosterTagNumber ?? "",
          rosterTagColorID: record.parsedRosterTagColorID,
          damRosterTagNumber: record.damRosterTagNumber ?? "",
          damRosterTagColorID: record.parsedDamRosterTagColorID,
          animalName: record.animalName ?? "",
          animalSex: record.parsedAnimalSex,
          animalType: record.parsedAnimalType,
          wasExpectedAtStart: record.wasExpectedAtStart?.boolValue ?? true,
          countedAt: record.countedAt,
          missingConfirmedAt: record.missingConfirmedAt,
          note: record.note ?? "",
          animal: animal,
          session: session
        )
        context.insert(check)
        checksByPublicID[publicID] = check
        inserted += 1
      }

      apply(record, to: check, herd: herd, session: session, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedFieldCheckAnimalCheckRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: check)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedFieldCheckAnimalCheckRecord,
    to check: FieldCheckAnimalCheck,
    herd: Herd,
    session: FieldCheckSession,
    animal: Animal?
  ) {
    check.herd = herd
    check.session = session
    check.animal = animal
    check.animalIDSnapshot = sharedRecord.parsedAnimalIDSnapshot
    check.rosterTagNumber = sharedRecord.rosterTagNumber ?? ""
    check.rosterTagColorID = sharedRecord.parsedRosterTagColorID
    check.damRosterTagNumber = sharedRecord.damRosterTagNumber ?? ""
    check.damRosterTagColorID = sharedRecord.parsedDamRosterTagColorID
    check.animalName = sharedRecord.animalName ?? ""
    check.animalSex = sharedRecord.parsedAnimalSex
    if let animalType = sharedRecord.parsedAnimalType {
      check.animalTypeSnapshot = animalType
    }
    check.wasExpectedAtStart = sharedRecord.wasExpectedAtStart?.boolValue ?? true
    check.countedAt = sharedRecord.countedAt
    check.missingConfirmedAt = sharedRecord.missingConfirmedAt
    check.note = sharedRecord.note ?? ""
  }

  static func upsertSwiftDataFieldCheckFindings(
    from sharedRecords: [SharedFieldCheckFindingRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    let validSharedRecords = sharedRecords.compactMap {
      record -> (SharedFieldCheckFindingRecord, UUID, UUID)? in
      guard let publicID = record.parsedPublicID,
        let sessionPublicID = record.parsedSessionPublicID ?? record.parsedSessionIDSnapshot
      else { return nil }
      return (record, publicID, sessionPublicID)
    }
    guard !validSharedRecords.isEmpty else { return (0, 0, []) }

    var findingsByPublicID: [UUID: FieldCheckFinding] = [:]
    for finding in try context.fetch(FetchDescriptor<FieldCheckFinding>())
    where findingsByPublicID[finding.publicID] == nil {
      findingsByPublicID[finding.publicID] = finding
    }

    var sessionsByPublicID: [UUID: FieldCheckSession] = [:]
    for session in try context.fetch(FetchDescriptor<FieldCheckSession>())
    where sessionsByPublicID[session.publicID] == nil {
      sessionsByPublicID[session.publicID] = session
    }

    var animalsByPublicID: [UUID: Animal] = [:]
    for animal in try context.fetch(FetchDescriptor<Animal>())
    where animalsByPublicID[animal.publicID] == nil {
      animalsByPublicID[animal.publicID] = animal
    }

    var inserted = 0
    var updated = 0
    var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

    for (record, publicID, sessionPublicID) in validSharedRecords {
      guard let session = sessionsByPublicID[sessionPublicID] else { continue }
      let animal = record.parsedAnimalPublicID.flatMap { animalsByPublicID[$0] }

      let finding: FieldCheckFinding
      var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
      if let existingFinding = findingsByPublicID[publicID] {
        finding = existingFinding
        updated += 1
        beforeFieldSnapshot = conflictFieldSnapshot(for: finding)
      } else {
        finding = FieldCheckFinding(
          publicID: publicID,
          recordedAt: record.recordedAt ?? Date.now,
          type: record.parsedType,
          severity: record.parsedSeverity,
          status: record.parsedStatus,
          note: record.note ?? "",
          animalIDSnapshot: record.parsedAnimalIDSnapshot,
          animalDisplayTagNumberSnapshot: record.animalDisplayTagNumberSnapshot ?? "",
          animalDisplayTagColorIDSnapshot: record.parsedAnimalDisplayTagColorIDSnapshot,
          animalNameSnapshot: record.animalNameSnapshot ?? "",
          pastureNameSnapshot: record.pastureNameSnapshot ?? "",
          sessionIDSnapshot: record.parsedSessionIDSnapshot ?? session.publicID,
          animal: animal,
          session: session
        )
        context.insert(finding)
        findingsByPublicID[publicID] = finding
        inserted += 1
      }

      apply(record, to: finding, herd: herd, session: session, animal: animal)
      if let beforeFieldSnapshot {
        updatedRecordConflicts.append(
          updatedRecordConflict(
            sourceEntityName: SharedFieldCheckFindingRecord.entityName,
            publicID: publicID,
            localModifiedAt: nil,
            sharedModifiedAt: record.lastMirroredAt,
            before: beforeFieldSnapshot,
            after: conflictFieldSnapshot(for: finding)
          )
        )
      }
    }

    return (inserted, updated, updatedRecordConflicts)
  }

  private static func apply(
    _ sharedRecord: SharedFieldCheckFindingRecord,
    to finding: FieldCheckFinding,
    herd: Herd,
    session: FieldCheckSession,
    animal: Animal?
  ) {
    finding.herd = herd
    finding.session = session
    finding.animal = animal
    finding.recordedAt = sharedRecord.recordedAt ?? finding.recordedAt
    finding.type = sharedRecord.parsedType
    finding.severity = sharedRecord.parsedSeverity
    finding.status = sharedRecord.parsedStatus
    finding.note = sharedRecord.note ?? ""
    finding.animalIDSnapshot = sharedRecord.parsedAnimalIDSnapshot
    finding.animalDisplayTagNumberSnapshot = sharedRecord.animalDisplayTagNumberSnapshot ?? ""
    finding.animalDisplayTagColorIDSnapshot = sharedRecord.parsedAnimalDisplayTagColorIDSnapshot
    finding.animalNameSnapshot = sharedRecord.animalNameSnapshot ?? ""
    finding.pastureNameSnapshot = sharedRecord.pastureNameSnapshot ?? ""
    finding.sessionIDSnapshot = sharedRecord.parsedSessionIDSnapshot ?? session.publicID
  }
}
