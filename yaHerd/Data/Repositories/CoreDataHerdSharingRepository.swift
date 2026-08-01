//
//  CoreDataHerdSharingRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
protocol HerdSharingBridgeSyncStore: AnyObject {
  func fetchSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess

  func importBridgeRecordsIntoSwiftData(
    for herd: HerdSummary,
    access: HerdSharingAccess,
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult

  func syncBridgeRecordsFromSnapshot(
    _ export: HerdSharingSwiftDataExport
  ) async throws -> HerdSharingBridgeExportResult

}

extension HerdSharingCoreDataStore: HerdSharingBridgeSyncStore {}

@MainActor
final class CoreDataHerdSharingRepository: HerdSharingRepository {
  private let context: ModelContext
  private let store: HerdSharingCoreDataStore
  private let syncStore: any HerdSharingBridgeSyncStore
  private let exportReader: any HerdSharingExportSnapshotReading
  private let swiftDataMutator: any HerdSharingSwiftDataMutating
  private let swiftDataImporter: any HerdSharingImportApplying
  private let shareAdapter: CloudKitShareAdapter
  private let operationGate = HerdSharingBridgeOperationGate()

  init(
    context: ModelContext,
    store: HerdSharingCoreDataStore? = nil,
    syncStore: (any HerdSharingBridgeSyncStore)? = nil,
    exportReader: (any HerdSharingExportSnapshotReading)? = nil,
    swiftDataMutator: (any HerdSharingSwiftDataMutating)? = nil,
    swiftDataImporter: (any HerdSharingImportApplying)? = nil,
    shareAdapter: CloudKitShareAdapter? = nil
  ) {
    self.context = context
    let resolvedStore = store ?? HerdSharingCoreDataStore()
    self.store = resolvedStore
    if let syncStore {
      self.syncStore = syncStore
    } else {
      self.syncStore = resolvedStore
    }
    let resolvedSwiftDataActor = SwiftDataHerdSharingActor(modelContainer: context.container)
    self.exportReader = exportReader ?? resolvedSwiftDataActor
    self.swiftDataMutator = swiftDataMutator ?? resolvedSwiftDataActor
    self.swiftDataImporter = swiftDataImporter ?? resolvedSwiftDataActor
    self.shareAdapter = shareAdapter ?? CloudKitShareAdapter()
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
    ReliabilityLog.syncEvent(
      "CoreDataHerdSharingRepository.startSharing.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration(
        "CoreDataHerdSharingRepository.startSharing", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.startSharing.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    await operationGate.acquire()
    defer { operationGate.release() }

    let export = try await exportReader.makeExport(
      for: herd,
      storeDescription: "owner private store"
    )
    let systemShare = try await store.makeSystemShare(from: export)
    let sharePresentation = shareAdapter.registerSystemShare(systemShare)
    let snapshot = export.snapshot
    return HerdSharingActionResult(
      title: "Share sheet ready",
      message:
        "Invite people through the system CloudKit sharing sheet. SwiftData remains the app data store; Core Data now mirrors the herd root, \(snapshot.records(for: .tagColorDefinitions).count) tag color definitions, \(snapshot.records(for: .statusReferences).count) custom status references, \(snapshot.records(for: .pastureGroups).count) pasture groups, \(snapshot.records(for: .pastures).count) pastures, \(snapshot.records(for: .animals).count) animal records, \(snapshot.records(for: .animalTags).count) animal tags, \(snapshot.records(for: .movements).count) movement records, \(snapshot.records(for: .statusRecords).count) status history records, \(snapshot.records(for: .healthRecords).count) health records, \(snapshot.records(for: .pregnancyChecks).count) pregnancy checks, \(snapshot.records(for: .workingProtocolTemplates).count) working protocol templates, \(snapshot.records(for: .workingSessions).count) working sessions, \(snapshot.records(for: .workingQueueItems).count) working queue items, \(snapshot.records(for: .workingTreatmentRecords).count) working treatment records, \(snapshot.records(for: .fieldCheckSessions).count) field check sessions, \(snapshot.records(for: .fieldCheckAnimalChecks).count) field check animal checks, and \(snapshot.records(for: .fieldCheckFindings).count) field check findings for CloudKit sharing.",
      sharePresentation: sharePresentation
    )
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent(
      "CoreDataHerdSharingRepository.acceptShareInvitation.started", detail: storageMode.displayName
    )
    defer {
      PerformanceLog.logDuration(
        "CoreDataHerdSharingRepository.acceptShareInvitation", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.acceptShareInvitation.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    await operationGate.acquire()
    defer { operationGate.release() }

    let metadata = try shareAdapter.metadata(for: invitation)
    try await store.acceptShareInvitation(metadata: metadata)
    shareAdapter.discardInvitation(invitation)

    do {
      let importResult = try await store.importSharedRecordsIntoSwiftData(importer: swiftDataImporter)
      return HerdSharingActionResult(
        title: "Invitation accepted",
        message:
          "Imported \(importResult.importedTagColorDefinitionCount) tag color definitions, \(importResult.importedStatusReferenceCount) custom status references, \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animal records, \(importResult.importedAnimalTagCount) animal tags, \(importResult.importedMovementCount) movement records, \(importResult.importedStatusRecordCount) status history records, \(importResult.importedHealthRecordCount) health records, \(importResult.importedPregnancyCheckCount) pregnancy checks, \(importResult.importedWorkingProtocolTemplateCount) working protocol templates, \(importResult.importedWorkingSessionCount) working sessions, \(importResult.importedWorkingQueueItemCount) queue items, \(importResult.importedWorkingTreatmentRecordCount) treatment records, \(importResult.importedFieldCheckSessionCount) field check sessions, \(importResult.importedFieldCheckAnimalCheckCount) field check animal checks, and \(importResult.importedFieldCheckFindingCount) field check findings from the Core Data sharing bridge into SwiftData for \(importResult.herdName). Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary) Reconciliation: \(importResult.reconciliationSummary)",
        conflictReview: makeConflictReview(
          from: importResult,
          sourceDescription: "Invitation accepted"
        ),
        reconciliationReview: makeReconciliationReview(
          from: importResult.reconciliationReport
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

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent(
      "CoreDataHerdSharingRepository.importSharedBridgeData.started",
      detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration(
        "CoreDataHerdSharingRepository.importSharedBridgeData", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.importSharedBridgeData.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    await operationGate.acquire()
    defer { operationGate.release() }

    let importResult: HerdSharingBridgeImportResult
    if let herd {
      let access = try await syncStore.fetchSharingAccess(for: herd)
      importResult = try await syncStore.importBridgeRecordsIntoSwiftData(
        for: herd,
        access: access,
        importer: swiftDataImporter
      )
    } else {
      importResult = try await store.importSharedRecordsIntoSwiftData(importer: swiftDataImporter)
    }
    return HerdSharingActionResult(
      title: "Shared data imported",
      message:
        "Imported \(importResult.insertedTagColorDefinitionCount) new/\(importResult.updatedTagColorDefinitionCount) existing tag color definitions, \(importResult.insertedStatusReferenceCount) new/\(importResult.updatedStatusReferenceCount) existing custom status references, \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedAnimalTagCount) new/\(importResult.updatedAnimalTagCount) existing animal tags, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records, \(importResult.insertedHealthRecordCount) new/\(importResult.updatedHealthRecordCount) existing health records, \(importResult.insertedPregnancyCheckCount) new/\(importResult.updatedPregnancyCheckCount) existing pregnancy checks, \(importResult.insertedWorkingProtocolTemplateCount) new/\(importResult.updatedWorkingProtocolTemplateCount) existing working protocol templates, \(importResult.insertedWorkingSessionCount) new/\(importResult.updatedWorkingSessionCount) existing working sessions, \(importResult.insertedWorkingQueueItemCount) new/\(importResult.updatedWorkingQueueItemCount) existing queue items, \(importResult.insertedWorkingTreatmentRecordCount) new/\(importResult.updatedWorkingTreatmentRecordCount) existing treatment records, \(importResult.insertedFieldCheckSessionCount) new/\(importResult.updatedFieldCheckSessionCount) existing field check sessions, \(importResult.insertedFieldCheckAnimalCheckCount) new/\(importResult.updatedFieldCheckAnimalCheckCount) existing field check animal checks, and \(importResult.insertedFieldCheckFindingCount) new/\(importResult.updatedFieldCheckFindingCount) existing field check findings from the Core Data sharing bridge into SwiftData for \(importResult.herdName). Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary) Reconciliation: \(importResult.reconciliationSummary)",
      conflictReview: makeConflictReview(
        from: importResult,
        sourceDescription: "Manual shared-data import"
      ),
      reconciliationReview: makeReconciliationReview(
        from: importResult.reconciliationReport
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

    await operationGate.acquire()
    defer { operationGate.release() }

    let deletedCount = try await swiftDataMutator.acceptPreventedSharedDeletes(
      review.preventedDeleteConflicts
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

    await operationGate.acquire()
    defer { operationGate.release() }

    let result = try await swiftDataMutator.restoreLocalFields(
      selections,
      from: review
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
    ReliabilityLog.syncEvent(
      "CoreDataHerdSharingRepository.syncSharedBridgeData.started", detail: storageMode.displayName)
    defer {
      PerformanceLog.logDuration(
        "CoreDataHerdSharingRepository.syncSharedBridgeData", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("CoreDataHerdSharingRepository.syncSharedBridgeData.finished")
    }

    guard storageMode == .iCloud else {
      throw HerdSharingActionError.iCloudSyncRequired
    }

    guard let herd else {
      throw HerdSharingActionError.shareRootMissing
    }

    await operationGate.acquire()
    defer { operationGate.release() }

    let access = try await syncStore.fetchSharingAccess(for: herd)
    guard access.canExportLocalChangesToBridge else {
      return try await importOnlySyncResult(herd: herd, access: access)
    }

    // Any existing shared bridge record must be imported before SwiftData snapshots are fetched.
    // Owner shares live in the private bridge store, while accepted shares live in the shared
    // bridge store. Exporting first can overwrite collaborator changes in either location.
    let importResult: HerdSharingBridgeImportResult?
    if access.bridgeLocation == .bridgeRecordMissing {
      importResult = nil
    } else {
      importResult = try await syncStore.importBridgeRecordsIntoSwiftData(
        for: herd,
        access: access,
        importer: swiftDataImporter
      )
    }

    let export = try await exportReader.makeExport(
      for: herd,
      storeDescription: access.locationDescription
    )
    let exportResult = try await syncStore.syncBridgeRecordsFromSnapshot(export)

    let importMessage: String
    let conflictReview: HerdSharingConflictReview?
    if let importResult {
      importMessage =
        "Imported \(importResult.insertedTagColorDefinitionCount) new/\(importResult.updatedTagColorDefinitionCount) existing tag color definitions, \(importResult.insertedStatusReferenceCount) new/\(importResult.updatedStatusReferenceCount) existing custom status references, \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedAnimalTagCount) new/\(importResult.updatedAnimalTagCount) existing animal tags, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records, \(importResult.insertedHealthRecordCount) new/\(importResult.updatedHealthRecordCount) existing health records, \(importResult.insertedPregnancyCheckCount) new/\(importResult.updatedPregnancyCheckCount) existing pregnancy checks, \(importResult.insertedWorkingProtocolTemplateCount) new/\(importResult.updatedWorkingProtocolTemplateCount) existing working protocol templates, \(importResult.insertedWorkingSessionCount) new/\(importResult.updatedWorkingSessionCount) existing working sessions, \(importResult.insertedWorkingQueueItemCount) new/\(importResult.updatedWorkingQueueItemCount) existing queue items, \(importResult.insertedWorkingTreatmentRecordCount) new/\(importResult.updatedWorkingTreatmentRecordCount) existing treatment records, \(importResult.insertedFieldCheckSessionCount) new/\(importResult.updatedFieldCheckSessionCount) existing field check sessions, \(importResult.insertedFieldCheckAnimalCheckCount) new/\(importResult.updatedFieldCheckAnimalCheckCount) existing field check animal checks, and \(importResult.insertedFieldCheckFindingCount) new/\(importResult.updatedFieldCheckFindingCount) existing field check findings from shared bridge records. Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary) Reconciliation: \(importResult.reconciliationSummary)"
      conflictReview = makeConflictReview(
        from: importResult,
        sourceDescription: "Shared-data sync"
      )
    } else {
      importMessage =
        "No existing bridge record was available to import from the \(access.locationDescription)."
      conflictReview = nil
    }

    let cloudKitMessage =
      exportResult.didUpdateExistingCloudKitShare
      ? "Existing CloudKit share membership was updated with the mirrored records."
      : "No existing owner-side CKShare needed updating; records were saved into the \(exportResult.writeTargetDescription)."

    return HerdSharingActionResult(
      title: "Shared data synced",
      message:
        "\(importMessage) Exported \(exportResult.exportedRecordCount) bridge records for \(exportResult.herdName) into the \(exportResult.writeTargetDescription). \(cloudKitMessage) Reconciliation after export: \(exportResult.reconciliationSummary)",
      conflictReview: conflictReview,
      reconciliationReview: makeReconciliationReview(
        from: exportResult.reconciliationReport
      )
    )
  }

  private func importOnlySyncResult(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingActionResult {
    do {
      let importResult = try await syncStore.importBridgeRecordsIntoSwiftData(
        for: herd,
        access: access,
        importer: swiftDataImporter
      )
      return HerdSharingActionResult(
        title: "Shared data imported",
        message:
          "Your CloudKit share access is \(access.permissionDescription) in the \(access.locationDescription), so yaHerd did not export local SwiftData changes back into the shared bridge. Imported \(importResult.importedTagColorDefinitionCount) tag color definitions, \(importResult.importedStatusReferenceCount) custom status references, \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animals, \(importResult.importedAnimalTagCount) animal tags, \(importResult.importedMovementCount) movement records, \(importResult.importedStatusRecordCount) status history records, \(importResult.importedHealthRecordCount) health records, \(importResult.importedPregnancyCheckCount) pregnancy checks, \(importResult.importedWorkingProtocolTemplateCount) working protocol templates, \(importResult.importedWorkingSessionCount) working sessions, \(importResult.importedWorkingQueueItemCount) queue items, \(importResult.importedWorkingTreatmentRecordCount) treatment records, \(importResult.importedFieldCheckSessionCount) field check sessions, \(importResult.importedFieldCheckAnimalCheckCount) field check animal checks, and \(importResult.importedFieldCheckFindingCount) field check findings from shared bridge records. Applied \(importResult.deletedRecordCount) shared deletions. Conflict report: \(importResult.conflictSummary) Reconciliation: \(importResult.reconciliationSummary)",
        conflictReview: makeConflictReview(
          from: importResult,
          sourceDescription: "Read-only shared-data import"
        ),
        reconciliationReview: makeReconciliationReview(
          from: importResult.reconciliationReport
        )
      )
    } catch HerdSharingActionError.bridgeImportFailed(_) {
      return HerdSharingActionResult(
        title: "Shared data not exported",
        message:
          "Your CloudKit share access is \(access.permissionDescription) in the \(access.locationDescription), so yaHerd did not export local SwiftData changes back into the shared bridge. No matching bridge records were available to import yet."
      )
    }
  }

  private func makeReconciliationReview(
    from report: HerdSharingBridgeReconciliationReport
  ) -> HerdSharingReconciliationReview {
    HerdSharingReconciliationReview(
      entities: report.entities.map { entity in
        HerdSharingEntityReconciliation(
          entityName: entity.step.displayName,
          localRecordCount: entity.localRecordCount,
          bridgeRecordCount: entity.bridgeRecordCount,
          missingInBridge: entity.missingInBridge,
          missingInSwiftData: entity.missingInSwiftData,
          duplicateLocalPublicIDs: entity.duplicateLocalPublicIDs,
          duplicateBridgePublicIDs: entity.duplicateBridgePublicIDs
        )
      },
      deletionTombstoneCount: report.deletionTombstoneCount
    )
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


}
