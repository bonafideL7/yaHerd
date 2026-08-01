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
        publicID: { $0.publicID }
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

  private func fetchAll<Model: PersistentModel>(
    _ descriptor: FetchDescriptor<Model>,
    pageSize: Int = 500
  ) throws -> [Model] {
    var records: [Model] = []
    var offset = 0

    while true {
      var page = descriptor
      page.fetchOffset = offset
      page.fetchLimit = pageSize
      let fetched = try modelContext.fetch(page)
      records.append(contentsOf: fetched)
      guard fetched.count == pageSize else { break }
      offset += fetched.count
    }

    return records
  }

  private func mergeRelatedModels<Model: AnyObject>(
    _ directModels: [Model],
    with relatedModels: [Model],
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
      guard seenModels.insert(ObjectIdentifier(model)).inserted else { continue }
      mergedModels.append(model)
    }

    return mergedModels.sorted {
      publicID($0).uuidString < publicID($1).uuidString
    }
  }
}
