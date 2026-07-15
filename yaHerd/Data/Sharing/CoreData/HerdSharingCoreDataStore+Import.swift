//
//  HerdSharingCoreDataStore+Import.swift
//  yaHerd
//

import CoreData
import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
  func importSharedRecordsIntoSwiftData(context swiftDataContext: ModelContext) async throws
    -> HerdSharingBridgeImportResult
  {
    try await performBridgeImport(
      for: nil,
      access: nil,
      context: swiftDataContext
    )
  }

  func importBridgeRecordsIntoSwiftData(
    for herd: HerdSummary,
    access: HerdSharingAccess,
    context swiftDataContext: ModelContext
  ) async throws -> HerdSharingBridgeImportResult {
    try await performBridgeImport(
      for: herd,
      access: access,
      context: swiftDataContext
    )
  }

  private func performBridgeImport(
    for requestedHerd: HerdSummary?,
    access: HerdSharingAccess?,
    context swiftDataContext: ModelContext
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
    let herdRecord: SharedHerdRecord
    let matchingHerdRecords: [SharedHerdRecord]
    if let requestedHerd {
      matchingHerdRecords = try fetchSharedHerdRecords(
        publicID: requestedHerd.publicID,
        in: source.store
      )
      guard let matchingRecord = matchingHerdRecords.sorted(by: sharedHerdRecordSort).first else {
        throw HerdSharingActionError.bridgeImportFailed(
          "No bridge herd record for \(requestedHerd.name) was found in the \(source.description)."
        )
      }
      herdRecord = matchingRecord
    } else {
      let herdRecords = try fetchSharedHerdRecords(in: source.store)
      guard let firstRecord = herdRecords.sorted(by: sharedHerdRecordSort).first,
        let firstPublicID = firstRecord.parsedPublicID
      else {
        throw HerdSharingActionError.bridgeImportFailed(
          "No accepted shared herd records were found in the Core Data sharing bridge."
        )
      }
      herdRecord = firstRecord
      matchingHerdRecords = herdRecords.filter { $0.parsedPublicID == firstPublicID }
    }

    guard let herdPublicID = herdRecord.parsedPublicID else {
      throw HerdSharingActionError.bridgeImportFailed(
        "The bridge herd record is missing a valid public ID."
      )
    }

    let duplicateLocalPublicIDs = HerdSharingBridgeReconciler.duplicatePublicIDs(
      in: try swiftDataPublicIDs(
        herdPublicID: herdPublicID,
        in: swiftDataContext
      )
    )
    guard duplicateLocalPublicIDs.isEmpty else {
      let details = duplicatePublicIDDescription(duplicateLocalPublicIDs)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Duplicate SwiftData public IDs must be repaired before importing shared data. \(details)"
      )
    }

    if swiftDataContext.hasChanges {
      try PersistenceLog.save(
        swiftDataContext,
        operation: "HerdSharingCoreDataStore.preImportPendingChanges"
      )
    }
    let operation = try operationCoordinator.begin(
      herdPublicID: herdPublicID,
      direction: .importFromBridge,
      bridgeLocation: source.description
    )

    do {
      let herd = try operationCoordinator.execute(
        .herd,
        operationID: operation.id
      ) {
        try upsertSwiftDataHerd(from: herdRecord, in: swiftDataContext)
      }
      let sharedTagColorDefinitionRecords = try fetchSharedTagColorDefinitionRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let tagColorDefinitionResult = try operationCoordinator.execute(
        .tagColorDefinitions,
        operationID: operation.id
      ) {
        try upsertSwiftDataTagColorDefinitions(
          from: canonicalImportRecords(sharedTagColorDefinitionRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedStatusReferenceRecords = try fetchSharedAnimalStatusReferenceRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let statusReferenceResult = try operationCoordinator.execute(
        .statusReferences,
        operationID: operation.id
      ) {
        try upsertSwiftDataStatusReferences(
          from: canonicalImportRecords(sharedStatusReferenceRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedPastureGroupRecords = try fetchSharedPastureGroupRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let pastureGroupResult = try operationCoordinator.execute(
        .pastureGroups,
        operationID: operation.id
      ) {
        try upsertSwiftDataPastureGroups(
          from: canonicalImportRecords(sharedPastureGroupRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedPastureRecords = try fetchSharedPastureRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let pastureResult = try operationCoordinator.execute(
        .pastures,
        operationID: operation.id
      ) {
        try upsertSwiftDataPastures(
          from: canonicalImportRecords(sharedPastureRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedAnimalRecords = try fetchSharedAnimalRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let animalResult = try operationCoordinator.execute(
        .animals,
        operationID: operation.id
      ) {
        try upsertSwiftDataAnimals(
          from: canonicalImportRecords(sharedAnimalRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedAnimalTagRecords = try fetchSharedAnimalTagRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let animalTagResult = try operationCoordinator.execute(
        .animalTags,
        operationID: operation.id
      ) {
        try upsertSwiftDataAnimalTags(
          from: canonicalImportRecords(sharedAnimalTagRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedMovementRecords = try fetchSharedMovementRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let movementResult = try operationCoordinator.execute(
        .movements,
        operationID: operation.id
      ) {
        try upsertSwiftDataMovements(
          from: canonicalImportRecords(sharedMovementRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedStatusRecords = try fetchSharedStatusRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let statusRecordResult = try operationCoordinator.execute(
        .statusRecords,
        operationID: operation.id
      ) {
        try upsertSwiftDataStatusRecords(
          from: canonicalImportRecords(sharedStatusRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedWorkingProtocolTemplates = try fetchSharedWorkingProtocolTemplateRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let workingProtocolTemplateResult = try operationCoordinator.execute(
        .workingProtocolTemplates,
        operationID: operation.id
      ) {
        try upsertSwiftDataWorkingProtocolTemplates(
          from: canonicalImportRecords(sharedWorkingProtocolTemplates),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedWorkingSessions = try fetchSharedWorkingSessionRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let workingSessionResult = try operationCoordinator.execute(
        .workingSessions,
        operationID: operation.id
      ) {
        try upsertSwiftDataWorkingSessions(
          from: canonicalImportRecords(sharedWorkingSessions),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedWorkingQueueItems = try fetchSharedWorkingQueueItemRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let workingQueueItemResult = try operationCoordinator.execute(
        .workingQueueItems,
        operationID: operation.id
      ) {
        try upsertSwiftDataWorkingQueueItems(
          from: canonicalImportRecords(sharedWorkingQueueItems),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedWorkingTreatmentRecords = try fetchSharedWorkingTreatmentRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let workingTreatmentRecordResult = try operationCoordinator.execute(
        .workingTreatmentRecords,
        operationID: operation.id
      ) {
        try upsertSwiftDataWorkingTreatmentRecords(
          from: canonicalImportRecords(sharedWorkingTreatmentRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedHealthRecords = try fetchSharedHealthRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let healthRecordResult = try operationCoordinator.execute(
        .healthRecords,
        operationID: operation.id
      ) {
        try upsertSwiftDataHealthRecords(
          from: canonicalImportRecords(sharedHealthRecords),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedPregnancyChecks = try fetchSharedPregnancyCheckRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let pregnancyCheckResult = try operationCoordinator.execute(
        .pregnancyChecks,
        operationID: operation.id
      ) {
        try upsertSwiftDataPregnancyChecks(
          from: canonicalImportRecords(sharedPregnancyChecks),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedFieldCheckSessions = try fetchSharedFieldCheckSessionRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let fieldCheckSessionResult = try operationCoordinator.execute(
        .fieldCheckSessions,
        operationID: operation.id
      ) {
        try upsertSwiftDataFieldCheckSessions(
          from: canonicalImportRecords(sharedFieldCheckSessions),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedFieldCheckAnimalChecks = try fetchSharedFieldCheckAnimalCheckRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let fieldCheckAnimalCheckResult = try operationCoordinator.execute(
        .fieldCheckAnimalChecks,
        operationID: operation.id
      ) {
        try upsertSwiftDataFieldCheckAnimalChecks(
          from: canonicalImportRecords(sharedFieldCheckAnimalChecks),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedFieldCheckFindings = try fetchSharedFieldCheckFindingRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let fieldCheckFindingResult = try operationCoordinator.execute(
        .fieldCheckFindings,
        operationID: operation.id
      ) {
        try upsertSwiftDataFieldCheckFindings(
          from: canonicalImportRecords(sharedFieldCheckFindings),
          herd: herd,
          in: swiftDataContext
        )
      }
      let sharedDeletedRecords = try fetchSharedDeletedRecords(
        herdPublicID: herdPublicID,
        in: source.store
      )
      let deletionResult = try operationCoordinator.execute(
        .deletions,
        operationID: operation.id
      ) {
        try deleteSwiftDataRecords(
          from: sharedDeletedRecords,
          herd: herd,
          in: swiftDataContext
        )
      }
      let updatedRecordConflicts =
        tagColorDefinitionResult.updatedRecordConflicts
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
      let freshConflictReport = HerdSharingBridgeConflictReport(
        existingLocalRecordUpdateCount: updatedRecordConflicts.count,
        updatedRecordConflicts: updatedRecordConflicts,
        preventedDeleteConflicts: deletionResult.preventedDeleteConflicts
      )
      let conflictReport = freshConflictReport.recoveringMissingConflicts(
        from: operation.pendingConflictReport
      )
      try operationCoordinator.recordConflictReport(
        conflictReport,
        operationID: operation.id
      )

      try operationCoordinator.execute(
        .persistentStoreCommit,
        operationID: operation.id
      ) {
        if swiftDataContext.hasChanges {
          try PersistenceLog.save(
            swiftDataContext,
            operation: "HerdSharingCoreDataStore.atomicSwiftDataImport"
          )
        }
      }

      let reconciliationReport = try operationCoordinator.execute(
        .reconciliation,
        operationID: operation.id
      ) {
        HerdSharingBridgeReconciler.makeReport(
          localPublicIDs: try swiftDataPublicIDs(
            herdPublicID: herdPublicID,
            in: swiftDataContext
          ),
          bridgePublicIDs: [
            .herd: matchingHerdRecords.compactMap(\.parsedPublicID),
            .tagColorDefinitions: sharedTagColorDefinitionRecords.compactMap(\.parsedPublicID),
            .statusReferences: sharedStatusReferenceRecords.compactMap(\.parsedPublicID),
            .pastureGroups: sharedPastureGroupRecords.compactMap(\.parsedPublicID),
            .pastures: sharedPastureRecords.compactMap(\.parsedPublicID),
            .animals: sharedAnimalRecords.compactMap(\.parsedPublicID),
            .animalTags: sharedAnimalTagRecords.compactMap(\.parsedPublicID),
            .movements: sharedMovementRecords.compactMap(\.parsedPublicID),
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

      let result = HerdSharingBridgeImportResult(
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
        conflictReport: conflictReport,
        reconciliationReport: reconciliationReport
      )
      try operationCoordinator.complete(
        operationID: operation.id,
        recordCounts: [
          "insertedRecords": totalInsertedRecordCount(in: result),
          "updatedRecords": totalUpdatedRecordCount(in: result),
          "deletedRecords": result.deletedRecordCount,
        ],
        reconciliationSummary: reconciliationReport.summary
      )
      return result
    } catch {
      swiftDataContext.rollback()
      operationCoordinator.fail(operationID: operation.id, error: error)
      throw error
    }
  }
  private func swiftDataPublicIDs(
    herdPublicID: UUID,
    in context: ModelContext
  ) throws -> [HerdSharingBridgeStep: [UUID]] {
    [
      .herd: try context.fetch(FetchDescriptor<Herd>())
        .filter { $0.publicID == herdPublicID }
        .map(\.publicID),
      .tagColorDefinitions: try context.fetch(FetchDescriptor<TagColorDefinition>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.id),
      .statusReferences: try context.fetch(FetchDescriptor<AnimalStatusReference>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.id),
      .pastureGroups: try context.fetch(FetchDescriptor<PastureGroup>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .pastures: try context.fetch(FetchDescriptor<Pasture>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .animals: try context.fetch(FetchDescriptor<Animal>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .animalTags: try context.fetch(FetchDescriptor<AnimalTag>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .movements: try context.fetch(FetchDescriptor<MovementRecord>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .statusRecords: try context.fetch(FetchDescriptor<StatusRecord>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingProtocolTemplates: try context.fetch(FetchDescriptor<WorkingProtocolTemplate>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingSessions: try context.fetch(FetchDescriptor<WorkingSession>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingQueueItems: try context.fetch(FetchDescriptor<WorkingQueueItem>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingTreatmentRecords: try context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .healthRecords: try context.fetch(FetchDescriptor<HealthRecord>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .pregnancyChecks: try context.fetch(FetchDescriptor<PregnancyCheck>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckSessions: try context.fetch(FetchDescriptor<FieldCheckSession>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckAnimalChecks: try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckFindings: try context.fetch(FetchDescriptor<FieldCheckFinding>())
        .filter { $0.herd?.publicID == herdPublicID }
        .map(\.publicID),
    ]
  }

  private func duplicatePublicIDDescription(
    _ duplicates: [HerdSharingBridgeStep: [UUID]]
  ) -> String {
    duplicates
      .sorted { $0.key.rawValue < $1.key.rawValue }
      .map { step, publicIDs in
        "\(step.displayName): \(publicIDs.map(\.uuidString).joined(separator: ", "))"
      }
      .joined(separator: "; ")
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

  private func canonicalImportRecords<Record: NSManagedObject>(
    _ records: [Record]
  ) -> [Record] {
    var recordsByPublicID: [String: Record] = [:]
    for record in records {
      guard let publicID = record.value(forKey: "publicID") as? String, !publicID.isEmpty else {
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
        recordsByPublicID[publicID] = record
      }
    }
    return recordsByPublicID.values.sorted { lhs, rhs in
      let lhsID = lhs.value(forKey: "publicID") as? String ?? ""
      let rhsID = rhs.value(forKey: "publicID") as? String ?? ""
      return lhsID < rhsID
    }
  }

}
