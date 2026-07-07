//
//  HerdSharingCoreDataStore.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation
import SwiftData

@MainActor
final class HerdSharingCoreDataStore {
  static let containerName = "yaHerdSharingBridge"
  static let storeDirectoryName = "HerdSharingBridge"
  static let privateStoreFileName = "HerdSharingPrivate.sqlite"
  static let sharedStoreFileName = "HerdSharingShared.sqlite"

  let persistentContainer: NSPersistentCloudKitContainer
  let cloudKitContainer: CKContainer

  private(set) var privateStore: NSPersistentStore?
  private(set) var sharedStore: NSPersistentStore?
  private var isLoaded = false

  init(
    containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
    storeDirectoryURL: URL? = nil
  ) {
    let model = HerdSharingCoreDataModelFactory.makeModel()
    persistentContainer = NSPersistentCloudKitContainer(
      name: Self.containerName,
      managedObjectModel: model
    )
    cloudKitContainer = CKContainer(identifier: containerIdentifier)

    let directoryURL = storeDirectoryURL ?? Self.defaultStoreDirectoryURL()
    persistentContainer.persistentStoreDescriptions = [
      Self.makeStoreDescription(
        url: directoryURL.appendingPathComponent(Self.privateStoreFileName),
        containerIdentifier: containerIdentifier,
        databaseScope: .private
      ),
      Self.makeStoreDescription(
        url: directoryURL.appendingPathComponent(Self.sharedStoreFileName),
        containerIdentifier: containerIdentifier,
        databaseScope: .shared
      ),
    ]
    persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
    persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
  }

  func loadIfNeeded() async throws {
    guard !isLoaded else { return }

    let directoryURL = persistentContainer.persistentStoreDescriptions
      .compactMap(\.url)
      .first?
      .deletingLastPathComponent()
    if let directoryURL {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }

    let container = persistentContainer
    let expectedStoreCount = container.persistentStoreDescriptions.count

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      var firstError: Error?
      var completedStoreCount = 0

      container.loadPersistentStores { _, error in
        if let error, firstError == nil {
          firstError = error
        }

        completedStoreCount += 1
        guard completedStoreCount == expectedStoreCount else { return }

        if let firstError {
          continuation.resume(throwing: firstError)
        } else {
          continuation.resume()
        }
      }
    }

