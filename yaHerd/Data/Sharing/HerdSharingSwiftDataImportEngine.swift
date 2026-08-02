//
//  HerdSharingSwiftDataImportEngine.swift
//  yaHerd
//

@preconcurrency import CoreData
import Foundation
import SwiftData

struct HerdSharingSwiftDataImportApplication: Sendable {
  let result: HerdSharingBridgeImportResult
  let completedSteps: [HerdSharingBridgeStep]
}

extension HerdSharingSwiftDataImportEngine {
  static func prepare(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector,
    in context: ModelContext
  ) throws -> HerdSharingSwiftDataImportApplication {
    let herdRecords: [SharedHerdRecord] = try detachedRecords(
      from: snapshot, step: .herd, as: SharedHerdRecord.self)
    guard let herdRecord = herdRecords.sorted(by: sharedRecordSort).first else {
      throw HerdSharingActionError.bridgeImportFailed(
        "No bridge herd record was found in the \(snapshot.storeDescription)."
      )
    }

    let tagColorRecords: [SharedTagColorDefinitionRecord] = try detachedRecords(
      from: snapshot, step: .tagColorDefinitions, as: SharedTagColorDefinitionRecord.self)
    let statusReferenceRecords: [SharedAnimalStatusReferenceRecord] = try detachedRecords(
      from: snapshot, step: .statusReferences, as: SharedAnimalStatusReferenceRecord.self)
    let pastureGroupRecords: [SharedPastureGroupRecord] = try detachedRecords(
      from: snapshot, step: .pastureGroups, as: SharedPastureGroupRecord.self)
    let pastureRecords: [SharedPastureRecord] = try detachedRecords(
      from: snapshot, step: .pastures, as: SharedPastureRecord.self)
    let animalRecords: [SharedAnimalRecord] = try detachedRecords(
      from: snapshot, step: .animals, as: SharedAnimalRecord.self)
    let animalTagRecords: [SharedAnimalTagRecord] = try detachedRecords(
      from: snapshot, step: .animalTags, as: SharedAnimalTagRecord.self)
    let movementRecords: [SharedMovementRecord] = try detachedRecords(
      from: snapshot, step: .movements, as: SharedMovementRecord.self)
    let statusRecords: [SharedStatusRecord] = try detachedRecords(
      from: snapshot, step: .statusRecords, as: SharedStatusRecord.self)
    let workingTemplateRecords: [SharedWorkingProtocolTemplateRecord] = try detachedRecords(
      from: snapshot, step: .workingProtocolTemplates, as: SharedWorkingProtocolTemplateRecord.self)
    let workingSessionRecords: [SharedWorkingSessionRecord] = try detachedRecords(
      from: snapshot, step: .workingSessions, as: SharedWorkingSessionRecord.self)
    let workingQueueRecords: [SharedWorkingQueueItemRecord] = try detachedRecords(
      from: snapshot, step: .workingQueueItems, as: SharedWorkingQueueItemRecord.self)
    let workingTreatmentRecords: [SharedWorkingTreatmentRecord] = try detachedRecords(
      from: snapshot, step: .workingTreatmentRecords, as: SharedWorkingTreatmentRecord.self)
    let healthRecords: [SharedHealthRecord] = try detachedRecords(
      from: snapshot, step: .healthRecords, as: SharedHealthRecord.self)
    let pregnancyRecords: [SharedPregnancyCheckRecord] = try detachedRecords(
      from: snapshot, step: .pregnancyChecks, as: SharedPregnancyCheckRecord.self)
    let fieldCheckSessionRecords: [SharedFieldCheckSessionRecord] = try detachedRecords(
      from: snapshot, step: .fieldCheckSessions, as: SharedFieldCheckSessionRecord.self)
    let fieldCheckAnimalRecords: [SharedFieldCheckAnimalCheckRecord] = try detachedRecords(
      from: snapshot, step: .fieldCheckAnimalChecks, as: SharedFieldCheckAnimalCheckRecord.self)
    let fieldCheckFindingRecords: [SharedFieldCheckFindingRecord] = try detachedRecords(
      from: snapshot, step: .fieldCheckFindings, as: SharedFieldCheckFindingRecord.self)
    let deletionRecords: [SharedDeletedRecord] = try detachedRecords(
      from: snapshot, step: .deletions, as: SharedDeletedRecord.self)

    let duplicateLocalPublicIDs = HerdSharingBridgeReconciler.duplicatePublicIDs(
      in: try swiftDataPublicIDs(herdPublicID: snapshot.herdPublicID, in: context)
    )
    guard duplicateLocalPublicIDs.isEmpty else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Duplicate SwiftData public IDs must be repaired before importing shared data. \(duplicateDescription(duplicateLocalPublicIDs))"
      )
    }

    if context.hasChanges {
      try PersistenceLog.save(context, operation: "SwiftDataHerdSharingActor.preImportPendingChanges")
    }

    var completedSteps: [HerdSharingBridgeStep] = []
    func complete(_ step: HerdSharingBridgeStep) throws {
      try failureInjector.check(after: step)
      completedSteps.append(step)
    }

    do {
      let herd = try upsertSwiftDataHerd(from: herdRecord, in: context)
      try complete(.herd)

      let tagColorResult = try upsertSwiftDataTagColorDefinitions(
        from: canonicalImportRecords(tagColorRecords), herd: herd, in: context)
      try complete(.tagColorDefinitions)
      let statusReferenceResult = try upsertSwiftDataStatusReferences(
        from: canonicalImportRecords(statusReferenceRecords), herd: herd, in: context)
      try complete(.statusReferences)
      let pastureGroupResult = try upsertSwiftDataPastureGroups(
        from: canonicalImportRecords(pastureGroupRecords), herd: herd, in: context)
      try complete(.pastureGroups)
      let pastureResult = try upsertSwiftDataPastures(
        from: canonicalImportRecords(pastureRecords), herd: herd, in: context)
      try complete(.pastures)
      let animalResult = try upsertSwiftDataAnimals(
        from: canonicalImportRecords(animalRecords), herd: herd, in: context)
      try complete(.animals)
      let animalTagResult = try upsertSwiftDataAnimalTags(
        from: canonicalImportRecords(animalTagRecords), herd: herd, in: context)
      try complete(.animalTags)
      let movementResult = try upsertSwiftDataMovements(
        from: canonicalImportRecords(movementRecords), herd: herd, in: context)
      try complete(.movements)
      let statusResult = try upsertSwiftDataStatusRecords(
        from: canonicalImportRecords(statusRecords), herd: herd, in: context)
      try complete(.statusRecords)
      let workingTemplateResult = try upsertSwiftDataWorkingProtocolTemplates(
        from: canonicalImportRecords(workingTemplateRecords), herd: herd, in: context)
      try complete(.workingProtocolTemplates)
      let workingSessionResult = try upsertSwiftDataWorkingSessions(
        from: canonicalImportRecords(workingSessionRecords), herd: herd, in: context)
      try complete(.workingSessions)
      let workingQueueResult = try upsertSwiftDataWorkingQueueItems(
        from: canonicalImportRecords(workingQueueRecords), herd: herd, in: context)
      try complete(.workingQueueItems)
      let workingTreatmentResult = try upsertSwiftDataWorkingTreatmentRecords(
        from: canonicalImportRecords(workingTreatmentRecords), herd: herd, in: context)
      try complete(.workingTreatmentRecords)
      let healthResult = try upsertSwiftDataHealthRecords(
        from: canonicalImportRecords(healthRecords), herd: herd, in: context)
      try complete(.healthRecords)
      let pregnancyResult = try upsertSwiftDataPregnancyChecks(
        from: canonicalImportRecords(pregnancyRecords), herd: herd, in: context)
      try complete(.pregnancyChecks)
      let fieldCheckSessionResult = try upsertSwiftDataFieldCheckSessions(
        from: canonicalImportRecords(fieldCheckSessionRecords), herd: herd, in: context)
      try complete(.fieldCheckSessions)
      let fieldCheckAnimalResult = try upsertSwiftDataFieldCheckAnimalChecks(
        from: canonicalImportRecords(fieldCheckAnimalRecords), herd: herd, in: context)
      try complete(.fieldCheckAnimalChecks)
      let fieldCheckFindingResult = try upsertSwiftDataFieldCheckFindings(
        from: canonicalImportRecords(fieldCheckFindingRecords), herd: herd, in: context)
      try complete(.fieldCheckFindings)

      let deletionResult = try HerdSharingSwiftDataMutationEngine.deleteSwiftDataRecords(
        from: canonicalImportRecords(deletionRecords), herd: herd, in: context)
      try complete(.deletions)

      let updatedConflicts =
        tagColorResult.updatedRecordConflicts
        + statusReferenceResult.updatedRecordConflicts
        + pastureGroupResult.updatedRecordConflicts
        + pastureResult.updatedRecordConflicts
        + animalResult.updatedRecordConflicts
        + animalTagResult.updatedRecordConflicts
        + movementResult.updatedRecordConflicts
        + statusResult.updatedRecordConflicts
        + workingTemplateResult.updatedRecordConflicts
        + workingSessionResult.updatedRecordConflicts
        + workingQueueResult.updatedRecordConflicts
        + workingTreatmentResult.updatedRecordConflicts
        + healthResult.updatedRecordConflicts
        + pregnancyResult.updatedRecordConflicts
        + fieldCheckSessionResult.updatedRecordConflicts
        + fieldCheckAnimalResult.updatedRecordConflicts
        + fieldCheckFindingResult.updatedRecordConflicts
      let conflictReport = HerdSharingBridgeConflictReport(
        existingLocalRecordUpdateCount: updatedConflicts.count,
        updatedRecordConflicts: updatedConflicts,
        preventedDeleteConflicts: deletionResult.preventedDeleteConflicts
      ).recoveringMissingConflicts(from: pendingConflictReport)

      return HerdSharingSwiftDataImportApplication(
        result: HerdSharingBridgeImportResult(
          herdName: herd.name,
          insertedTagColorDefinitionCount: tagColorResult.inserted,
          updatedTagColorDefinitionCount: tagColorResult.updated,
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
          insertedStatusRecordCount: statusResult.inserted,
          updatedStatusRecordCount: statusResult.updated,
          insertedHealthRecordCount: healthResult.inserted,
          updatedHealthRecordCount: healthResult.updated,
          insertedPregnancyCheckCount: pregnancyResult.inserted,
          updatedPregnancyCheckCount: pregnancyResult.updated,
          insertedWorkingProtocolTemplateCount: workingTemplateResult.inserted,
          updatedWorkingProtocolTemplateCount: workingTemplateResult.updated,
          insertedWorkingSessionCount: workingSessionResult.inserted,
          updatedWorkingSessionCount: workingSessionResult.updated,
          insertedWorkingQueueItemCount: workingQueueResult.inserted,
          updatedWorkingQueueItemCount: workingQueueResult.updated,
          insertedWorkingTreatmentRecordCount: workingTreatmentResult.inserted,
          updatedWorkingTreatmentRecordCount: workingTreatmentResult.updated,
          insertedFieldCheckSessionCount: fieldCheckSessionResult.inserted,
          updatedFieldCheckSessionCount: fieldCheckSessionResult.updated,
          insertedFieldCheckAnimalCheckCount: fieldCheckAnimalResult.inserted,
          updatedFieldCheckAnimalCheckCount: fieldCheckAnimalResult.updated,
          insertedFieldCheckFindingCount: fieldCheckFindingResult.inserted,
          updatedFieldCheckFindingCount: fieldCheckFindingResult.updated,
          deletedRecordCount: deletionResult.deletedCount,
          conflictReport: conflictReport,
          reconciliationReport: .empty
        ),
        completedSteps: completedSteps
      )
    } catch {
      context.rollback()
      throw error
    }
  }

  static func commit(
    _ preparation: HerdSharingSwiftDataImportApplication,
    snapshot: HerdSharingBridgeStoreSnapshot,
    failureInjector: HerdSharingBridgeFailureInjector,
    in context: ModelContext
  ) throws -> HerdSharingSwiftDataImportApplication {
    var completedSteps = preparation.completedSteps
    func complete(_ step: HerdSharingBridgeStep) throws {
      try failureInjector.check(after: step)
      completedSteps.append(step)
    }

    do {
      if context.hasChanges {
        try PersistenceLog.save(context, operation: "SwiftDataHerdSharingActor.atomicImport")
      }
      try complete(.persistentStoreCommit)

      let reconciliation = HerdSharingBridgeReconciler.makeReport(
        localPublicIDs: try swiftDataPublicIDs(
          herdPublicID: snapshot.herdPublicID,
          in: context
        ),
        bridgePublicIDs: snapshot.publicIDsByStep,
        deletionTombstoneCount: snapshot.deletionTombstoneCount
      )
      try complete(.reconciliation)

      var result = preparation.result
      result.reconciliationReport = reconciliation
      return HerdSharingSwiftDataImportApplication(
        result: result,
        completedSteps: completedSteps
      )
    } catch {
      context.rollback()
      throw error
    }
  }

  private static func detachedRecords<Record: NSManagedObject>(
    from snapshot: HerdSharingBridgeStoreSnapshot,
    step: HerdSharingBridgeStep,
    as _: Record.Type
  ) throws -> [Record] {
    guard let entityName = step.coreDataEntityName else { return [] }
    guard let entity = HerdSharingCoreDataModelFactory.makeCurrentModel().entitiesByName[entityName]
    else {
      throw HerdSharingBridgeSnapshotError.missingEntityDescription(entityName)
    }
    return try snapshot.records(for: step).map { recordSnapshot in
      let record = Record(entity: entity, insertInto: nil)
      try recordSnapshot.apply(to: record)
      return record
    }
  }

  private static func canonicalImportRecords<Record: NSManagedObject>(
    _ records: [Record]
  ) -> [Record] {
    var canonicalByPublicID: [UUID: Record] = [:]
    var recordsWithoutPublicID: [Record] = []
    for record in records {
      guard let publicIDString = record.value(forKey: "publicID") as? String,
        let publicID = UUID(uuidString: publicIDString)
      else {
        recordsWithoutPublicID.append(record)
        continue
      }
      guard let existing = canonicalByPublicID[publicID] else {
        canonicalByPublicID[publicID] = record
        continue
      }
      if sharedRecordSort(record, existing) {
        canonicalByPublicID[publicID] = record
      }
    }
    return recordsWithoutPublicID + canonicalByPublicID.values
  }

  private static func sharedRecordSort(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
    let lhsDate = lhs.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
    let rhsDate = rhs.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
    if lhsDate != rhsDate { return lhsDate > rhsDate }
    let lhsID = lhs.value(forKey: "publicID") as? String ?? ""
    let rhsID = rhs.value(forKey: "publicID") as? String ?? ""
    return lhsID < rhsID
  }

  private static func swiftDataPublicIDs(
    herdPublicID: UUID,
    in context: ModelContext
  ) throws -> [HerdSharingBridgeStep: [UUID]] {
    [
      .herd: try context.fetch(FetchDescriptor<Herd>())
        .filter { $0.publicID == herdPublicID }.map(\.publicID),
      .tagColorDefinitions: try context.fetch(FetchDescriptor<TagColorDefinition>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.id),
      .statusReferences: try context.fetch(FetchDescriptor<AnimalStatusReference>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.id),
      .pastureGroups: try context.fetch(FetchDescriptor<PastureGroup>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.publicID),
      .pastures: try context.fetch(FetchDescriptor<Pasture>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.publicID),
      .animals: try context.fetch(FetchDescriptor<Animal>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.publicID),
      .animalTags: try context.fetch(FetchDescriptor<AnimalTag>())
        .filter { $0.herd?.publicID == herdPublicID || $0.animal?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .movements: try context.fetch(FetchDescriptor<MovementRecord>())
        .filter { $0.herd?.publicID == herdPublicID || $0.animal?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .statusRecords: try context.fetch(FetchDescriptor<StatusRecord>())
        .filter { $0.herd?.publicID == herdPublicID || $0.animal?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingProtocolTemplates: try context.fetch(FetchDescriptor<WorkingProtocolTemplate>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.publicID),
      .workingSessions: try context.fetch(FetchDescriptor<WorkingSession>())
        .filter { $0.herd?.publicID == herdPublicID }.map(\.publicID),
      .workingQueueItems: try context.fetch(FetchDescriptor<WorkingQueueItem>())
        .filter { $0.herd?.publicID == herdPublicID || $0.session?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .workingTreatmentRecords: try context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
        .filter { $0.herd?.publicID == herdPublicID || $0.session?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .healthRecords: try context.fetch(FetchDescriptor<HealthRecord>())
        .filter { $0.herd?.publicID == herdPublicID || $0.animal?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .pregnancyChecks: try context.fetch(FetchDescriptor<PregnancyCheck>())
        .filter { $0.herd?.publicID == herdPublicID || $0.animal?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckSessions: try context.fetch(FetchDescriptor<FieldCheckSession>())
        .filter { $0.herd?.publicID == herdPublicID || $0.pasture?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckAnimalChecks: try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>())
        .filter { $0.herd?.publicID == herdPublicID || $0.session?.herd?.publicID == herdPublicID }
        .map(\.publicID),
      .fieldCheckFindings: try context.fetch(FetchDescriptor<FieldCheckFinding>())
        .filter { $0.herd?.publicID == herdPublicID || $0.session?.herd?.publicID == herdPublicID }
        .map(\.publicID),
    ]
  }

  private static func duplicateDescription(
    _ duplicates: [HerdSharingBridgeStep: [UUID]]
  ) -> String {
    duplicates.sorted { $0.key.rawValue < $1.key.rawValue }
      .map { step, ids in
        "\(step.displayName): \(ids.map(\.uuidString).joined(separator: ", "))"
      }
      .joined(separator: "; ")
  }
}
