//
//  HerdSharingCoreDataStore+Export.swift
//  yaHerd
//

import CoreData
import Foundation

extension HerdSharingCoreDataStore {
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
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("HerdSharingCoreDataStore.syncBridgeRecordsFromSwiftData.started")
    defer {
      PerformanceLog.logDuration(
        "HerdSharingCoreDataStore.syncBridgeRecordsFromSwiftData",
        startedAt: profilingStartedAt
      )
      ReliabilityLog.syncEvent("HerdSharingCoreDataStore.syncBridgeRecordsFromSwiftData.finished")
    }
    try await loadIfNeeded()

    let localPublicIDs: [HerdSharingBridgeStep: [UUID]] = [
      .herd: [herd.publicID],
      .tagColorDefinitions: tagColorDefinitions.map(\.id),
      .statusReferences: statusReferences.map(\.id),
      .pastureGroups: pastureGroups.map(\.publicID),
      .pastures: pastures.map(\.publicID),
      .animals: animals.map(\.publicID),
      .animalTags: animalTags.map(\.publicID),
      .movements: movements.map(\.publicID),
      .statusRecords: statusRecords.map(\.publicID),
      .workingProtocolTemplates: workingProtocolTemplates.map(\.publicID),
      .workingSessions: workingSessions.map(\.publicID),
      .workingQueueItems: workingQueueItems.map(\.publicID),
      .workingTreatmentRecords: workingTreatmentRecords.map(\.publicID),
      .healthRecords: healthRecords.map(\.publicID),
      .pregnancyChecks: pregnancyChecks.map(\.publicID),
      .fieldCheckSessions: fieldCheckSessions.map(\.publicID),
      .fieldCheckAnimalChecks: fieldCheckAnimalChecks.map(\.publicID),
      .fieldCheckFindings: fieldCheckFindings.map(\.publicID),
    ]
    let duplicateLocalPublicIDs = HerdSharingBridgeReconciler.duplicatePublicIDs(
      in: localPublicIDs
    )
    guard duplicateLocalPublicIDs.isEmpty else {
      let details =
        duplicateLocalPublicIDs
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { step, publicIDs in
          "\(step.displayName): \(publicIDs.map(\.uuidString).joined(separator: ", "))"
        }
        .joined(separator: "; ")
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Duplicate application-managed public IDs must be repaired before export. \(details)"
      )
    }

    let target = try writableBridgeStore(for: herd)
    let operation = try operationCoordinator.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: target.description
    )
    let context = persistentContainer.viewContext
    if context.hasChanges {
      try PersistenceLog.save(
        context,
        operation: "HerdSharingCoreDataStore.preExportPendingChanges"
      )
    }

    let originalPrivateStore = privateStore
    privateStore = target.store
    isDeferringBridgeContextSaves = true
    defer {
      isDeferringBridgeContextSaves = false
      privateStore = originalPrivateStore
    }

    do {
      let record = try await operationCoordinator.execute(
        .herd,
        operationID: operation.id
      ) {
        try await mirrorHerdIntoPrivateStore(herd)
      }
      let sharedTagColorDefinitions = try operationCoordinator.execute(
        .tagColorDefinitions,
        operationID: operation.id
      ) {
        try mirrorTagColorDefinitionsIntoPrivateStore(
          tagColorDefinitions,
          herd: herd,
          herdRecord: record
        )
      }
      let sharedStatusReferences = try operationCoordinator.execute(
        .statusReferences,
        operationID: operation.id
      ) {
        try mirrorStatusReferencesIntoPrivateStore(
          statusReferences,
          herd: herd,
          herdRecord: record
        )
      }
      let pastureGroupRecords = try operationCoordinator.execute(
        .pastureGroups,
        operationID: operation.id
      ) {
        try mirrorPastureGroupsIntoPrivateStore(
          pastureGroups,
          herd: herd,
          herdRecord: record
        )
      }
      let pastureRecords = try operationCoordinator.execute(
        .pastures,
        operationID: operation.id
      ) {
        try mirrorPasturesIntoPrivateStore(
          pastures,
          herd: herd,
          herdRecord: record,
          pastureGroupRecords: pastureGroupRecords
        )
      }
      let animalRecords = try operationCoordinator.execute(
        .animals,
        operationID: operation.id
      ) {
        try mirrorAnimalsIntoPrivateStore(animals, herd: herd, herdRecord: record)
      }
      let sharedAnimalTags = try operationCoordinator.execute(
        .animalTags,
        operationID: operation.id
      ) {
        try mirrorAnimalTagsIntoPrivateStore(
          animalTags,
          herd: herd,
          herdRecord: record,
          animalRecords: animalRecords
        )
      }
      let movementRecords = try operationCoordinator.execute(
        .movements,
        operationID: operation.id
      ) {
        try mirrorMovementsIntoPrivateStore(
          movements,
          herd: herd,
          herdRecord: record,
          animalRecords: animalRecords
        )
      }
      let sharedStatusRecords = try operationCoordinator.execute(
        .statusRecords,
        operationID: operation.id
      ) {
        try mirrorStatusRecordsIntoPrivateStore(
          statusRecords,
          herd: herd,
          herdRecord: record,
          animalRecords: animalRecords
        )
      }
      let sharedWorkingProtocolTemplates = try operationCoordinator.execute(
        .workingProtocolTemplates,
        operationID: operation.id
      ) {
        try mirrorWorkingProtocolTemplatesIntoPrivateStore(
          workingProtocolTemplates,
          herd: herd,
          herdRecord: record
        )
      }
      let sharedWorkingSessions = try operationCoordinator.execute(
        .workingSessions,
        operationID: operation.id
      ) {
        try mirrorWorkingSessionsIntoPrivateStore(
          workingSessions,
          herd: herd,
          herdRecord: record
        )
      }
      let sharedWorkingQueueItems = try operationCoordinator.execute(
        .workingQueueItems,
        operationID: operation.id
      ) {
        try mirrorWorkingQueueItemsIntoPrivateStore(
          workingQueueItems,
          herd: herd,
          herdRecord: record,
          sessionRecords: sharedWorkingSessions,
          animalRecords: animalRecords
        )
      }
      let sharedWorkingTreatmentRecords = try operationCoordinator.execute(
        .workingTreatmentRecords,
        operationID: operation.id
      ) {
        try mirrorWorkingTreatmentRecordsIntoPrivateStore(
          workingTreatmentRecords,
          herd: herd,
          herdRecord: record,
          sessionRecords: sharedWorkingSessions,
          animalRecords: animalRecords
        )
      }
      let sharedHealthRecords = try operationCoordinator.execute(
        .healthRecords,
        operationID: operation.id
      ) {
        try mirrorHealthRecordsIntoPrivateStore(
          healthRecords,
          herd: herd,
          herdRecord: record,
          animalRecords: animalRecords
        )
      }
      let sharedPregnancyChecks = try operationCoordinator.execute(
        .pregnancyChecks,
        operationID: operation.id
      ) {
        try mirrorPregnancyChecksIntoPrivateStore(
          pregnancyChecks,
          herd: herd,
          herdRecord: record,
          animalRecords: animalRecords
        )
      }
      let sharedFieldCheckSessions = try operationCoordinator.execute(
        .fieldCheckSessions,
        operationID: operation.id
      ) {
        try mirrorFieldCheckSessionsIntoPrivateStore(
          fieldCheckSessions,
          herd: herd,
          herdRecord: record
        )
      }
      let sharedFieldCheckAnimalChecks = try operationCoordinator.execute(
        .fieldCheckAnimalChecks,
        operationID: operation.id
      ) {
        try mirrorFieldCheckAnimalChecksIntoPrivateStore(
          fieldCheckAnimalChecks,
          herd: herd,
          herdRecord: record,
          sessionRecords: sharedFieldCheckSessions,
          animalRecords: animalRecords
        )
      }
      let sharedFieldCheckFindings = try operationCoordinator.execute(
        .fieldCheckFindings,
        operationID: operation.id
      ) {
        try mirrorFieldCheckFindingsIntoPrivateStore(
          fieldCheckFindings,
          herd: herd,
          herdRecord: record,
          sessionRecords: sharedFieldCheckSessions,
          animalRecords: animalRecords
        )
      }
      let sharedDeletedRecords = try operationCoordinator.execute(
        .deletions,
        operationID: operation.id
      ) {
        try fetchSharedDeletedRecords(
          herdPublicID: herd.publicID,
          in: target.store
        )
      }

      try operationCoordinator.execute(
        .persistentStoreCommit,
        operationID: operation.id
      ) {
        if context.hasChanges {
          try PersistenceLog.save(
            context,
            operation: "HerdSharingCoreDataStore.atomicBridgeExport"
          )
        }
      }

      let reconciliationReport = try operationCoordinator.execute(
        .reconciliation,
        operationID: operation.id
      ) {
        HerdSharingBridgeReconciler.makeReport(
          localPublicIDs: localPublicIDs,
          bridgePublicIDs: [
            .herd: try fetchSharedHerdRecords(
              publicID: herd.publicID,
              in: target.store
            ).compactMap(\.parsedPublicID),
            .tagColorDefinitions: sharedTagColorDefinitions.compactMap(\.parsedPublicID),
            .statusReferences: sharedStatusReferences.compactMap(\.parsedPublicID),
            .pastureGroups: pastureGroupRecords.compactMap(\.parsedPublicID),
            .pastures: pastureRecords.compactMap(\.parsedPublicID),
            .animals: animalRecords.compactMap(\.parsedPublicID),
            .animalTags: sharedAnimalTags.compactMap(\.parsedPublicID),
            .movements: movementRecords.compactMap(\.parsedPublicID),
            .statusRecords: sharedStatusRecords.compactMap(\.parsedPublicID),
            .workingProtocolTemplates: sharedWorkingProtocolTemplates.compactMap(\.parsedPublicID),
            .workingSessions: sharedWorkingSessions.compactMap(\.parsedPublicID),
            .workingQueueItems: sharedWorkingQueueItems.compactMap(\.parsedPublicID),
            .workingTreatmentRecords: sharedWorkingTreatmentRecords.compactMap(\.parsedPublicID),
            .healthRecords: sharedHealthRecords.compactMap(\.parsedPublicID),
            .pregnancyChecks: sharedPregnancyChecks.compactMap(\.parsedPublicID),
            .fieldCheckSessions: sharedFieldCheckSessions.compactMap(\.parsedPublicID),
            .fieldCheckAnimalChecks: sharedFieldCheckAnimalChecks.compactMap(\.parsedPublicID),
            .fieldCheckFindings: sharedFieldCheckFindings.compactMap(\.parsedPublicID),
          ],
          deletionTombstoneCount: sharedDeletedRecords.count
        )
      }

      let recordsToShare: [NSManagedObject] =
        [record as NSManagedObject] + sharedTagColorDefinitions.map { $0 as NSManagedObject }
        + sharedStatusReferences.map { $0 as NSManagedObject }
        + pastureGroupRecords.map { $0 as NSManagedObject }
        + pastureRecords.map { $0 as NSManagedObject }
        + animalRecords.map { $0 as NSManagedObject }
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
        _ = try await operationCoordinator.execute(
          .cloudKitShareUpdate,
          operationID: operation.id
        ) {
          try await shareRecords(recordsToShare, title: herd.name)
        }
        didUpdateExistingCloudKitShare = true
      }

      let result = HerdSharingBridgeExportResult(
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
        exportedDeletedRecordCount: sharedDeletedRecords.count,
        reconciliationReport: reconciliationReport
      )
      try operationCoordinator.complete(
        operationID: operation.id,
        recordCounts: [
          "exportedRecords": result.exportedRecordCount,
          "deletionTombstones": result.exportedDeletedRecordCount,
        ],
        reconciliationSummary: reconciliationReport.summary
      )
      return result
    } catch {
      context.rollback()
      operationCoordinator.fail(operationID: operation.id, error: error)
      throw error
    }
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
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("HerdSharingCoreDataStore.makeSystemShare.started")
    defer {
      PerformanceLog.logDuration(
        "HerdSharingCoreDataStore.makeSystemShare",
        startedAt: profilingStartedAt
      )
      ReliabilityLog.syncEvent("HerdSharingCoreDataStore.makeSystemShare.finished")
    }

    _ = try await syncBridgeRecordsFromSwiftData(
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

    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded."
      )
    }
    guard let record = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore) else {
      throw HerdSharingActionError.shareRootMissing
    }

    let recordsToShare: [NSManagedObject] =
      [record as NSManagedObject]
      + (try fetchSharedTagColorDefinitionRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedAnimalStatusReferenceRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedPastureGroupRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedPastureRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedAnimalRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedAnimalTagRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedMovementRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedStatusRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedWorkingProtocolTemplateRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedWorkingSessionRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedWorkingQueueItemRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedWorkingTreatmentRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedHealthRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedPregnancyCheckRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedFieldCheckSessionRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedFieldCheckAnimalCheckRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedFieldCheckFindingRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
      + (try fetchSharedDeletedRecords(
        herdPublicID: herd.publicID,
        in: privateStore
      )).map { $0 as NSManagedObject }
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
}
