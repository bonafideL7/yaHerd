//
//  SwiftDataHerdSharingActor.swift
//  yaHerd
//

import Foundation
import SwiftData

struct HerdSharingSwiftDataExport: Sendable {
  let herd: HerdSummary
  let snapshot: HerdSharingBridgeStoreSnapshot
  let localPublicIDs: [HerdSharingBridgeStep: [UUID]]
}

protocol HerdSharingImportApplying: Sendable {
  func applyImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication
}

protocol HerdSharingSwiftDataMutating: Sendable {
  func acceptPreventedSharedDeletes(
    _ conflicts: [HerdSharingPreventedDeleteConflict]
  ) async throws -> Int

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    from review: HerdSharingConflictReview
  ) async throws -> HerdSharingLocalFieldRestoreResult
}

protocol HerdSharingExportSnapshotReading: Sendable {
  func makeExport(
    for herd: HerdSummary,
    storeDescription: String
  ) async throws -> HerdSharingSwiftDataExport
}

@ModelActor
actor SwiftDataHerdSharingActor: HerdSharingExportSnapshotReading, HerdSharingImportApplying,
  HerdSharingSwiftDataMutating
{
  private static let exportPageSize = 500

  func applyImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) throws -> HerdSharingSwiftDataImportApplication {
    try PerformanceLog.measure("SwiftData.sharing.import") {
      try HerdSharingSwiftDataImportEngine.apply(
        snapshot,
        pendingConflictReport: pendingConflictReport,
        failureInjector: failureInjector,
        in: modelContext
      )
    }
  }

  func acceptPreventedSharedDeletes(
    _ conflicts: [HerdSharingPreventedDeleteConflict]
  ) throws -> Int {
    try PerformanceLog.measure("SwiftData.sharing.acceptDeletes") {
      try HerdSharingSwiftDataMutationEngine.acceptPreventedSharedDeletes(
        conflicts,
        context: modelContext
      )
    }
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    from review: HerdSharingConflictReview
  ) throws -> HerdSharingLocalFieldRestoreResult {
    try PerformanceLog.measure("SwiftData.sharing.restoreLocalFields") {
      try HerdSharingSwiftDataMutationEngine.restoreLocalFields(
        selections,
        from: review,
        context: modelContext
      )
    }
  }

  func makeExport(
    for requestedHerd: HerdSummary,
    storeDescription: String
  ) throws -> HerdSharingSwiftDataExport {
    try PerformanceLog.measure("SwiftData.sharing.exportSnapshot") {
      let herdID = requestedHerd.publicID
      var herdDescriptor = FetchDescriptor<Herd>(
        predicate: #Predicate<Herd> { herd in
          herd.publicID == herdID
        },
        sortBy: [SortDescriptor(\Herd.createdAt)]
      )
      herdDescriptor.fetchLimit = 2
      let matchingHerds = try modelContext.fetch(herdDescriptor)
      guard matchingHerds.count <= 1 else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Multiple SwiftData herd roots use public ID \(herdID.uuidString). Repair the duplicate before sharing or synchronization."
        )
      }
      let herd = matchingHerds.first?.toSummary() ?? requestedHerd

      let tagColorDefinitions = try fetchAll(
        FetchDescriptor<TagColorDefinition>(
          predicate: #Predicate<TagColorDefinition> { definition in
            definition.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\TagColorDefinition.id)]
        )
      )
      let statusReferences = try fetchAll(
        FetchDescriptor<AnimalStatusReference>(
          predicate: #Predicate<AnimalStatusReference> { reference in
            reference.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\AnimalStatusReference.id)]
        )
      )
      let pastureGroups = try fetchAll(
        FetchDescriptor<PastureGroup>(
          predicate: #Predicate<PastureGroup> { group in
            group.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\PastureGroup.publicID)]
        )
      )
      let pastures = try fetchAll(
        FetchDescriptor<Pasture>(
          predicate: #Predicate<Pasture> { pasture in
            pasture.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\Pasture.publicID)]
        )
      )
      let animals = try fetchAll(
        FetchDescriptor<Animal>(
          predicate: #Predicate<Animal> { animal in
            animal.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\Animal.publicID)]
        )
      )
      let directAnimalTags = try fetchAll(
        FetchDescriptor<AnimalTag>(
          predicate: #Predicate<AnimalTag> { tag in
            tag.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\AnimalTag.publicID)]
        )
      )
      let animalTags = mergeRelatedModels(
        directAnimalTags,
        with: animals.flatMap { $0.tags },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directMovements = try fetchAll(
        FetchDescriptor<MovementRecord>(
          predicate: #Predicate<MovementRecord> { movement in
            movement.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\MovementRecord.publicID)]
        )
      )
      let movements = mergeRelatedModels(
        directMovements,
        with: animals.flatMap { $0.movementRecords },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directStatusRecords = try fetchAll(
        FetchDescriptor<StatusRecord>(
          predicate: #Predicate<StatusRecord> { record in
            record.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\StatusRecord.publicID)]
        )
      )
      let statusRecords = mergeRelatedModels(
        directStatusRecords,
        with: animals.flatMap { $0.statusRecords },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directHealthRecords = try fetchAll(
        FetchDescriptor<HealthRecord>(
          predicate: #Predicate<HealthRecord> { record in
            record.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\HealthRecord.publicID)]
        )
      )
      let healthRecords = mergeRelatedModels(
        directHealthRecords,
        with: animals.flatMap { $0.healthRecords },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directPregnancyChecks = try fetchAll(
        FetchDescriptor<PregnancyCheck>(
          predicate: #Predicate<PregnancyCheck> { check in
            check.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\PregnancyCheck.publicID)]
        )
      )
      let pregnancyChecks = mergeRelatedModels(
        directPregnancyChecks,
        with: animals.flatMap { $0.pregnancyChecks },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let workingProtocolTemplates = try fetchAll(
        FetchDescriptor<WorkingProtocolTemplate>(
          predicate: #Predicate<WorkingProtocolTemplate> { template in
            template.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\WorkingProtocolTemplate.publicID)]
        )
      )
      let workingSessions = try fetchAll(
        FetchDescriptor<WorkingSession>(
          predicate: #Predicate<WorkingSession> { session in
            session.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\WorkingSession.publicID)]
        )
      )
      let directWorkingQueueItems = try fetchAll(
        FetchDescriptor<WorkingQueueItem>(
          predicate: #Predicate<WorkingQueueItem> { item in
            item.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\WorkingQueueItem.publicID)]
        )
      )
      let workingQueueItems = mergeRelatedModels(
        directWorkingQueueItems,
        with: workingSessions.flatMap { $0.queueItems }
          + animals.flatMap { $0.workingQueueItemStorage ?? [] },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directWorkingTreatmentRecords = try fetchAll(
        FetchDescriptor<WorkingTreatmentRecord>(
          predicate: #Predicate<WorkingTreatmentRecord> { record in
            record.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\WorkingTreatmentRecord.publicID)]
        )
      )
      let workingTreatmentRecords = mergeRelatedModels(
        directWorkingTreatmentRecords,
        with: workingSessions.flatMap { $0.treatmentRecordStorage ?? [] }
          + animals.flatMap { $0.workingTreatmentRecordStorage ?? [] },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directFieldCheckSessions = try fetchAll(
        FetchDescriptor<FieldCheckSession>(
          predicate: #Predicate<FieldCheckSession> { session in
            session.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\FieldCheckSession.publicID)]
        )
      )
      let fieldCheckSessions = mergeRelatedModels(
        directFieldCheckSessions,
        with: pastures.flatMap { $0.fieldCheckSessionStorage ?? [] },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directFieldCheckAnimalChecks = try fetchAll(
        FetchDescriptor<FieldCheckAnimalCheck>(
          predicate: #Predicate<FieldCheckAnimalCheck> { check in
            check.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\FieldCheckAnimalCheck.publicID)]
        )
      )
      let fieldCheckAnimalChecks = mergeRelatedModels(
        directFieldCheckAnimalChecks,
        with: fieldCheckSessions.flatMap { $0.animalChecks }
          + animals.flatMap { $0.fieldCheckAnimalCheckStorage ?? [] },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )
      let directFieldCheckFindings = try fetchAll(
        FetchDescriptor<FieldCheckFinding>(
          predicate: #Predicate<FieldCheckFinding> { finding in
            finding.herd?.publicID == herdID
          },
          sortBy: [SortDescriptor(\FieldCheckFinding.publicID)]
        )
      )
      let fieldCheckFindings = mergeRelatedModels(
        directFieldCheckFindings,
        with: fieldCheckSessions.flatMap { $0.findings }
          + animals.flatMap { $0.fieldCheckFindingStorage ?? [] },
        requestedHerdPublicID: herdID,
        relatedHerdPublicID: { $0.herd?.publicID },
        publicID: { $0.publicID }
      )

      var collaborativeAggregates: [any CollaborativelyMutableAggregate] = []
      if let herdModel = matchingHerds.first {
        collaborativeAggregates.append(herdModel)
      }
      appendCollaborativeAggregates(tagColorDefinitions, to: &collaborativeAggregates)
      appendCollaborativeAggregates(statusReferences, to: &collaborativeAggregates)
      appendCollaborativeAggregates(pastureGroups, to: &collaborativeAggregates)
      appendCollaborativeAggregates(pastures, to: &collaborativeAggregates)
      appendCollaborativeAggregates(animals, to: &collaborativeAggregates)
      appendCollaborativeAggregates(animalTags, to: &collaborativeAggregates)
      appendCollaborativeAggregates(movements, to: &collaborativeAggregates)
      appendCollaborativeAggregates(statusRecords, to: &collaborativeAggregates)
      appendCollaborativeAggregates(workingProtocolTemplates, to: &collaborativeAggregates)
      appendCollaborativeAggregates(workingSessions, to: &collaborativeAggregates)
      appendCollaborativeAggregates(workingQueueItems, to: &collaborativeAggregates)
      appendCollaborativeAggregates(workingTreatmentRecords, to: &collaborativeAggregates)
      appendCollaborativeAggregates(healthRecords, to: &collaborativeAggregates)
      appendCollaborativeAggregates(pregnancyChecks, to: &collaborativeAggregates)
      appendCollaborativeAggregates(fieldCheckSessions, to: &collaborativeAggregates)
      appendCollaborativeAggregates(fieldCheckAnimalChecks, to: &collaborativeAggregates)
      appendCollaborativeAggregates(fieldCheckFindings, to: &collaborativeAggregates)
      try prepareCollaborationRevisionMetadata(
        for: collaborativeAggregates,
        herdPublicID: herdID
      )

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
        let details = duplicateLocalPublicIDs
          .sorted { $0.key.rawValue < $1.key.rawValue }
          .map { step, publicIDs in
            "\(step.displayName): \(publicIDs.map(\.uuidString).joined(separator: ", "))"
          }
          .joined(separator: "; ")
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Duplicate application-managed public IDs must be repaired before export. \(details)"
        )
      }

      return HerdSharingSwiftDataExport(
        herd: herd,
        snapshot: try HerdSharingBridgeExportSnapshotBuilder.makeExportStoreSnapshot(
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
          fieldCheckFindings: fieldCheckFindings,
          storeDescription: storeDescription
        ),
        localPublicIDs: localPublicIDs
      )
    }
  }

  private func prepareCollaborationRevisionMetadata(
    for aggregates: [any CollaborativelyMutableAggregate],
    herdPublicID: UUID
  ) throws {
    let revisionRecords = try fetchAll(
      FetchDescriptor<CollaborationRevisionRecord>(
        predicate: #Predicate<CollaborationRevisionRecord> { record in
          record.herdPublicID == herdPublicID
        },
        sortBy: [SortDescriptor(\CollaborationRevisionRecord.aggregateKey)]
      )
    )
    var recordsByKey: [CollaborationAggregateKey: CollaborationRevisionRecord] = [:]
    var requiresSave = false

    for record in revisionRecords {
      let key = record.key
      guard CollaborationAggregateType(rawValue: key.sourceEntityName) != nil else {
        continue
      }
      guard let existing = recordsByKey[key] else {
        recordsByKey[key] = record
        continue
      }

      let keepIncoming = record.revision > existing.revision
        || (record.revision == existing.revision && record.modifiedAt > existing.modifiedAt)
      if keepIncoming {
        modelContext.delete(existing)
        recordsByKey[key] = record
      } else {
        modelContext.delete(record)
      }
      requiresSave = true
      ReliabilityLog.persistenceEvent(
        "SwiftDataHerdSharingActor.duplicateRevisionMetadataRepaired",
        detail: key.storageKey
      )
    }

    for aggregate in aggregates {
      let key = aggregate.collaborationKey
      guard recordsByKey[key] == nil else { continue }
      let metadata = CollaborationRevisionMetadata.localBootstrap(
        fieldValues: CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
      )
      let record = CollaborationRevisionRecord(
        key: key,
        herdPublicID: aggregate.collaborationHerdPublicID ?? herdPublicID,
        metadata: metadata
      )
      modelContext.insert(record)
      recordsByKey[key] = record
      requiresSave = true
    }

    if requiresSave {
      try PersistenceLog.save(
        modelContext,
        operation: "SwiftDataHerdSharingActor.prepareCollaborationRevisionMetadata"
      )
    }

    let entries = recordsByKey.values
      .map { CollaborationRevisionRegistry.Entry(key: $0.key, metadata: $0.metadata) }
      .sorted { $0.key.storageKey < $1.key.storageKey }
    CollaborationRevisionRegistry.registerAuthoritativeLocals(entries)
  }

  private func appendCollaborativeAggregates<Model: CollaborativelyMutableAggregate>(
    _ models: [Model],
    to aggregates: inout [any CollaborativelyMutableAggregate]
  ) {
    for model in models {
      aggregates.append(model)
    }
  }

  private func fetchAll<Model: PersistentModel>(
    _ descriptor: FetchDescriptor<Model>,
    pageSize: Int = 500
  ) throws -> [Model] {
    let expectedCount = try modelContext.fetchCount(descriptor)
    var records: [Model] = []
    records.reserveCapacity(expectedCount)
    var seenModelIDs = Set<PersistentIdentifier>()
    seenModelIDs.reserveCapacity(expectedCount)
    var offset = 0

    while records.count < expectedCount {
      var page = descriptor
      page.fetchOffset = offset
      page.fetchLimit = pageSize
      let fetched = try modelContext.fetch(page)

      guard !fetched.isEmpty else {
        throw unstablePagedExportError(
          modelType: Model.self,
          expectedCount: expectedCount,
          fetchedCount: records.count
        )
      }

      for record in fetched {
        guard seenModelIDs.insert(record.persistentModelID).inserted else {
          throw unstablePagedExportError(
            modelType: Model.self,
            expectedCount: expectedCount,
            fetchedCount: records.count
          )
        }
        records.append(record)
      }

      offset += fetched.count
      if fetched.count < pageSize { break }
    }

    guard records.count == expectedCount else {
      throw unstablePagedExportError(
        modelType: Model.self,
        expectedCount: expectedCount,
        fetchedCount: records.count
      )
    }

    return records
  }

  private func unstablePagedExportError<Model: PersistentModel>(
    modelType: Model.Type,
    expectedCount: Int,
    fetchedCount: Int
  ) -> HerdSharingActionError {
    .bridgeConsistencyFailed(
      "SwiftData export could not produce a complete stable page sequence for \(String(describing: modelType)); expected \(expectedCount) records and read \(fetchedCount). Repair duplicate application-managed public IDs before sharing or synchronization."
    )
  }

  private func mergeRelatedModels<Model: AnyObject>(
    _ directModels: [Model],
    with relatedModels: [Model],
    requestedHerdPublicID: UUID,
    relatedHerdPublicID: (Model) -> UUID?,
    publicID: (Model) -> UUID
  ) -> [Model] {
    var seenModels = Set<ObjectIdentifier>()
    var mergedModels: [Model] = []
    mergedModels.reserveCapacity(directModels.count + relatedModels.count)

    for model in directModels {
      guard seenModels.insert(ObjectIdentifier(model)).inserted else { continue }
      mergedModels.append(model)
    }
    for model in relatedModels {
      if let scopedHerdPublicID = relatedHerdPublicID(model),
        scopedHerdPublicID != requestedHerdPublicID
      {
        continue
      }
      guard seenModels.insert(ObjectIdentifier(model)).inserted else { continue }
      mergedModels.append(model)
    }

    return mergedModels.sorted {
      publicID($0).uuidString < publicID($1).uuidString
    }
  }
}
