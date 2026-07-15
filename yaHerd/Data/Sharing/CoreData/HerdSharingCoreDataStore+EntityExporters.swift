//
//  HerdSharingCoreDataStore+EntityExporters.swift
//  yaHerd
//

import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func mirrorHerdIntoPrivateStore(_ herd: HerdSummary) async throws -> SharedHerdRecord {
    try await loadIfNeeded()

    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedHerdRecords(
      publicID: herd.publicID,
      in: privateStore
    )
    let recordsByPublicID: [String: SharedHerdRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    let existingRecord = recordsByPublicID[herd.publicID.uuidString]
    let record = existingRecord ?? SharedHerdRecord(context: context)

    if existingRecord == nil {
      context.assign(record, to: privateStore)
    }

    record.mirror(herd)

    try saveBridgeContextIfNeeded()

    return record
  }

  func mirrorTagColorDefinitionsIntoPrivateStore(
    _ definitions: [TagColorDefinition],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedTagColorDefinitionRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedTagColorDefinitionRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedTagColorDefinitionRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    let mirroredDefinitionIDs = Set(definitions.map { $0.id.uuidString })
    var mirroredRecords: [SharedTagColorDefinitionRecord] = []

    for definition in definitions {
      let publicID = definition.id.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedTagColorDefinitionRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(definition, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredDefinitionIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedTagColorDefinitionRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorStatusReferencesIntoPrivateStore(
    _ statusReferences: [AnimalStatusReference],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedAnimalStatusReferenceRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedAnimalStatusReferenceRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedAnimalStatusReferenceRecord] =
      repairDuplicateBridgeRecords(
        existingRecords,
        in: context
      )
    let mirroredReferenceIDs = Set(statusReferences.map { $0.id.uuidString })
    var mirroredRecords: [SharedAnimalStatusReferenceRecord] = []

    for statusReference in statusReferences {
      let publicID = statusReference.id.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedAnimalStatusReferenceRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(statusReference, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredReferenceIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedAnimalStatusReferenceRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorAnimalsIntoPrivateStore(
    _ animals: [Animal],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedAnimalRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedAnimalRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedAnimalRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    let mirroredAnimalIDs = Set(animals.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedAnimalRecord] = []

    for animal in animals {
      let publicID = animal.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedAnimalRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(animal, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords where !mirroredAnimalIDs.contains(staleRecord.publicID ?? "")
    {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedAnimalRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorAnimalTagsIntoPrivateStore(
    _ tags: [AnimalTag],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedAnimalTagRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedAnimalTagRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedAnimalTagRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredTagIDs = Set(tags.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedAnimalTagRecord] = []

    for tag in tags {
      let publicID = tag.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedAnimalTagRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(tag, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.animal = tag.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords where !mirroredTagIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedAnimalTagRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorPastureGroupsIntoPrivateStore(
    _ pastureGroups: [PastureGroup],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedPastureGroupRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedPastureGroupRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedPastureGroupRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    let mirroredGroupIDs = Set(pastureGroups.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedPastureGroupRecord] = []

    for pastureGroup in pastureGroups {
      let publicID = pastureGroup.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedPastureGroupRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(pastureGroup, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords where !mirroredGroupIDs.contains(staleRecord.publicID ?? "")
    {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedPastureGroupRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorPasturesIntoPrivateStore(
    _ pastures: [Pasture],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    pastureGroupRecords: [SharedPastureGroupRecord]
  ) throws -> [SharedPastureRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedPastureRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedPastureRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var groupsByPublicID: [String: SharedPastureGroupRecord] = [:]
    for groupRecord in pastureGroupRecords {
      guard let publicID = groupRecord.publicID else { continue }
      groupsByPublicID[publicID] = groupRecord
    }

    let mirroredPastureIDs = Set(pastures.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedPastureRecord] = []

    for pasture in pastures {
      let publicID = pasture.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedPastureRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(pasture, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.group = pasture.group.flatMap { groupsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredPastureIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedPastureRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorMovementsIntoPrivateStore(
    _ movements: [MovementRecord],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedMovementRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedMovementRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedMovementRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredMovementIDs = Set(movements.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedMovementRecord] = []

    for movement in movements {
      let publicID = movement.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedMovementRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(movement, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.animal = movement.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredMovementIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedMovementRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorStatusRecordsIntoPrivateStore(
    _ statusRecords: [StatusRecord],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedStatusRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedStatusRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedStatusRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredStatusRecordIDs = Set(statusRecords.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedStatusRecord] = []

    for statusRecord in statusRecords {
      let publicID = statusRecord.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedStatusRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(statusRecord, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.animal = statusRecord.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredStatusRecordIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedStatusRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorHealthRecordsIntoPrivateStore(
    _ healthRecords: [HealthRecord],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedHealthRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedHealthRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedHealthRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredHealthRecordIDs = Set(healthRecords.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedHealthRecord] = []

    for healthRecord in healthRecords {
      let publicID = healthRecord.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedHealthRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(healthRecord, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.animal = healthRecord.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredHealthRecordIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedHealthRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorPregnancyChecksIntoPrivateStore(
    _ pregnancyChecks: [PregnancyCheck],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedPregnancyCheckRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedPregnancyCheckRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedPregnancyCheckRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )
    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredPregnancyCheckIDs = Set(pregnancyChecks.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedPregnancyCheckRecord] = []

    for pregnancyCheck in pregnancyChecks {
      let publicID = pregnancyCheck.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedPregnancyCheckRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(pregnancyCheck, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.animal = pregnancyCheck.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredPregnancyCheckIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedPregnancyCheckRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorWorkingProtocolTemplatesIntoPrivateStore(
    _ templates: [WorkingProtocolTemplate],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedWorkingProtocolTemplateRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedWorkingProtocolTemplateRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedWorkingProtocolTemplateRecord] =
      repairDuplicateBridgeRecords(
        existingRecords,
        in: context
      )

    let mirroredTemplateIDs = Set(templates.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedWorkingProtocolTemplateRecord] = []

    for template in templates {
      let publicID = template.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedWorkingProtocolTemplateRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(template, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredTemplateIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedWorkingProtocolTemplateRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorWorkingSessionsIntoPrivateStore(
    _ sessions: [WorkingSession],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedWorkingSessionRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedWorkingSessionRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedWorkingSessionRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )

    let mirroredSessionIDs = Set(sessions.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedWorkingSessionRecord] = []

    for session in sessions {
      let publicID = session.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedWorkingSessionRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(session, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredSessionIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedWorkingSessionRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorWorkingQueueItemsIntoPrivateStore(
    _ queueItems: [WorkingQueueItem],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    sessionRecords: [SharedWorkingSessionRecord],
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedWorkingQueueItemRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedWorkingQueueItemRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedWorkingQueueItemRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )

    var sessionsByPublicID: [String: SharedWorkingSessionRecord] = [:]
    for sessionRecord in sessionRecords {
      guard let publicID = sessionRecord.publicID else { continue }
      sessionsByPublicID[publicID] = sessionRecord
    }

    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredQueueItemIDs = Set(queueItems.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedWorkingQueueItemRecord] = []

    for queueItem in queueItems {
      let publicID = queueItem.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedWorkingQueueItemRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(queueItem, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.session = queueItem.session.flatMap { sessionsByPublicID[$0.publicID.uuidString] }
      record.animal = queueItem.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredQueueItemIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedWorkingQueueItemRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorWorkingTreatmentRecordsIntoPrivateStore(
    _ treatmentRecords: [WorkingTreatmentRecord],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    sessionRecords: [SharedWorkingSessionRecord],
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedWorkingTreatmentRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedWorkingTreatmentRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedWorkingTreatmentRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )

    var sessionsByPublicID: [String: SharedWorkingSessionRecord] = [:]
    for sessionRecord in sessionRecords {
      guard let publicID = sessionRecord.publicID else { continue }
      sessionsByPublicID[publicID] = sessionRecord
    }

    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredTreatmentRecordIDs = Set(treatmentRecords.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedWorkingTreatmentRecord] = []

    for treatmentRecord in treatmentRecords {
      let publicID = treatmentRecord.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedWorkingTreatmentRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(treatmentRecord, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.session = treatmentRecord.session.flatMap {
        sessionsByPublicID[$0.publicID.uuidString]
      }
      record.animal = treatmentRecord.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredTreatmentRecordIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedWorkingTreatmentRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorFieldCheckSessionsIntoPrivateStore(
    _ sessions: [FieldCheckSession],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord
  ) throws -> [SharedFieldCheckSessionRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedFieldCheckSessionRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedFieldCheckSessionRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )

    let mirroredSessionIDs = Set(sessions.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedFieldCheckSessionRecord] = []

    for session in sessions {
      let publicID = session.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedFieldCheckSessionRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(session, herdPublicID: herd.publicID)
      record.herd = herdRecord
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredSessionIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedFieldCheckSessionRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorFieldCheckAnimalChecksIntoPrivateStore(
    _ checks: [FieldCheckAnimalCheck],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    sessionRecords: [SharedFieldCheckSessionRecord],
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedFieldCheckAnimalCheckRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedFieldCheckAnimalCheckRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedFieldCheckAnimalCheckRecord] =
      repairDuplicateBridgeRecords(
        existingRecords,
        in: context
      )

    var sessionsByPublicID: [String: SharedFieldCheckSessionRecord] = [:]
    for sessionRecord in sessionRecords {
      guard let publicID = sessionRecord.publicID else { continue }
      sessionsByPublicID[publicID] = sessionRecord
    }

    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredCheckIDs = Set(checks.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedFieldCheckAnimalCheckRecord] = []

    for check in checks {
      let publicID = check.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedFieldCheckAnimalCheckRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(check, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.session = check.session.flatMap { sessionsByPublicID[$0.publicID.uuidString] }
      record.animal = check.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords where !mirroredCheckIDs.contains(staleRecord.publicID ?? "")
    {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedFieldCheckAnimalCheckRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  func mirrorFieldCheckFindingsIntoPrivateStore(
    _ findings: [FieldCheckFinding],
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    sessionRecords: [SharedFieldCheckSessionRecord],
    animalRecords: [SharedAnimalRecord]
  ) throws -> [SharedFieldCheckFindingRecord] {
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecords = try fetchSharedFieldCheckFindingRecords(
      herdPublicID: herd.publicID, in: privateStore)
    let recordsByPublicID: [String: SharedFieldCheckFindingRecord] = repairDuplicateBridgeRecords(
      existingRecords,
      in: context
    )

    var sessionsByPublicID: [String: SharedFieldCheckSessionRecord] = [:]
    for sessionRecord in sessionRecords {
      guard let publicID = sessionRecord.publicID else { continue }
      sessionsByPublicID[publicID] = sessionRecord
    }

    var animalsByPublicID: [String: SharedAnimalRecord] = [:]
    for animalRecord in animalRecords {
      guard let publicID = animalRecord.publicID else { continue }
      animalsByPublicID[publicID] = animalRecord
    }

    let mirroredFindingIDs = Set(findings.map { $0.publicID.uuidString })
    var mirroredRecords: [SharedFieldCheckFindingRecord] = []

    for finding in findings {
      let publicID = finding.publicID.uuidString
      let existingRecord = recordsByPublicID[publicID]
      let record = existingRecord ?? SharedFieldCheckFindingRecord(context: context)

      if existingRecord == nil {
        context.assign(record, to: privateStore)
      }

      record.mirror(finding, herdPublicID: herd.publicID)
      record.herd = herdRecord
      record.session = finding.session.flatMap { sessionsByPublicID[$0.publicID.uuidString] }
      record.animal = finding.animal.flatMap { animalsByPublicID[$0.publicID.uuidString] }
      mirroredRecords.append(record)
    }

    for staleRecord in existingRecords
    where !mirroredFindingIDs.contains(staleRecord.publicID ?? "") {
      try recordDeletionForStaleRecord(
        staleRecord,
        sourceEntityName: SharedFieldCheckFindingRecord.entityName,
        herd: herd,
        herdRecord: herdRecord,
        in: privateStore
      )
      context.delete(staleRecord)
    }

    try saveBridgeContextIfNeeded()

    return mirroredRecords
  }

  private func repairDuplicateBridgeRecords<Record: NSManagedObject>(
    _ records: [Record],
    in context: NSManagedObjectContext
  ) -> [String: Record] {
    var recordsByPublicID: [String: Record] = [:]

    for record in records {
      guard let publicID = record.value(forKey: "publicID") as? String, !publicID.isEmpty else {
        context.delete(record)
        continue
      }

      guard let existing = recordsByPublicID[publicID] else {
        recordsByPublicID[publicID] = record
        continue
      }

      let existingDate = existing.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
      let candidateDate = record.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
      let candidateWins =
        candidateDate > existingDate
        || (candidateDate == existingDate
          && record.objectID.uriRepresentation().absoluteString
            < existing.objectID.uriRepresentation().absoluteString)
      if candidateWins {
        context.delete(existing)
        recordsByPublicID[publicID] = record
      } else {
        context.delete(record)
      }
      ReliabilityLog.syncEvent(
        "HerdSharingCoreDataStore.duplicateBridgeRecordRepaired",
        detail: "\(String(describing: Record.self)):\(publicID)"
      )
    }

    return recordsByPublicID
  }

  func saveBridgeContextIfNeeded() throws {
    guard !isDeferringBridgeContextSaves else { return }
    let context = persistentContainer.viewContext
    if context.hasChanges {
      try PersistenceLog.save(context, operation: "HerdSharingCoreDataStore")
    }
  }

  private func recordDeletionForStaleRecord(
    _ staleRecord: NSManagedObject,
    sourceEntityName: String,
    herd: HerdSummary,
    herdRecord: SharedHerdRecord,
    in store: NSPersistentStore
  ) throws {
    guard let publicID = staleRecord.value(forKey: "publicID") as? String,
      !publicID.isEmpty
    else { return }

    let context = persistentContainer.viewContext
    let existingTombstone = try fetchSharedDeletedRecord(
      publicID: publicID,
      sourceEntityName: sourceEntityName,
      herdPublicID: herd.publicID,
      in: store
    )
    let tombstone = existingTombstone ?? SharedDeletedRecord(context: context)

    if existingTombstone == nil {
      context.assign(tombstone, to: store)
    }

    tombstone.mirrorDeletion(
      publicID: publicID,
      herdPublicID: herd.publicID,
      sourceEntityName: sourceEntityName
    )
    tombstone.herd = herdRecord
  }
}
