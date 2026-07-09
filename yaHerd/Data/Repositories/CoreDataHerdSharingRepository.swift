//
//  CoreDataHerdSharingRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class CoreDataHerdSharingRepository: HerdSharingRepository {
  private let context: ModelContext
  private let store: HerdSharingCoreDataStore

  init(
    context: ModelContext,
    store: HerdSharingCoreDataStore? = nil
  ) {
    self.context = context
    self.store = store ?? HerdSharingCoreDataStore()
  }

  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    guard herd != nil else {
      return .shareRootMissing
    }

    switch storageMode {
    case .localOnly:
      return .iCloudSyncRequired
    case .iCloud:
      return .sharingAdapterAvailable
    }
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    guard let herd else {
      throw HerdSharingActionError.shareRootMissing
    }

    return try await store.fetchSharingAccess(for: herd)
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.startSharing.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration("CoreDataHerdSharingRepository.startSharing", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.startSharing.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    let tagColorDefinitions = try fetchSwiftDataTagColorDefinitions(for: herd)
    let statusReferences = try fetchSwiftDataStatusReferences(for: herd)
    let pastureGroups = try fetchSwiftDataPastureGroups(for: herd)
    let pastures = try fetchSwiftDataPastures(for: herd)
    let animals = try fetchSwiftDataAnimals(for: herd)
    let animalTags = try fetchSwiftDataAnimalTags(for: herd)
    let movements = try fetchSwiftDataMovements(for: herd)
    let statusRecords = try fetchSwiftDataStatusRecords(for: herd)
    let healthRecords = try fetchSwiftDataHealthRecords(for: herd)
    let pregnancyChecks = try fetchSwiftDataPregnancyChecks(for: herd)
    let workingProtocolTemplates = try fetchSwiftDataWorkingProtocolTemplates(for: herd)
    let workingSessions = try fetchSwiftDataWorkingSessions(for: herd)
    let workingQueueItems = try fetchSwiftDataWorkingQueueItems(for: herd)
    let workingTreatmentRecords = try fetchSwiftDataWorkingTreatmentRecords(for: herd)
    let fieldCheckSessions = try fetchSwiftDataFieldCheckSessions(for: herd)
    let fieldCheckAnimalChecks = try fetchSwiftDataFieldCheckAnimalChecks(for: herd)
    let fieldCheckFindings = try fetchSwiftDataFieldCheckFindings(for: herd)
    let systemShare = try await store.makeSystemShare(
      for: herd,
      tagColorDefinitions: tagColorDefinitions,
      statusReferences: statusReferences,
      animalTags: animalTags,
      pastureGroups: pastureGroups,
      pastures: pastures,
      animals: animals,
      movements: movements,
      statusRecords: statusRecords,
      healthRecords: healthRecords,
      pregnancyChecks: pregnancyChecks,
      workingProtocolTemplates: workingProtocolTemplates,
      workingSessions: workingSessions,
      workingQueueItems: workingQueueItems,
      workingTreatmentRecords: workingTreatmentRecords,
      fieldCheckSessions: fieldCheckSessions,
      fieldCheckAnimalChecks: fieldCheckAnimalChecks,
      fieldCheckFindings: fieldCheckFindings
    )
    return HerdSharingActionResult(
      title: "Share sheet ready",
      message:
        "Invite people through the system CloudKit sharing sheet. SwiftData remains the app data store; Core Data now mirrors the herd root, \(tagColorDefinitions.count) tag color definitions, \(statusReferences.count) custom status references, \(pastureGroups.count) pasture groups, \(pastures.count) pastures, \(animals.count) animal records, \(animalTags.count) animal tags, \(movements.count) movement records, \(statusRecords.count) status history records, \(healthRecords.count) health records, \(pregnancyChecks.count) pregnancy checks, \(workingProtocolTemplates.count) working protocol templates, \(workingSessions.count) working sessions, \(workingQueueItems.count) working queue items, \(workingTreatmentRecords.count) working treatment records, \(fieldCheckSessions.count) field check sessions, \(fieldCheckAnimalChecks.count) field check animal checks, and \(fieldCheckFindings.count) field check findings for CloudKit sharing.",
      systemShare: systemShare
    )
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.acceptShareInvitation.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration("CoreDataHerdSharingRepository.acceptShareInvitation", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.acceptShareInvitation.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    try await store.acceptShareInvitation(metadata: invitation.metadata)

    do {
      let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
      return HerdSharingActionResult(
        title: "Invitation accepted",
        message:
          "Imported \(importResult.importedTagColorDefinitionCount) tag color definitions, \(importResult.importedStatusReferenceCount) custom status references, \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animal records, \(importResult.importedAnimalTagCount) animal tags, \(importResult.importedMovementCount) movement records, \(importResult.importedStatusRecordCount) status history records, \(importResult.importedHealthRecordCount) health records, \(importResult.importedPregnancyCheckCount) pregnancy checks, \(importResult.importedWorkingProtocolTemplateCount) working protocol templates, \(importResult.importedWorkingSessionCount) working sessions, \(importResult.importedWorkingQueueItemCount) queue items, \(importResult.importedWorkingTreatmentRecordCount) treatment records, \(importResult.importedFieldCheckSessionCount) field check sessions, \(importResult.importedFieldCheckAnimalCheckCount) field check animal checks, and \(importResult.importedFieldCheckFindingCount) field check findings from the Core Data sharing bridge into SwiftData for \(importResult.herdName). Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary)",
        conflictReview: makeConflictReview(
          from: importResult,
          sourceDescription: "Invitation accepted"
        )
      )
    } catch HerdSharingActionError.bridgeImportFailed(_) {
      return HerdSharingActionResult(
        title: "Invitation accepted",
        message:
          "The CloudKit share was accepted into the Core Data bridge, but shared records were not available to import into SwiftData yet. Use Import Shared Data after CloudKit finishes syncing."
      )
    }
  }

  func importSharedBridgeData(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult
  {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.importSharedBridgeData.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration("CoreDataHerdSharingRepository.importSharedBridgeData", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.importSharedBridgeData.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
    return HerdSharingActionResult(
      title: "Shared data imported",
      message:
        "Imported \(importResult.insertedTagColorDefinitionCount) new/\(importResult.updatedTagColorDefinitionCount) existing tag color definitions, \(importResult.insertedStatusReferenceCount) new/\(importResult.updatedStatusReferenceCount) existing custom status references, \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedAnimalTagCount) new/\(importResult.updatedAnimalTagCount) existing animal tags, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records, \(importResult.insertedHealthRecordCount) new/\(importResult.updatedHealthRecordCount) existing health records, \(importResult.insertedPregnancyCheckCount) new/\(importResult.updatedPregnancyCheckCount) existing pregnancy checks, \(importResult.insertedWorkingProtocolTemplateCount) new/\(importResult.updatedWorkingProtocolTemplateCount) existing working protocol templates, \(importResult.insertedWorkingSessionCount) new/\(importResult.updatedWorkingSessionCount) existing working sessions, \(importResult.insertedWorkingQueueItemCount) new/\(importResult.updatedWorkingQueueItemCount) existing queue items, \(importResult.insertedWorkingTreatmentRecordCount) new/\(importResult.updatedWorkingTreatmentRecordCount) existing treatment records, \(importResult.insertedFieldCheckSessionCount) new/\(importResult.updatedFieldCheckSessionCount) existing field check sessions, \(importResult.insertedFieldCheckAnimalCheckCount) new/\(importResult.updatedFieldCheckAnimalCheckCount) existing field check animal checks, and \(importResult.insertedFieldCheckFindingCount) new/\(importResult.updatedFieldCheckFindingCount) existing field check findings from the Core Data sharing bridge into SwiftData for \(importResult.herdName). Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary)",
      conflictReview: makeConflictReview(
        from: importResult,
        sourceDescription: "Manual shared-data import"
      )
    )
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    guard review.preventedDeleteCount > 0 else {
      return HerdSharingActionResult(
        title: "No shared deletes to accept",
        message: "This conflict report does not contain skipped shared deletes."
      )
    }

    let deletedCount = try store.acceptPreventedSharedDeletes(
      review.preventedDeleteConflicts,
      context: context
    )

    return HerdSharingActionResult(
      title: "Shared deletes accepted",
      message:
        "Deleted \(deletedCount) of \(review.preventedDeleteCount) local SwiftData record(s) from skipped shared deletes. Run Sync Shared Data to keep the Core Data sharing bridge aligned."
    )
  }


  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    guard !selections.isEmpty else {
      return HerdSharingActionResult(
        title: "No local fields selected",
        message: "Select one or more changed fields before restoring local values."
      )
    }

    let result = try store.restoreLocalFields(
      selections,
      from: review,
      context: context
    )

    return HerdSharingActionResult(
      title: "Local fields restored",
      message:
        "Restored \(result.restoredFieldCount) of \(result.requestedFieldCount) selected local field value(s). Skipped \(result.skippedFieldCount) unsupported or stale field value(s). Run Sync Shared Data to re-export restored local values."
    )
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.syncSharedBridgeData.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration("CoreDataHerdSharingRepository.syncSharedBridgeData", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.syncSharedBridgeData.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    guard let herd else {
      throw HerdSharingActionError.shareRootMissing
    }

    let access = try await store.fetchSharingAccess(for: herd)
    guard access.canExportLocalChangesToBridge else {
      return try await importOnlySyncResult(access: access)
    }

    let tagColorDefinitions = try fetchSwiftDataTagColorDefinitions(for: herd)
    let statusReferences = try fetchSwiftDataStatusReferences(for: herd)
    let pastureGroups = try fetchSwiftDataPastureGroups(for: herd)
    let pastures = try fetchSwiftDataPastures(for: herd)
    let animals = try fetchSwiftDataAnimals(for: herd)
    let animalTags = try fetchSwiftDataAnimalTags(for: herd)
    let movements = try fetchSwiftDataMovements(for: herd)
    let statusRecords = try fetchSwiftDataStatusRecords(for: herd)
    let healthRecords = try fetchSwiftDataHealthRecords(for: herd)
    let pregnancyChecks = try fetchSwiftDataPregnancyChecks(for: herd)
    let workingProtocolTemplates = try fetchSwiftDataWorkingProtocolTemplates(for: herd)
    let workingSessions = try fetchSwiftDataWorkingSessions(for: herd)
    let workingQueueItems = try fetchSwiftDataWorkingQueueItems(for: herd)
    let workingTreatmentRecords = try fetchSwiftDataWorkingTreatmentRecords(for: herd)
    let fieldCheckSessions = try fetchSwiftDataFieldCheckSessions(for: herd)
    let fieldCheckAnimalChecks = try fetchSwiftDataFieldCheckAnimalChecks(for: herd)
    let fieldCheckFindings = try fetchSwiftDataFieldCheckFindings(for: herd)

    let exportResult = try await store.syncBridgeRecordsFromSwiftData(
      herd: herd,
      tagColorDefinitions: tagColorDefinitions,
      statusReferences: statusReferences,
      animalTags: animalTags,
      pastureGroups: pastureGroups,
      pastures: pastures,
      animals: animals,
      movements: movements,
      statusRecords: statusRecords,
      healthRecords: healthRecords,
      pregnancyChecks: pregnancyChecks,
      workingProtocolTemplates: workingProtocolTemplates,
      workingSessions: workingSessions,
      workingQueueItems: workingQueueItems,
      workingTreatmentRecords: workingTreatmentRecords,
      fieldCheckSessions: fieldCheckSessions,
      fieldCheckAnimalChecks: fieldCheckAnimalChecks,
      fieldCheckFindings: fieldCheckFindings
    )

    let importMessage: String
    let conflictReview: HerdSharingConflictReview?
    do {
      let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
      importMessage =
        "Imported \(importResult.insertedTagColorDefinitionCount) new/\(importResult.updatedTagColorDefinitionCount) existing tag color definitions, \(importResult.insertedStatusReferenceCount) new/\(importResult.updatedStatusReferenceCount) existing custom status references, \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedAnimalTagCount) new/\(importResult.updatedAnimalTagCount) existing animal tags, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records, \(importResult.insertedHealthRecordCount) new/\(importResult.updatedHealthRecordCount) existing health records, \(importResult.insertedPregnancyCheckCount) new/\(importResult.updatedPregnancyCheckCount) existing pregnancy checks, \(importResult.insertedWorkingProtocolTemplateCount) new/\(importResult.updatedWorkingProtocolTemplateCount) existing working protocol templates, \(importResult.insertedWorkingSessionCount) new/\(importResult.updatedWorkingSessionCount) existing working sessions, \(importResult.insertedWorkingQueueItemCount) new/\(importResult.updatedWorkingQueueItemCount) existing queue items, \(importResult.insertedWorkingTreatmentRecordCount) new/\(importResult.updatedWorkingTreatmentRecordCount) existing treatment records, \(importResult.insertedFieldCheckSessionCount) new/\(importResult.updatedFieldCheckSessionCount) existing field check sessions, \(importResult.insertedFieldCheckAnimalCheckCount) new/\(importResult.updatedFieldCheckAnimalCheckCount) existing field check animal checks, and \(importResult.insertedFieldCheckFindingCount) new/\(importResult.updatedFieldCheckFindingCount) existing field check findings from shared bridge records. Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary)"
      conflictReview = makeConflictReview(
        from: importResult,
        sourceDescription: "Shared-data sync"
      )
    } catch HerdSharingActionError.bridgeImportFailed(_) {
      importMessage =
        "No accepted shared-store records were available to import. This is expected before accepting a share or before CloudKit finishes downloading shared records."
      conflictReview = nil
    }

    let cloudKitMessage =
      exportResult.didUpdateExistingCloudKitShare
      ? "Existing CloudKit share membership was updated with the mirrored records."
      : "No existing owner-side CKShare needed updating; records were saved into the \(exportResult.writeTargetDescription)."

    return HerdSharingActionResult(
      title: "Shared data synced",
      message:
        "Exported \(exportResult.exportedRecordCount) bridge records for \(exportResult.herdName) into the \(exportResult.writeTargetDescription). \(cloudKitMessage) \(importMessage)",
      conflictReview: conflictReview
    )
  }

  private func importOnlySyncResult(
    access: HerdSharingAccess
  ) async throws -> HerdSharingActionResult {
    do {
      let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
      return HerdSharingActionResult(
        title: "Shared data imported",
        message:
          "Your CloudKit share access is \(access.permissionDescription) in the \(access.locationDescription), so yaHerd did not export local SwiftData changes back into the shared bridge. Imported \(importResult.importedTagColorDefinitionCount) tag color definitions, \(importResult.importedStatusReferenceCount) custom status references, \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animals, \(importResult.importedAnimalTagCount) animal tags, \(importResult.importedMovementCount) movement records, \(importResult.importedStatusRecordCount) status history records, \(importResult.importedHealthRecordCount) health records, \(importResult.importedPregnancyCheckCount) pregnancy checks, \(importResult.importedWorkingProtocolTemplateCount) working protocol templates, \(importResult.importedWorkingSessionCount) working sessions, \(importResult.importedWorkingQueueItemCount) queue items, \(importResult.importedWorkingTreatmentRecordCount) treatment records, \(importResult.importedFieldCheckSessionCount) field check sessions, \(importResult.importedFieldCheckAnimalCheckCount) field check animal checks, and \(importResult.importedFieldCheckFindingCount) field check findings from shared bridge records. Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary)",
        conflictReview: makeConflictReview(
          from: importResult,
          sourceDescription: "Read-only shared-data import"
        )
      )
    } catch HerdSharingActionError.bridgeImportFailed(_) {
      return HerdSharingActionResult(
        title: "Shared data not exported",
        message:
          "Your CloudKit share access is \(access.permissionDescription) in the \(access.locationDescription), so yaHerd did not export local SwiftData changes back into the shared bridge. No accepted shared-store records were available to import yet."
      )
    }
  }

  private func makeConflictReview(
    from importResult: HerdSharingBridgeImportResult,
    sourceDescription: String
  ) -> HerdSharingConflictReview? {
    let report = importResult.conflictReport
    guard report.hasConflicts else { return nil }

    return HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: sourceDescription,
      detectedAt: .now,
      existingLocalRecordUpdateCount: report.existingLocalRecordUpdateCount,
      updatedRecordConflicts: report.updatedRecordConflicts.map { conflict in
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: conflict.sourceEntityName,
          publicID: conflict.publicID,
          localModifiedAt: conflict.localModifiedAt,
          sharedModifiedAt: conflict.sharedModifiedAt,
          fieldChanges: conflict.fieldChanges.map { fieldChange in
            HerdSharingUpdatedRecordFieldChange(
              fieldName: fieldChange.fieldName,
              localValue: HerdSharingConflictStoredValue(
                type: HerdSharingConflictStoredValue.ValueType(
                  rawValue: fieldChange.localValue.type.rawValue
                ) ?? .string,
                encodedValue: fieldChange.localValue.encodedValue
              ),
              sharedValue: HerdSharingConflictStoredValue(
                type: HerdSharingConflictStoredValue.ValueType(
                  rawValue: fieldChange.sharedValue.type.rawValue
                ) ?? .string,
                encodedValue: fieldChange.sharedValue.encodedValue
              )
            )
          }
        )
      },
      preventedDeleteConflicts: report.preventedDeleteConflicts.map { conflict in
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: conflict.sourceEntityName,
          publicID: conflict.publicID,
          localModifiedAt: conflict.localModifiedAt,
          sharedDeletedAt: conflict.sharedModifiedAt
        )
      }
    )
  }

  private func fetchSwiftDataTagColorDefinitions(for herd: HerdSummary) throws
    -> [TagColorDefinition]
  {
    let herdID = herd.publicID
    return try PerformanceLog.measure("CoreDataHerdSharingRepository.fetchTagColorDefinitions") {
      let descriptor = FetchDescriptor<TagColorDefinition>(
        predicate: #Predicate<TagColorDefinition> { definition in
          definition.herd?.publicID == herdID
        }
      )
      return try context.fetch(descriptor)
    }
  }

  private func fetchSwiftDataStatusReferences(for herd: HerdSummary) throws
    -> [AnimalStatusReference]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<AnimalStatusReference>(
      predicate: #Predicate<AnimalStatusReference> { statusReference in
        statusReference.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataPastureGroups(for herd: HerdSummary) throws -> [PastureGroup] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<PastureGroup>(
      predicate: #Predicate<PastureGroup> { pastureGroup in
        pastureGroup.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataPastures(for herd: HerdSummary) throws -> [Pasture] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<Pasture>(
      predicate: #Predicate<Pasture> { pasture in
        pasture.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataAnimals(for herd: HerdSummary) throws -> [Animal] {
    let herdID = herd.publicID
    return try PerformanceLog.measure("CoreDataHerdSharingRepository.fetchAnimals") {
      let descriptor = FetchDescriptor<Animal>(
        predicate: #Predicate<Animal> { animal in
          animal.herd?.publicID == herdID
        }
      )
      return try context.fetch(descriptor)
    }
  }

  private func fetchSwiftDataAnimalTags(for herd: HerdSummary) throws -> [AnimalTag] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<AnimalTag>(
      predicate: #Predicate<AnimalTag> { tag in
        tag.herd?.publicID == herdID || tag.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataMovements(for herd: HerdSummary) throws -> [MovementRecord] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<MovementRecord>(
      predicate: #Predicate<MovementRecord> { movement in
        movement.herd?.publicID == herdID || movement.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataStatusRecords(for herd: HerdSummary) throws -> [StatusRecord] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<StatusRecord>(
      predicate: #Predicate<StatusRecord> { statusRecord in
        statusRecord.herd?.publicID == herdID || statusRecord.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataHealthRecords(for herd: HerdSummary) throws -> [HealthRecord] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<HealthRecord>(
      predicate: #Predicate<HealthRecord> { healthRecord in
        healthRecord.herd?.publicID == herdID || healthRecord.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataPregnancyChecks(for herd: HerdSummary) throws -> [PregnancyCheck] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<PregnancyCheck>(
      predicate: #Predicate<PregnancyCheck> { pregnancyCheck in
        pregnancyCheck.herd?.publicID == herdID || pregnancyCheck.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataWorkingProtocolTemplates(for herd: HerdSummary) throws
    -> [WorkingProtocolTemplate]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<WorkingProtocolTemplate>(
      predicate: #Predicate<WorkingProtocolTemplate> { template in
        template.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataWorkingSessions(for herd: HerdSummary) throws -> [WorkingSession] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<WorkingSession>(
      predicate: #Predicate<WorkingSession> { session in
        session.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataWorkingQueueItems(for herd: HerdSummary) throws -> [WorkingQueueItem] {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<WorkingQueueItem>(
      predicate: #Predicate<WorkingQueueItem> { queueItem in
        queueItem.herd?.publicID == herdID
          || queueItem.session?.herd?.publicID == herdID
          || queueItem.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataWorkingTreatmentRecords(for herd: HerdSummary) throws
    -> [WorkingTreatmentRecord]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<WorkingTreatmentRecord>(
      predicate: #Predicate<WorkingTreatmentRecord> { treatmentRecord in
        treatmentRecord.herd?.publicID == herdID
          || treatmentRecord.session?.herd?.publicID == herdID
          || treatmentRecord.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataFieldCheckSessions(for herd: HerdSummary) throws -> [FieldCheckSession]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<FieldCheckSession>(
      predicate: #Predicate<FieldCheckSession> { session in
        session.herd?.publicID == herdID || session.pasture?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataFieldCheckAnimalChecks(for herd: HerdSummary) throws
    -> [FieldCheckAnimalCheck]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<FieldCheckAnimalCheck>(
      predicate: #Predicate<FieldCheckAnimalCheck> { check in
        check.herd?.publicID == herdID
          || check.session?.herd?.publicID == herdID
          || check.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }

  private func fetchSwiftDataFieldCheckFindings(for herd: HerdSummary) throws -> [FieldCheckFinding]
  {
    let herdID = herd.publicID
    let descriptor = FetchDescriptor<FieldCheckFinding>(
      predicate: #Predicate<FieldCheckFinding> { finding in
        finding.herd?.publicID == herdID
          || finding.session?.herd?.publicID == herdID
          || finding.animal?.herd?.publicID == herdID
      }
    )
    return try context.fetch(descriptor)
  }


}
