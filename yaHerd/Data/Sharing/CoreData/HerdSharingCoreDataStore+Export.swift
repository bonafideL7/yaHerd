//
//  HerdSharingCoreDataStore+Export.swift
//  yaHerd
//

import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func syncBridgeRecordsFromSnapshot(
    _ export: HerdSharingSwiftDataExport
  ) async throws -> HerdSharingBridgeExportResult {
    try await loadIfNeeded()
    let herd = export.herd
    let preparedTarget = try await writableBridgeStore(for: herd)
    let operation = try await operationCoordinator.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: preparedTarget.description
    )

    do {
      let target = try await writableBridgeStore(for: herd)
      guard target.store === preparedTarget.store,
            target.description == preparedTarget.description
      else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The writable sharing bridge changed while export was being prepared. No bridge records were written."
        )
      }
      let targetSnapshot = HerdSharingBridgeStoreSnapshot(
        herdPublicID: export.snapshot.herdPublicID,
        storeDescription: target.description,
        recordsByStep: export.snapshot.recordsByStep
      )
      let writeResult = try await writeBridgeSnapshot(
        targetSnapshot,
        to: target.store,
        failureInjector: operationCoordinator.backgroundFailureInjector
      )
      try await operationCoordinator.recordCompletedSteps(
        HerdSharingBridgeStep.entitySteps + [.persistentStoreCommit],
        operationID: operation.id
      )

      let reconciliationReport = try await operationCoordinator.execute(
        .reconciliation,
        operationID: operation.id
      ) {
        HerdSharingBridgeReconciler.makeReport(
          localPublicIDs: export.localPublicIDs,
          bridgePublicIDs: writeResult.snapshot.publicIDsByStep,
          deletionTombstoneCount: writeResult.snapshot.deletionTombstoneCount
        )
      }

      let recordsToShare = try managedObjects(for: writeResult.managedObjectURIs)
      guard let herdRecord = recordsToShare.first(where: {
        $0.entity.name == SharedHerdRecord.entityName
          && ($0.value(forKey: "publicID") as? String) == herd.publicID.uuidString
      }) else {
        throw HerdSharingActionError.shareRootMissing
      }

      var didUpdateExistingCloudKitShare = false
      if target.shouldUpdateShare, try existingShare(for: herdRecord) != nil {
        _ = try await operationCoordinator.execute(
          .cloudKitShareUpdate,
          operationID: operation.id
        ) {
          try await shareRecords(recordsToShare, title: herd.name)
        }
        didUpdateExistingCloudKitShare = true
      }

      let finalSnapshot = writeResult.snapshot
      let result = HerdSharingBridgeExportResult(
        herdName: herd.name,
        writeTargetDescription: target.description,
        didUpdateExistingCloudKitShare: didUpdateExistingCloudKitShare,
        exportedTagColorDefinitionCount: finalSnapshot.records(for: .tagColorDefinitions).count,
        exportedStatusReferenceCount: finalSnapshot.records(for: .statusReferences).count,
        exportedAnimalTagCount: finalSnapshot.records(for: .animalTags).count,
        exportedPastureGroupCount: finalSnapshot.records(for: .pastureGroups).count,
        exportedPastureCount: finalSnapshot.records(for: .pastures).count,
        exportedAnimalCount: finalSnapshot.records(for: .animals).count,
        exportedMovementCount: finalSnapshot.records(for: .movements).count,
        exportedStatusRecordCount: finalSnapshot.records(for: .statusRecords).count,
        exportedHealthRecordCount: finalSnapshot.records(for: .healthRecords).count,
        exportedPregnancyCheckCount: finalSnapshot.records(for: .pregnancyChecks).count,
        exportedWorkingProtocolTemplateCount: finalSnapshot.records(for: .workingProtocolTemplates).count,
        exportedWorkingSessionCount: finalSnapshot.records(for: .workingSessions).count,
        exportedWorkingQueueItemCount: finalSnapshot.records(for: .workingQueueItems).count,
        exportedWorkingTreatmentRecordCount: finalSnapshot.records(for: .workingTreatmentRecords).count,
        exportedFieldCheckSessionCount: finalSnapshot.records(for: .fieldCheckSessions).count,
        exportedFieldCheckAnimalCheckCount: finalSnapshot.records(for: .fieldCheckAnimalChecks).count,
        exportedFieldCheckFindingCount: finalSnapshot.records(for: .fieldCheckFindings).count,
        exportedDeletedRecordCount: finalSnapshot.records(for: .deletions).count,
        reconciliationReport: reconciliationReport
      )
      try await operationCoordinator.complete(
        operationID: operation.id,
        recordCounts: [
          "exportedRecords": result.exportedRecordCount,
          "deletionTombstones": result.exportedDeletedRecordCount,
        ],
        reconciliationSummary: reconciliationReport.summary
      )
      return result
    } catch {
      await operationCoordinator.fail(operationID: operation.id, error: error)
      throw error
    }
  }

  func makeSystemShare(
    from export: HerdSharingSwiftDataExport
  ) async throws -> CloudKitSystemShare {
    _ = try await syncBridgeRecordsFromSnapshot(export)
    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded."
      )
    }
    let bridgeSnapshot = try await readBridgeSnapshot(
      from: privateStore,
      requestedHerdPublicID: export.herd.publicID,
      storeDescription: "owner private store"
    )
    let recordsToShare = try managedObjects(
      for: HerdSharingBridgeStep.entitySteps.flatMap { step in
        bridgeSnapshot.records(for: step).map(\.sourceObjectURI)
      }
    )
    let share = try await shareRecords(recordsToShare, title: export.herd.name)

    return CloudKitSystemShare(
      title: export.herd.name,
      share: share,
      container: cloudKitContainer,
      persistUpdatedShareHandler: { [weak self] share in
        await self?.persistUpdatedShare(share)
      },
      stopSharingHandler: { [weak self] share in
        try await self?.purgeStoppedShare(share)
      }
    )
  }

  private func managedObjects(for objectURIs: [String]) throws -> [NSManagedObject] {
    let coordinator = persistentContainer.persistentStoreCoordinator
    let context = persistentContainer.viewContext
    return try objectURIs.compactMap { rawURI in
      guard let url = URL(string: rawURI),
        let objectID = coordinator.managedObjectID(forURIRepresentation: url)
      else { return nil }
      return try context.existingObject(with: objectID)
    }
  }
}
