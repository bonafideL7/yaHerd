//
//  HerdSharingCoreDataStore+Import.swift
//  yaHerd
//

@preconcurrency import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func importSharedRecordsIntoSwiftData(
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    try await performBridgeImport(
      for: nil,
      access: nil,
      importer: importer
    )
  }

  func importBridgeRecordsIntoSwiftData(
    for herd: HerdSummary,
    access: HerdSharingAccess,
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    try await performBridgeImport(
      for: herd,
      access: access,
      importer: importer
    )
  }

  private func performBridgeImport(
    for requestedHerd: HerdSummary?,
    access: HerdSharingAccess?,
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("HerdSharingCoreDataStore.importSharedRecordsIntoSwiftData.started")
    defer {
      PerformanceLog.logDuration(
        "HerdSharingCoreDataStore.importSharedRecordsIntoSwiftData",
        startedAt: profilingStartedAt
      )
      ReliabilityLog.syncEvent("HerdSharingCoreDataStore.importSharedRecordsIntoSwiftData.finished")
    }

    try await loadIfNeeded()
    let source = try bridgeImportSource(for: requestedHerd, access: access)
    let snapshot: HerdSharingBridgeStoreSnapshot
    do {
      snapshot = try await readBridgeSnapshot(
        from: source.store,
        requestedHerdPublicID: requestedHerd?.publicID,
        storeDescription: source.description
      )
    } catch {
      throw Self.importBoundaryError(
        error,
        requestedHerd: requestedHerd,
        sourceDescription: source.description
      )
    }

    if let revisionHydrator = importer as? any CollaborationRevisionHydrating {
      try await revisionHydrator.hydrateCollaborationRevisions(
        for: snapshot.herdPublicID
      )
    }

    let operation = try await operationCoordinator.begin(
      herdPublicID: snapshot.herdPublicID,
      direction: .importFromBridge,
      bridgeLocation: source.description
    )

    do {
      let application = try await importer.applyImport(
        snapshot,
        pendingConflictReport: operation.pendingConflictReport,
        failureInjector: operationCoordinator.backgroundFailureInjector
      )
      await operationCoordinator.recordCommittedImportSuccess(
        completedSteps: application.completedSteps,
        conflictReport: application.result.conflictReport,
        operationID: operation.id,
        recordCounts: [
          "insertedRecords": totalInsertedRecordCount(in: application.result),
          "updatedRecords": totalUpdatedRecordCount(in: application.result),
          "deletedRecords": application.result.deletedRecordCount,
        ],
        reconciliationSummary: application.result.reconciliationSummary
      )
      return application.result
    } catch let committedFailure as HerdSharingSwiftDataCommittedImportFailure {
      await operationCoordinator.recordCommittedImportFailure(
        committedFailure,
        operationID: operation.id
      )
      throw committedFailure.underlyingError
    } catch {
      await operationCoordinator.fail(operationID: operation.id, error: error)
      throw error
    }
  }

  nonisolated static func importBoundaryError(
    _ error: Error,
    requestedHerd: HerdSummary?,
    sourceDescription: String
  ) -> Error {
    guard let snapshotError = error as? HerdSharingBridgeSnapshotError else {
      return error
    }
    guard case .missingHerdRecord = snapshotError else {
      return error
    }

    if let requestedHerd {
      return HerdSharingActionError.bridgeImportFailed(
        "No bridge herd record for \(requestedHerd.name) was found in the \(sourceDescription)."
      )
    }
    return HerdSharingActionError.bridgeImportFailed(
      "No accepted shared herd records were found in the Core Data sharing bridge."
    )
  }

  private func totalInsertedRecordCount(in result: HerdSharingBridgeImportResult) -> Int {
    result.insertedTagColorDefinitionCount
      + result.insertedStatusReferenceCount
      + result.insertedAnimalTagCount
      + result.insertedPastureGroupCount
      + result.insertedPastureCount
      + result.insertedAnimalCount
      + result.insertedMovementCount
      + result.insertedStatusRecordCount
      + result.insertedHealthRecordCount
      + result.insertedPregnancyCheckCount
      + result.insertedWorkingProtocolTemplateCount
      + result.insertedWorkingSessionCount
      + result.insertedWorkingQueueItemCount
      + result.insertedWorkingTreatmentRecordCount
      + result.insertedFieldCheckSessionCount
      + result.insertedFieldCheckAnimalCheckCount
      + result.insertedFieldCheckFindingCount
  }

  private func totalUpdatedRecordCount(in result: HerdSharingBridgeImportResult) -> Int {
    result.updatedTagColorDefinitionCount
      + result.updatedStatusReferenceCount
      + result.updatedAnimalTagCount
      + result.updatedPastureGroupCount
      + result.updatedPastureCount
      + result.updatedAnimalCount
      + result.updatedMovementCount
      + result.updatedStatusRecordCount
      + result.updatedHealthRecordCount
      + result.updatedPregnancyCheckCount
      + result.updatedWorkingProtocolTemplateCount
      + result.updatedWorkingSessionCount
      + result.updatedWorkingQueueItemCount
      + result.updatedWorkingTreatmentRecordCount
      + result.updatedFieldCheckSessionCount
      + result.updatedFieldCheckAnimalCheckCount
      + result.updatedFieldCheckFindingCount
  }

  private func bridgeImportSource(
    for herd: HerdSummary?,
    access: HerdSharingAccess?
  ) throws -> (store: NSPersistentStore, description: String) {
    guard let herd, let access else {
      guard let sharedStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The shared CloudKit bridge store was not loaded."
        )
      }
      return (sharedStore, "accepted shared store")
    }

    switch access.bridgeLocation {
    case .ownerPrivateStore:
      guard let privateStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The private sharing bridge store was not loaded."
        )
      }
      return (privateStore, "owner private store")
    case .acceptedSharedStore:
      guard let sharedStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The shared CloudKit bridge store was not loaded."
        )
      }
      return (sharedStore, "accepted shared store")
    case .bridgeRecordMissing:
      throw HerdSharingActionError.bridgeImportFailed(
        "No bridge record exists for \(herd.name)."
      )
    }
  }
}