    privateStore = store(named: Self.privateStoreFileName)
    sharedStore = store(named: Self.sharedStoreFileName)
    isLoaded = true
  }

  func mirrorHerdIntoPrivateStore(_ herd: HerdSummary) async throws -> SharedHerdRecord {
    try await loadIfNeeded()

    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    let context = persistentContainer.viewContext
    let existingRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
    let record = existingRecord ?? SharedHerdRecord(context: context)

    if existingRecord == nil {
      context.assign(record, to: privateStore)
    }

    record.mirror(herd)

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedTagColorDefinitionRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedAnimalStatusReferenceRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedAnimalRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedAnimalTagRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedPastureGroupRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedPastureRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedMovementRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedStatusRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedHealthRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedPregnancyCheckRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }
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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedWorkingProtocolTemplateRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedWorkingSessionRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedWorkingQueueItemRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedWorkingTreatmentRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedFieldCheckSessionRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedFieldCheckAnimalCheckRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

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
    var recordsByPublicID: [String: SharedFieldCheckFindingRecord] = [:]
    for record in existingRecords {
      guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
      recordsByPublicID[publicID] = record
    }

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

    if context.hasChanges {
      try context.save()
    }

    return mirroredRecords
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

  func syncBridgeRecordsFromSwiftData(
    herd: HerdSummary,
    tagColorDefinitions: [TagColorDefinition],
    statusReferences: [AnimalStatusReference],
    animalTags: [AnimalTag],
    pastureGroups: [PastureGroup],
    pastures: [Pasture],
    animals: [Animal],
    movements: [MovementRecord],
    statusRecords: [StatusRecord],
    healthRecords: [HealthRecord],
    pregnancyChecks: [PregnancyCheck],
    workingProtocolTemplates: [WorkingProtocolTemplate],
    workingSessions: [WorkingSession],
    workingQueueItems: [WorkingQueueItem],
    workingTreatmentRecords: [WorkingTreatmentRecord],
    fieldCheckSessions: [FieldCheckSession],
    fieldCheckAnimalChecks: [FieldCheckAnimalCheck],
    fieldCheckFindings: [FieldCheckFinding]
  ) async throws -> HerdSharingBridgeExportResult {
    try await loadIfNeeded()

    let target = try writableBridgeStore(for: herd)
    let originalPrivateStore = privateStore
    privateStore = target.store
    defer { privateStore = originalPrivateStore }

    let record = try await mirrorHerdIntoPrivateStore(herd)
    let sharedTagColorDefinitions = try mirrorTagColorDefinitionsIntoPrivateStore(
      tagColorDefinitions,
      herd: herd,
      herdRecord: record
    )
    let sharedStatusReferences = try mirrorStatusReferencesIntoPrivateStore(
      statusReferences,
      herd: herd,
      herdRecord: record
    )
    let pastureGroupRecords = try mirrorPastureGroupsIntoPrivateStore(
      pastureGroups,
      herd: herd,
      herdRecord: record
    )
    let pastureRecords = try mirrorPasturesIntoPrivateStore(
      pastures,
      herd: herd,
      herdRecord: record,
      pastureGroupRecords: pastureGroupRecords
    )
    let animalRecords = try mirrorAnimalsIntoPrivateStore(animals, herd: herd, herdRecord: record)
    let sharedAnimalTags = try mirrorAnimalTagsIntoPrivateStore(
      animalTags,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let movementRecords = try mirrorMovementsIntoPrivateStore(
      movements,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedStatusRecords = try mirrorStatusRecordsIntoPrivateStore(
      statusRecords,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedWorkingProtocolTemplates = try mirrorWorkingProtocolTemplatesIntoPrivateStore(
      workingProtocolTemplates,
      herd: herd,
      herdRecord: record
    )
    let sharedWorkingSessions = try mirrorWorkingSessionsIntoPrivateStore(
      workingSessions,
      herd: herd,
      herdRecord: record
    )
    let sharedWorkingQueueItems = try mirrorWorkingQueueItemsIntoPrivateStore(
      workingQueueItems,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedWorkingSessions,
      animalRecords: animalRecords
    )
    let sharedWorkingTreatmentRecords = try mirrorWorkingTreatmentRecordsIntoPrivateStore(
      workingTreatmentRecords,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedWorkingSessions,
      animalRecords: animalRecords
    )
    let sharedHealthRecords = try mirrorHealthRecordsIntoPrivateStore(
      healthRecords,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedPregnancyChecks = try mirrorPregnancyChecksIntoPrivateStore(
      pregnancyChecks,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedFieldCheckSessions = try mirrorFieldCheckSessionsIntoPrivateStore(
      fieldCheckSessions,
      herd: herd,
      herdRecord: record
    )
    let sharedFieldCheckAnimalChecks = try mirrorFieldCheckAnimalChecksIntoPrivateStore(
      fieldCheckAnimalChecks,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedFieldCheckSessions,
      animalRecords: animalRecords
    )
    let sharedFieldCheckFindings = try mirrorFieldCheckFindingsIntoPrivateStore(
      fieldCheckFindings,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedFieldCheckSessions,
      animalRecords: animalRecords
    )
    let sharedDeletedRecords = try fetchSharedDeletedRecords(
      herdPublicID: herd.publicID,
      in: target.store
    )
    let recordsToShare: [NSManagedObject] =
      [record as NSManagedObject] + sharedTagColorDefinitions.map { $0 as NSManagedObject }
      + sharedStatusReferences.map { $0 as NSManagedObject }
      + pastureGroupRecords.map { $0 as NSManagedObject }
      + pastureRecords.map { $0 as NSManagedObject } + animalRecords.map { $0 as NSManagedObject }
      + sharedAnimalTags.map { $0 as NSManagedObject }
      + movementRecords.map { $0 as NSManagedObject }
      + sharedStatusRecords.map { $0 as NSManagedObject }
      + sharedWorkingProtocolTemplates.map { $0 as NSManagedObject }
      + sharedWorkingSessions.map { $0 as NSManagedObject }
      + sharedWorkingQueueItems.map { $0 as NSManagedObject }
      + sharedWorkingTreatmentRecords.map { $0 as NSManagedObject }
      + sharedHealthRecords.map { $0 as NSManagedObject }
      + sharedPregnancyChecks.map { $0 as NSManagedObject }
      + sharedFieldCheckSessions.map { $0 as NSManagedObject }
      + sharedFieldCheckAnimalChecks.map { $0 as NSManagedObject }
      + sharedFieldCheckFindings.map { $0 as NSManagedObject }
      + sharedDeletedRecords.map { $0 as NSManagedObject }

    var didUpdateExistingCloudKitShare = false
    if target.shouldUpdateShare, try existingShare(for: record) != nil {
      _ = try await shareRecords(recordsToShare, title: herd.name)
      didUpdateExistingCloudKitShare = true
    }

    return HerdSharingBridgeExportResult(
      herdName: herd.name,
      writeTargetDescription: target.description,
      didUpdateExistingCloudKitShare: didUpdateExistingCloudKitShare,
      exportedTagColorDefinitionCount: sharedTagColorDefinitions.count,
      exportedStatusReferenceCount: sharedStatusReferences.count,
      exportedAnimalTagCount: sharedAnimalTags.count,
      exportedPastureGroupCount: pastureGroupRecords.count,
      exportedPastureCount: pastureRecords.count,
      exportedAnimalCount: animalRecords.count,
      exportedMovementCount: movementRecords.count,
      exportedStatusRecordCount: sharedStatusRecords.count,
      exportedHealthRecordCount: sharedHealthRecords.count,
      exportedPregnancyCheckCount: sharedPregnancyChecks.count,
      exportedWorkingProtocolTemplateCount: sharedWorkingProtocolTemplates.count,
      exportedWorkingSessionCount: sharedWorkingSessions.count,
      exportedWorkingQueueItemCount: sharedWorkingQueueItems.count,
      exportedWorkingTreatmentRecordCount: sharedWorkingTreatmentRecords.count,
      exportedFieldCheckSessionCount: sharedFieldCheckSessions.count,
      exportedFieldCheckAnimalCheckCount: sharedFieldCheckAnimalChecks.count,
      exportedFieldCheckFindingCount: sharedFieldCheckFindings.count,
      exportedDeletedRecordCount: sharedDeletedRecords.count
    )
  }

  func fetchSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess {
    try await loadIfNeeded()

    if let privateStore,
      let privateHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
    {
      let share = try existingShare(for: privateHerdRecord)
      return .ownerPrivateStore(participantCount: share?.participants.count)
    }

    if let sharedStore,
      let sharedHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: sharedStore)
    {
      let share = try existingShare(for: sharedHerdRecord)
      let permission = share.map { sharingPermission(from: $0) } ?? .unknown
      return .acceptedSharedStore(
        permission: permission,
        participantCount: share?.participants.count
      )
    }

    return .localOwnerBridgePending
  }

  private func writableBridgeStore(for herd: HerdSummary) throws -> (
    store: NSPersistentStore,
    description: String,
    shouldUpdateShare: Bool
  ) {
    if let privateStore,
      let privateHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
    {
      let hasExistingShare = try existingShare(for: privateHerdRecord) != nil
      return (privateStore, "owner private store", hasExistingShare)
    }

    if let sharedStore,
      let sharedHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: sharedStore)
    {
      let share = try existingShare(for: sharedHerdRecord)
      let permission = share.map { sharingPermission(from: $0) } ?? .unknown
      guard permission == .readWrite || permission == .owner else {
        throw HerdSharingActionError.readOnlyShareCannotWrite
      }
      return (sharedStore, "accepted shared store", false)
    }

    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    return (privateStore, "owner private store", false)
  }

  func makeSystemShare(
    for herd: HerdSummary,
    tagColorDefinitions: [TagColorDefinition],
    statusReferences: [AnimalStatusReference],
    animalTags: [AnimalTag],
    pastureGroups: [PastureGroup],
    pastures: [Pasture],
    animals: [Animal],
    movements: [MovementRecord],
    statusRecords: [StatusRecord],
    healthRecords: [HealthRecord],
    pregnancyChecks: [PregnancyCheck],
    workingProtocolTemplates: [WorkingProtocolTemplate],
    workingSessions: [WorkingSession],
    workingQueueItems: [WorkingQueueItem],
    workingTreatmentRecords: [WorkingTreatmentRecord],
    fieldCheckSessions: [FieldCheckSession],
    fieldCheckAnimalChecks: [FieldCheckAnimalCheck],
    fieldCheckFindings: [FieldCheckFinding]
  ) async throws -> HerdSystemShare {
    let record = try await mirrorHerdIntoPrivateStore(herd)
    let sharedTagColorDefinitions = try mirrorTagColorDefinitionsIntoPrivateStore(
      tagColorDefinitions,
      herd: herd,
      herdRecord: record
    )
    let sharedStatusReferences = try mirrorStatusReferencesIntoPrivateStore(
      statusReferences,
      herd: herd,
      herdRecord: record
    )
    let pastureGroupRecords = try mirrorPastureGroupsIntoPrivateStore(
      pastureGroups,
      herd: herd,
      herdRecord: record
    )
    let pastureRecords = try mirrorPasturesIntoPrivateStore(
      pastures,
      herd: herd,
      herdRecord: record,
      pastureGroupRecords: pastureGroupRecords
    )
    let animalRecords = try mirrorAnimalsIntoPrivateStore(animals, herd: herd, herdRecord: record)
    let sharedAnimalTags = try mirrorAnimalTagsIntoPrivateStore(
      animalTags,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let movementRecords = try mirrorMovementsIntoPrivateStore(
      movements,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedStatusRecords = try mirrorStatusRecordsIntoPrivateStore(
      statusRecords,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedWorkingProtocolTemplates = try mirrorWorkingProtocolTemplatesIntoPrivateStore(
      workingProtocolTemplates,
      herd: herd,
      herdRecord: record
    )
    let sharedWorkingSessions = try mirrorWorkingSessionsIntoPrivateStore(
      workingSessions,
      herd: herd,
      herdRecord: record
    )
    let sharedWorkingQueueItems = try mirrorWorkingQueueItemsIntoPrivateStore(
      workingQueueItems,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedWorkingSessions,
      animalRecords: animalRecords
    )
    let sharedWorkingTreatmentRecords = try mirrorWorkingTreatmentRecordsIntoPrivateStore(
      workingTreatmentRecords,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedWorkingSessions,
      animalRecords: animalRecords
    )
    let sharedHealthRecords = try mirrorHealthRecordsIntoPrivateStore(
      healthRecords,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedPregnancyChecks = try mirrorPregnancyChecksIntoPrivateStore(
      pregnancyChecks,
      herd: herd,
      herdRecord: record,
      animalRecords: animalRecords
    )
    let sharedFieldCheckSessions = try mirrorFieldCheckSessionsIntoPrivateStore(
      fieldCheckSessions,
      herd: herd,
      herdRecord: record
    )
    let sharedFieldCheckAnimalChecks = try mirrorFieldCheckAnimalChecksIntoPrivateStore(
      fieldCheckAnimalChecks,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedFieldCheckSessions,
      animalRecords: animalRecords
    )
    let sharedFieldCheckFindings = try mirrorFieldCheckFindingsIntoPrivateStore(
      fieldCheckFindings,
      herd: herd,
      herdRecord: record,
      sessionRecords: sharedFieldCheckSessions,
      animalRecords: animalRecords
    )
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }
    let sharedDeletedRecords = try fetchSharedDeletedRecords(
      herdPublicID: herd.publicID,
      in: privateStore
    )
    let recordsToShare: [NSManagedObject] =
      [record as NSManagedObject] + sharedTagColorDefinitions.map { $0 as NSManagedObject }
      + sharedStatusReferences.map { $0 as NSManagedObject }
      + pastureGroupRecords.map { $0 as NSManagedObject }
      + pastureRecords.map { $0 as NSManagedObject } + animalRecords.map { $0 as NSManagedObject }
      + sharedAnimalTags.map { $0 as NSManagedObject }
      + movementRecords.map { $0 as NSManagedObject }
      + sharedStatusRecords.map { $0 as NSManagedObject }
      + sharedWorkingProtocolTemplates.map { $0 as NSManagedObject }
      + sharedWorkingSessions.map { $0 as NSManagedObject }
      + sharedWorkingQueueItems.map { $0 as NSManagedObject }
      + sharedWorkingTreatmentRecords.map { $0 as NSManagedObject }
      + sharedHealthRecords.map { $0 as NSManagedObject }
      + sharedPregnancyChecks.map { $0 as NSManagedObject }
      + sharedFieldCheckSessions.map { $0 as NSManagedObject }
      + sharedFieldCheckAnimalChecks.map { $0 as NSManagedObject }
      + sharedFieldCheckFindings.map { $0 as NSManagedObject }
      + sharedDeletedRecords.map { $0 as NSManagedObject }
    let share = try await shareRecords(recordsToShare, title: herd.name)

    return HerdSystemShare(
      title: herd.name,
      share: share,
      container: cloudKitContainer,
      persistUpdatedShareHandler: { [weak self] share in
        await self?.persistUpdatedShare(share)
      },
      stopSharingHandler: { [weak self] share in
        await self?.purgeStoppedShare(share)
      }
    )
  }

  func acceptShareInvitation(metadata: CKShare.Metadata) async throws {
    try await loadIfNeeded()

    guard let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The shared CloudKit bridge store was not loaded.")
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      persistentContainer.acceptShareInvitations(
        from: [metadata],
        into: sharedStore
      ) { _, error in
        if let error {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
        } else {
          continuation.resume()
        }
      }
    }
  }

  func importSharedRecordsIntoSwiftData(context swiftDataContext: ModelContext) async throws
    -> HerdSharingBridgeImportResult
  {
    try await loadIfNeeded()

    guard let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The shared CloudKit bridge store was not loaded.")
    }

    let herdRecords = try fetchSharedHerdRecords(in: sharedStore)
    guard let herdRecord = herdRecords.sorted(by: sharedHerdRecordSort).first else {
      throw HerdSharingActionError.bridgeImportFailed(
        "No shared herd records were found in the Core Data sharing bridge.")
    }

    guard let herdPublicID = herdRecord.parsedPublicID else {
      throw HerdSharingActionError.bridgeImportFailed(
        "The shared herd record is missing a valid public ID.")
    }

    let herd = try upsertSwiftDataHerd(from: herdRecord, in: swiftDataContext)
    let sharedTagColorDefinitionRecords = try fetchSharedTagColorDefinitionRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let tagColorDefinitionResult = try upsertSwiftDataTagColorDefinitions(
      from: sharedTagColorDefinitionRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedStatusReferenceRecords = try fetchSharedAnimalStatusReferenceRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let statusReferenceResult = try upsertSwiftDataStatusReferences(
      from: sharedStatusReferenceRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedPastureGroupRecords = try fetchSharedPastureGroupRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let pastureGroupResult = try upsertSwiftDataPastureGroups(
      from: sharedPastureGroupRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedPastureRecords = try fetchSharedPastureRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let pastureResult = try upsertSwiftDataPastures(
      from: sharedPastureRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedAnimalRecords = try fetchSharedAnimalRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let animalResult = try upsertSwiftDataAnimals(
      from: sharedAnimalRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedAnimalTagRecords = try fetchSharedAnimalTagRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let animalTagResult = try upsertSwiftDataAnimalTags(
      from: sharedAnimalTagRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedMovementRecords = try fetchSharedMovementRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let movementResult = try upsertSwiftDataMovements(
      from: sharedMovementRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedStatusRecords = try fetchSharedStatusRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let statusRecordResult = try upsertSwiftDataStatusRecords(
      from: sharedStatusRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedWorkingProtocolTemplates = try fetchSharedWorkingProtocolTemplateRecords(
      herdPublicID: herdPublicID,
      in: sharedStore
    )
    let workingProtocolTemplateResult = try upsertSwiftDataWorkingProtocolTemplates(
      from: sharedWorkingProtocolTemplates,
      herd: herd,
      in: swiftDataContext
    )
    let sharedWorkingSessions = try fetchSharedWorkingSessionRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let workingSessionResult = try upsertSwiftDataWorkingSessions(
      from: sharedWorkingSessions,
      herd: herd,
      in: swiftDataContext
    )
    let sharedWorkingQueueItems = try fetchSharedWorkingQueueItemRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let workingQueueItemResult = try upsertSwiftDataWorkingQueueItems(
      from: sharedWorkingQueueItems,
      herd: herd,
      in: swiftDataContext
    )
    let sharedWorkingTreatmentRecords = try fetchSharedWorkingTreatmentRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let workingTreatmentRecordResult = try upsertSwiftDataWorkingTreatmentRecords(
      from: sharedWorkingTreatmentRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedHealthRecords = try fetchSharedHealthRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let healthRecordResult = try upsertSwiftDataHealthRecords(
      from: sharedHealthRecords,
      herd: herd,
      in: swiftDataContext
    )
    let sharedPregnancyChecks = try fetchSharedPregnancyCheckRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let pregnancyCheckResult = try upsertSwiftDataPregnancyChecks(
      from: sharedPregnancyChecks,
      herd: herd,
      in: swiftDataContext
    )
    let sharedFieldCheckSessions = try fetchSharedFieldCheckSessionRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let fieldCheckSessionResult = try upsertSwiftDataFieldCheckSessions(
      from: sharedFieldCheckSessions,
      herd: herd,
      in: swiftDataContext
    )
    let sharedFieldCheckAnimalChecks = try fetchSharedFieldCheckAnimalCheckRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let fieldCheckAnimalCheckResult = try upsertSwiftDataFieldCheckAnimalChecks(
      from: sharedFieldCheckAnimalChecks,
      herd: herd,
      in: swiftDataContext
    )
    let sharedFieldCheckFindings = try fetchSharedFieldCheckFindingRecords(
      herdPublicID: herdPublicID, in: sharedStore)
    let fieldCheckFindingResult = try upsertSwiftDataFieldCheckFindings(
      from: sharedFieldCheckFindings,
      herd: herd,
      in: swiftDataContext
    )
    let sharedDeletedRecords = try fetchSharedDeletedRecords(
      herdPublicID: herdPublicID,
      in: sharedStore
    )
    let deletionResult = try deleteSwiftDataRecords(
      from: sharedDeletedRecords,
      herd: herd,
      in: swiftDataContext
    )
    let updatedRecordConflicts = tagColorDefinitionResult.updatedRecordConflicts
      + statusReferenceResult.updatedRecordConflicts
      + animalTagResult.updatedRecordConflicts
      + pastureGroupResult.updatedRecordConflicts
      + pastureResult.updatedRecordConflicts
      + animalResult.updatedRecordConflicts
      + movementResult.updatedRecordConflicts
      + statusRecordResult.updatedRecordConflicts
      + healthRecordResult.updatedRecordConflicts
      + pregnancyCheckResult.updatedRecordConflicts
      + workingProtocolTemplateResult.updatedRecordConflicts
      + workingSessionResult.updatedRecordConflicts
      + workingQueueItemResult.updatedRecordConflicts
      + workingTreatmentRecordResult.updatedRecordConflicts
      + fieldCheckSessionResult.updatedRecordConflicts
      + fieldCheckAnimalCheckResult.updatedRecordConflicts
      + fieldCheckFindingResult.updatedRecordConflicts
    let conflictReport = HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: updatedRecordConflicts.count,
      updatedRecordConflicts: updatedRecordConflicts,
      preventedDeleteConflicts: deletionResult.preventedDeleteConflicts
    )

    if swiftDataContext.hasChanges {
      try swiftDataContext.save()
    }

    return HerdSharingBridgeImportResult(
      herdName: herd.name,
      insertedTagColorDefinitionCount: tagColorDefinitionResult.inserted,
      updatedTagColorDefinitionCount: tagColorDefinitionResult.updated,
      insertedStatusReferenceCount: statusReferenceResult.inserted,
      updatedStatusReferenceCount: statusReferenceResult.updated,
      insertedAnimalTagCount: animalTagResult.inserted,
      updatedAnimalTagCount: animalTagResult.updated,
      insertedPastureGroupCount: pastureGroupResult.inserted,
      updatedPastureGroupCount: pastureGroupResult.updated,
      insertedPastureCount: pastureResult.inserted,
      updatedPastureCount: pastureResult.updated,
      insertedAnimalCount: animalResult.inserted,
      updatedAnimalCount: animalResult.updated,
      insertedMovementCount: movementResult.inserted,
      updatedMovementCount: movementResult.updated,
      insertedStatusRecordCount: statusRecordResult.inserted,
      updatedStatusRecordCount: statusRecordResult.updated,
      insertedHealthRecordCount: healthRecordResult.inserted,
      updatedHealthRecordCount: healthRecordResult.updated,
      insertedPregnancyCheckCount: pregnancyCheckResult.inserted,
      updatedPregnancyCheckCount: pregnancyCheckResult.updated,
      insertedWorkingProtocolTemplateCount: workingProtocolTemplateResult.inserted,
      updatedWorkingProtocolTemplateCount: workingProtocolTemplateResult.updated,
      insertedWorkingSessionCount: workingSessionResult.inserted,
      updatedWorkingSessionCount: workingSessionResult.updated,
      insertedWorkingQueueItemCount: workingQueueItemResult.inserted,
      updatedWorkingQueueItemCount: workingQueueItemResult.updated,
      insertedWorkingTreatmentRecordCount: workingTreatmentRecordResult.inserted,
      updatedWorkingTreatmentRecordCount: workingTreatmentRecordResult.updated,
      insertedFieldCheckSessionCount: fieldCheckSessionResult.inserted,
      updatedFieldCheckSessionCount: fieldCheckSessionResult.updated,
      insertedFieldCheckAnimalCheckCount: fieldCheckAnimalCheckResult.inserted,
      updatedFieldCheckAnimalCheckCount: fieldCheckAnimalCheckResult.updated,
      insertedFieldCheckFindingCount: fieldCheckFindingResult.inserted,
      updatedFieldCheckFindingCount: fieldCheckFindingResult.updated,
      deletedRecordCount: deletionResult.deletedCount,
      conflictReport: conflictReport
    )
  }

  private func shareRecords(
    _ records: [NSManagedObject],
    title: String
  ) async throws -> CKShare {
    let existingCKShare =
      try records
      .compactMap { record in
        try self.existingShare(for: record)
      }
      .first

    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<CKShare, Error>) in
      persistentContainer.share(records, to: existingCKShare) { _, share, _, error in
        if let error {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
          return
        }

        guard let share else {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(
              "Core Data did not return a CKShare."))
          return
        }

        share[CKShare.SystemFieldKey.title] = title as NSString
        continuation.resume(returning: share)
      }
    }
  }

  private func existingShare(for record: NSManagedObject) throws -> CKShare? {
    let shares = try persistentContainer.fetchShares(matching: [record.objectID])
    return shares[record.objectID]
  }

  private func sharingPermission(from share: CKShare) -> HerdSharingAccess.Permission {
    guard let currentUserParticipant = share.currentUserParticipant else {
      return .unknown
    }

    switch currentUserParticipant.permission {
    case .readOnly:
      return .readOnly
    case .readWrite:
      return .readWrite
    case .unknown, .none:
      return .unknown
    @unknown default:
      return .unknown
    }
  }

  private func persistUpdatedShare(_ share: CKShare) async {
    guard let privateStore else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      persistentContainer.persistUpdatedShare(
        share,
        in: privateStore
      ) { _, _ in
        continuation.resume()
      }
    }
  }

  private func purgeStoppedShare(_ share: CKShare) async {
    guard let privateStore else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      persistentContainer.purgeObjectsAndRecordsInZone(
        with: share.recordID.zoneID,
        in: privateStore
      ) { _, _ in
        continuation.resume()
      }
    }
  }

  private func upsertSwiftDataHerd(
    from sharedRecord: SharedHerdRecord,
    in context: ModelContext
  ) throws -> Herd {
    guard let sharedPublicID = sharedRecord.parsedPublicID else {
      throw HerdSharingActionError.bridgeImportFailed(
        "The shared herd record is missing a valid public ID.")
    }

    if let existingHerd = try fetchSwiftDataHerd(publicID: sharedPublicID, in: context) {
      apply(sharedRecord, to: existingHerd)
      return existingHerd
    }

    let herd = try DefaultHerdBootstrapper.defaultHerd(in: context)
    herd.publicID = sharedPublicID
    apply(sharedRecord, to: herd)
    return herd
  }

  private func apply(_ sharedRecord: SharedHerdRecord, to herd: Herd) {
    herd.name =
      sharedRecord.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? DefaultHerdBootstrapper.defaultHerdName
    herd.createdAt = sharedRecord.createdAt ?? herd.createdAt
    herd.updatedAt = sharedRecord.updatedAt ?? Date.now
    herd.schemaVersion = sharedRecord.schemaVersion?.intValue ?? herd.schemaVersion
  }

  private func upsertSwiftDataTagColorDefinitions(
    from sharedRecords: [SharedTagColorDefinitionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataStatusReferences(
    from sharedRecords: [SharedAnimalStatusReferenceRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
    _ sharedRecord: SharedAnimalStatusReferenceRecord,
    to reference: AnimalStatusReference,
    herd: Herd
  ) {
    reference.herd = herd
    reference.name = sharedRecord.name ?? ""
    reference.baseStatus = sharedRecord.parsedBaseStatus
    reference.createdAt = sharedRecord.createdAt ?? reference.createdAt
  }

  private func upsertSwiftDataPastureGroups(
    from sharedRecords: [SharedPastureGroupRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
    _ sharedRecord: SharedPastureGroupRecord,
    to group: PastureGroup,
    herd: Herd
  ) {
    group.herd = herd
    group.name = sharedRecord.name ?? ""
    group.grazeDays = sharedRecord.grazeDays?.intValue ?? group.grazeDays
    group.restDays = sharedRecord.restDays?.intValue ?? group.restDays
  }

  private func upsertSwiftDataPastures(
    from sharedRecords: [SharedPastureRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataAnimals(
    from sharedRecords: [SharedAnimalRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataAnimalTags(
    from sharedRecords: [SharedAnimalTagRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataMovements(
    from sharedRecords: [SharedMovementRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataStatusRecords(
    from sharedRecords: [SharedStatusRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataWorkingProtocolTemplates(
    from sharedRecords: [SharedWorkingProtocolTemplateRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
    _ sharedRecord: SharedWorkingProtocolTemplateRecord,
    to template: WorkingProtocolTemplate,
    herd: Herd
  ) {
    template.herd = herd
    template.name = sharedRecord.name ?? ""
    template.items = sharedRecord.parsedItems
  }

  private func upsertSwiftDataWorkingSessions(
    from sharedRecords: [SharedWorkingSessionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataWorkingQueueItems(
    from sharedRecords: [SharedWorkingQueueItemRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataWorkingTreatmentRecords(
    from sharedRecords: [SharedWorkingTreatmentRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataHealthRecords(
    from sharedRecords: [SharedHealthRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataPregnancyChecks(
    from sharedRecords: [SharedPregnancyCheckRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataFieldCheckSessions(
    from sharedRecords: [SharedFieldCheckSessionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataFieldCheckAnimalChecks(
    from sharedRecords: [SharedFieldCheckAnimalCheckRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private func upsertSwiftDataFieldCheckFindings(
    from sharedRecords: [SharedFieldCheckFindingRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]) {
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

  private func apply(
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

  private typealias HerdSharingConflictFieldSnapshot = [String: HerdSharingBridgeConflictValue]

  private func updatedRecordConflict(
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

  private func updatedRecordConflict(
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

  private func conflictFieldChanges(
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

  private func conflictValue(_ value: Any?) -> HerdSharingBridgeConflictValue {
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

  private func conflictFieldSnapshot(_ values: [String: Any?]) -> HerdSharingConflictFieldSnapshot {
    values.reduce(into: HerdSharingConflictFieldSnapshot()) { result, item in
      result[item.key] = conflictValue(item.value)
    }
  }

  private func conflictFieldSnapshot(for definition: TagColorDefinition) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for reference: AnimalStatusReference) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": reference.name,
      "baseStatus": reference.baseStatus,
      "createdAt": reference.createdAt,
    ])
  }

  private func conflictFieldSnapshot(for group: PastureGroup) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": group.name,
      "grazeDays": group.grazeDays,
      "restDays": group.restDays,
    ])
  }

  private func conflictFieldSnapshot(for pasture: Pasture) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for animal: Animal) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for tag: AnimalTag) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for movement: MovementRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": movement.date,
      "fromPasture": movement.fromPasture,
      "toPasture": movement.toPasture,
      "animalPublicID": movement.animal?.publicID,
    ])
  }

  private func conflictFieldSnapshot(for statusRecord: StatusRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": statusRecord.date,
      "oldStatus": statusRecord.oldStatus,
      "newStatus": statusRecord.newStatus,
      "oldStatusReferenceID": statusRecord.oldStatusReferenceID,
      "newStatusReferenceID": statusRecord.newStatusReferenceID,
      "animalPublicID": statusRecord.animal?.publicID,
    ])
  }

  private func conflictFieldSnapshot(for template: WorkingProtocolTemplate) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "name": template.name,
      "items": template.items,
    ])
  }

  private func conflictFieldSnapshot(for session: WorkingSession) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for queueItem: WorkingQueueItem) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for treatmentRecord: WorkingTreatmentRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": treatmentRecord.date,
      "itemName": treatmentRecord.itemName,
      "given": treatmentRecord.given,
      "quantity": treatmentRecord.quantity,
      "sessionPublicID": treatmentRecord.session?.publicID,
      "animalPublicID": treatmentRecord.animal?.publicID,
    ])
  }

  private func conflictFieldSnapshot(for healthRecord: HealthRecord) -> HerdSharingConflictFieldSnapshot {
    conflictFieldSnapshot([
      "date": healthRecord.date,
      "treatment": healthRecord.treatment,
      "notes": healthRecord.notes,
      "workingSessionPublicID": healthRecord.workingSession?.publicID,
      "animalPublicID": healthRecord.animal?.publicID,
    ])
  }

  private func conflictFieldSnapshot(for check: PregnancyCheck) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for session: FieldCheckSession) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for check: FieldCheckAnimalCheck) -> HerdSharingConflictFieldSnapshot {
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

  private func conflictFieldSnapshot(for finding: FieldCheckFinding) -> HerdSharingConflictFieldSnapshot {
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

    if context.hasChanges {
      try context.save()
    }

    return deletedCount
  }

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

    if context.hasChanges {
      try context.save()
    }

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
      guard let animal = try fetchSwiftDataRecord(
        Animal.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreAnimalLocalField(fieldName: fieldName, value: value, animal: animal)
    case SharedPastureRecord.entityName:
      guard let pasture = try fetchSwiftDataRecord(
        Pasture.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restorePastureLocalField(fieldName: fieldName, value: value, pasture: pasture)
    case SharedHealthRecord.entityName:
      guard let healthRecord = try fetchSwiftDataRecord(
        HealthRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreHealthRecordLocalField(
        fieldName: fieldName,
        value: value,
        healthRecord: healthRecord
      )
    case SharedMovementRecord.entityName:
      guard let movement = try fetchSwiftDataRecord(
        MovementRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreMovementRecordLocalField(fieldName: fieldName, value: value, movement: movement)
    case SharedPregnancyCheckRecord.entityName:
      guard let check = try fetchSwiftDataRecord(
        PregnancyCheck.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restorePregnancyCheckLocalField(fieldName: fieldName, value: value, check: check)
    case SharedStatusRecord.entityName:
      guard let statusRecord = try fetchSwiftDataRecord(
        StatusRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreStatusRecordLocalField(
        fieldName: fieldName,
        value: value,
        statusRecord: statusRecord
      )
    case SharedAnimalTagRecord.entityName:
      guard let tag = try fetchSwiftDataRecord(
        AnimalTag.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreAnimalTagLocalField(fieldName: fieldName, value: value, tag: tag)
    case SharedTagColorDefinitionRecord.entityName:
      guard let definition = try fetchSwiftDataRecord(
        TagColorDefinition.self,
        publicID: publicID,
        keyPath: \.id,
        in: context
      ) else { return false }
      return restoreTagColorDefinitionLocalField(
        fieldName: fieldName,
        value: value,
        definition: definition
      )
    case SharedAnimalStatusReferenceRecord.entityName:
      guard let reference = try fetchSwiftDataRecord(
        AnimalStatusReference.self,
        publicID: publicID,
        keyPath: \.id,
        in: context
      ) else { return false }
      return restoreAnimalStatusReferenceLocalField(
        fieldName: fieldName,
        value: value,
        reference: reference
      )
    case SharedPastureGroupRecord.entityName:
      guard let group = try fetchSwiftDataRecord(
        PastureGroup.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restorePastureGroupLocalField(fieldName: fieldName, value: value, group: group)
    case SharedWorkingProtocolTemplateRecord.entityName:
      guard let template = try fetchSwiftDataRecord(
        WorkingProtocolTemplate.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreWorkingProtocolTemplateLocalField(
        fieldName: fieldName,
        value: value,
        template: template
      )
    case SharedWorkingSessionRecord.entityName:
      guard let session = try fetchSwiftDataRecord(
        WorkingSession.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreWorkingSessionLocalField(fieldName: fieldName, value: value, session: session)
    case SharedWorkingQueueItemRecord.entityName:
      guard let queueItem = try fetchSwiftDataRecord(
        WorkingQueueItem.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreWorkingQueueItemLocalField(
        fieldName: fieldName,
        value: value,
        queueItem: queueItem
      )
    case SharedWorkingTreatmentRecord.entityName:
      guard let treatmentRecord = try fetchSwiftDataRecord(
        WorkingTreatmentRecord.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreWorkingTreatmentRecordLocalField(
        fieldName: fieldName,
        value: value,
        treatmentRecord: treatmentRecord
      )
    case SharedFieldCheckSessionRecord.entityName:
      guard let session = try fetchSwiftDataRecord(
        FieldCheckSession.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreFieldCheckSessionLocalField(fieldName: fieldName, value: value, session: session)
    case SharedFieldCheckAnimalCheckRecord.entityName:
      guard let check = try fetchSwiftDataRecord(
        FieldCheckAnimalCheck.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreFieldCheckAnimalCheckLocalField(fieldName: fieldName, value: value, check: check)
    case SharedFieldCheckFindingRecord.entityName:
      guard let finding = try fetchSwiftDataRecord(
        FieldCheckFinding.self,
        publicID: publicID,
        keyPath: \.publicID,
        in: context
      ) else { return false }
      return restoreFieldCheckFindingLocalField(fieldName: fieldName, value: value, finding: finding)
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
      guard let rawValue = value.stringValue, let sex = Sex(rawValue: rawValue) else { return false }
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
      guard let rawValue = value.stringValue, let location = AnimalLocation(rawValue: rawValue) else {
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
      guard let rawValue = value.stringValue, let result = PregnancyResult(rawValue: rawValue) else {
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
      guard let rawValue = value.stringValue, let status = WorkingSessionStatus(rawValue: rawValue) else {
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
      guard let rawValue = value.stringValue, let status = WorkingQueueStatus(rawValue: rawValue) else {
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
    case "quantity":
      if value.isNull {
        treatmentRecord.quantity = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        treatmentRecord.quantity = doubleValue
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
      guard let rawValue = value.stringValue, let sex = Sex(rawValue: rawValue) else { return false }
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
      guard let rawValue = value.stringValue, let type = FieldCheckFindingType(rawValue: rawValue) else {
        return false
      }
      finding.type = type
    case "severity":
      guard let rawValue = value.stringValue, let severity = FieldCheckFindingSeverity(rawValue: rawValue) else {
        return false
      }
      finding.severity = severity
    case "status":
      guard let rawValue = value.stringValue, let status = FieldCheckFindingStatus(rawValue: rawValue) else {
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

  private func deleteSwiftDataRecords(
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

  private func fetchSwiftDataRecord<T: PersistentModel>(
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

  private func fetchSwiftDataHerd(
    publicID: UUID,
    in context: ModelContext
  ) throws -> Herd? {
    try context.fetch(FetchDescriptor<Herd>()).first { herd in
      herd.publicID == publicID
    }
  }

  private func sharedHerdRecordSort(_ lhs: SharedHerdRecord, _ rhs: SharedHerdRecord) -> Bool {
    let lhsDate = lhs.lastMirroredAt ?? lhs.updatedAt ?? lhs.createdAt ?? .distantPast
    let rhsDate = rhs.lastMirroredAt ?? rhs.updatedAt ?? rhs.createdAt ?? .distantPast
    return lhsDate > rhsDate
  }

  private func fetchSharedHerdRecords(in store: NSPersistentStore) throws -> [SharedHerdRecord] {
    let request = SharedHerdRecord.fetchRequest()
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedHerdRecord(
    publicID: UUID,
    in store: NSPersistentStore
  ) throws -> SharedHerdRecord? {
    let request = SharedHerdRecord.fetchRequest()
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "publicID == %@", publicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request).first
  }

  private func fetchSharedTagColorDefinitionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedTagColorDefinitionRecord] {
    let request = SharedTagColorDefinitionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedAnimalStatusReferenceRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalStatusReferenceRecord] {
    let request = SharedAnimalStatusReferenceRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedAnimalTagRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalTagRecord] {
    let request = SharedAnimalTagRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedPastureGroupRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPastureGroupRecord] {
    let request = SharedPastureGroupRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedPastureRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPastureRecord] {
    let request = SharedPastureRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedAnimalRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedAnimalRecord] {
    let request = SharedAnimalRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedMovementRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedMovementRecord] {
    let request = SharedMovementRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedStatusRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedStatusRecord] {
    let request = SharedStatusRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedHealthRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedHealthRecord] {
    let request = SharedHealthRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedPregnancyCheckRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedPregnancyCheckRecord] {
    let request = SharedPregnancyCheckRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedWorkingProtocolTemplateRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingProtocolTemplateRecord] {
    let request = SharedWorkingProtocolTemplateRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedWorkingSessionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingSessionRecord] {
    let request = SharedWorkingSessionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedWorkingQueueItemRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingQueueItemRecord] {
    let request = SharedWorkingQueueItemRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedWorkingTreatmentRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedWorkingTreatmentRecord] {
    let request = SharedWorkingTreatmentRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedFieldCheckSessionRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckSessionRecord] {
    let request = SharedFieldCheckSessionRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedFieldCheckAnimalCheckRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckAnimalCheckRecord] {
    let request = SharedFieldCheckAnimalCheckRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedFieldCheckFindingRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedFieldCheckFindingRecord] {
    let request = SharedFieldCheckFindingRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedDeletedRecords(
    herdPublicID: UUID,
    in store: NSPersistentStore
  ) throws -> [SharedDeletedRecord] {
    let request = SharedDeletedRecord.fetchRequest()
    request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
    request.affectedStores = [store]
    return try persistentContainer.viewContext.fetch(request)
  }

  private func fetchSharedDeletedRecord(
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
    return try persistentContainer.viewContext.fetch(request).first
  }

  private func store(named fileName: String) -> NSPersistentStore? {
    persistentContainer.persistentStoreCoordinator.persistentStores.first { store in
      store.url?.lastPathComponent == fileName
    }
  }

  private static func makeStoreDescription(
    url: URL,
    containerIdentifier: String,
    databaseScope: CKDatabase.Scope
  ) -> NSPersistentStoreDescription {
    let description = NSPersistentStoreDescription(url: url)
    let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
    options.databaseScope = databaseScope
    description.cloudKitContainerOptions = options
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(
      true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    return description
  }

  private static func defaultStoreDirectoryURL() -> URL {
    let applicationSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return applicationSupportURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
  }
}
