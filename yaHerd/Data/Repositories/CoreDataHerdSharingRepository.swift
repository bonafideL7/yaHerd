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

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
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
              localValueDescription: fieldChange.localValueDescription,
              sharedValueDescription: fieldChange.sharedValueDescription
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
    let descriptor = FetchDescriptor<TagColorDefinition>()
    return try context.fetch(descriptor).filter { definition in
      definition.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataStatusReferences(for herd: HerdSummary) throws
    -> [AnimalStatusReference]
  {
    let descriptor = FetchDescriptor<AnimalStatusReference>()
    return try context.fetch(descriptor).filter { statusReference in
      statusReference.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataPastureGroups(for herd: HerdSummary) throws -> [PastureGroup] {
    let descriptor = FetchDescriptor<PastureGroup>()
    return try context.fetch(descriptor).filter { pastureGroup in
      pastureGroup.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataPastures(for herd: HerdSummary) throws -> [Pasture] {
    let descriptor = FetchDescriptor<Pasture>()
    return try context.fetch(descriptor).filter { pasture in
      pasture.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataAnimals(for herd: HerdSummary) throws -> [Animal] {
    let descriptor = FetchDescriptor<Animal>()
    return try context.fetch(descriptor).filter { animal in
      animal.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataAnimalTags(for herd: HerdSummary) throws -> [AnimalTag] {
    let descriptor = FetchDescriptor<AnimalTag>()
    return try context.fetch(descriptor).filter { tag in
      tag.herd?.publicID == herd.publicID || tag.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataMovements(for herd: HerdSummary) throws -> [MovementRecord] {
    let descriptor = FetchDescriptor<MovementRecord>()
    return try context.fetch(descriptor).filter { movement in
      movement.herd?.publicID == herd.publicID || movement.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataStatusRecords(for herd: HerdSummary) throws -> [StatusRecord] {
    let descriptor = FetchDescriptor<StatusRecord>()
    return try context.fetch(descriptor).filter { statusRecord in
      statusRecord.herd?.publicID == herd.publicID
        || statusRecord.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataHealthRecords(for herd: HerdSummary) throws -> [HealthRecord] {
    let descriptor = FetchDescriptor<HealthRecord>()
    return try context.fetch(descriptor).filter { healthRecord in
      healthRecord.herd?.publicID == herd.publicID
        || healthRecord.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataPregnancyChecks(for herd: HerdSummary) throws -> [PregnancyCheck] {
    let descriptor = FetchDescriptor<PregnancyCheck>()
    return try context.fetch(descriptor).filter { pregnancyCheck in
      pregnancyCheck.herd?.publicID == herd.publicID
        || pregnancyCheck.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataWorkingProtocolTemplates(for herd: HerdSummary) throws
    -> [WorkingProtocolTemplate]
  {
    let descriptor = FetchDescriptor<WorkingProtocolTemplate>()
    return try context.fetch(descriptor).filter { template in
      template.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataWorkingSessions(for herd: HerdSummary) throws -> [WorkingSession] {
    let descriptor = FetchDescriptor<WorkingSession>()
    return try context.fetch(descriptor).filter { session in
      session.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataWorkingQueueItems(for herd: HerdSummary) throws -> [WorkingQueueItem] {
    let descriptor = FetchDescriptor<WorkingQueueItem>()
    return try context.fetch(descriptor).filter { queueItem in
      queueItem.herd?.publicID == herd.publicID
        || queueItem.session?.herd?.publicID == herd.publicID
        || queueItem.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataWorkingTreatmentRecords(for herd: HerdSummary) throws
    -> [WorkingTreatmentRecord]
  {
    let descriptor = FetchDescriptor<WorkingTreatmentRecord>()
    return try context.fetch(descriptor).filter { treatmentRecord in
      treatmentRecord.herd?.publicID == herd.publicID
        || treatmentRecord.session?.herd?.publicID == herd.publicID
        || treatmentRecord.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataFieldCheckSessions(for herd: HerdSummary) throws -> [FieldCheckSession]
  {
    let descriptor = FetchDescriptor<FieldCheckSession>()
    return try context.fetch(descriptor).filter { session in
      session.herd?.publicID == herd.publicID || session.pasture?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataFieldCheckAnimalChecks(for herd: HerdSummary) throws
    -> [FieldCheckAnimalCheck]
  {
    let descriptor = FetchDescriptor<FieldCheckAnimalCheck>()
    return try context.fetch(descriptor).filter { check in
      check.herd?.publicID == herd.publicID || check.session?.herd?.publicID == herd.publicID
        || check.animal?.herd?.publicID == herd.publicID
    }
  }

  private func fetchSwiftDataFieldCheckFindings(for herd: HerdSummary) throws -> [FieldCheckFinding]
  {
    let descriptor = FetchDescriptor<FieldCheckFinding>()
    return try context.fetch(descriptor).filter { finding in
      finding.herd?.publicID == herd.publicID || finding.session?.herd?.publicID == herd.publicID
        || finding.animal?.herd?.publicID == herd.publicID
    }
  }

}
