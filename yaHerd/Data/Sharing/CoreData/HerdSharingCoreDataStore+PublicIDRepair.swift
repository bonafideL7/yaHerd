import CoreData
import CryptoKit
import Foundation

@MainActor
protocol PublicIDRepairBridgeStore: AnyObject {
  func publicIDRepairFingerprint(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation
  ) async throws -> String

  func syncPublicIDRepairBridgeRecordsFromSnapshot(
    _ export: HerdSharingSwiftDataExport,
    expectedLocation: HerdSharingAccess.BridgeLocation,
    expectedFingerprint: String
  ) async throws -> HerdSharingBridgeExportResult
}

enum HerdSharingPublicIDRepairBridgeError: LocalizedError, Equatable {
  case targetChanged(expected: String, actual: String)
  case bridgeContentChanged(herdPublicID: UUID)

  var errorDescription: String? {
    switch self {
    case .targetChanged(let expected, let actual):
      return "The public-ID repair bridge target changed from \(expected) to \(actual). The repair remains blocked so no shared data is overwritten."
    case .bridgeContentChanged(let herdPublicID):
      return "Shared bridge data for herd \(herdPublicID.uuidString) changed after public-ID repair preparation. The repair remains blocked so collaborator changes are not overwritten."
    }
  }
}

private struct PublicIDRepairResolvedBridgeTarget {
  let store: NSPersistentStore
  let description: String
  let shouldUpdateShare: Bool
}

extension HerdSharingCoreDataStore: PublicIDRepairBridgeStore {
  func publicIDRepairFingerprint(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation
  ) async throws -> String {
    try await loadIfNeeded()
    let target = try publicIDRepairBridgeTarget(
      for: herd,
      expectedLocation: expectedLocation
    )
    return try await publicIDRepairBridgeFingerprint(
      for: herd,
      expectedLocation: expectedLocation,
      target: target
    )
  }

  func syncPublicIDRepairBridgeRecordsFromSnapshot(
    _ export: HerdSharingSwiftDataExport,
    expectedLocation: HerdSharingAccess.BridgeLocation,
    expectedFingerprint: String
  ) async throws -> HerdSharingBridgeExportResult {
    try await loadIfNeeded()
    let herd = export.herd

    // Resolve the prepared store after the SwiftData export snapshot has been built. Unlike the
    // normal sharing path, repair convergence is not allowed to fall through to another store.
    let target = try publicIDRepairBridgeTarget(
      for: herd,
      expectedLocation: expectedLocation
    )
    let currentFingerprint = try await publicIDRepairBridgeFingerprint(
      for: herd,
      expectedLocation: expectedLocation,
      target: target
    )
    guard currentFingerprint == expectedFingerprint else {
      throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
        herdPublicID: herd.publicID
      )
    }

    let operation = try await operationCoordinator.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: target.description
    )

    do {
      // Re-check after the operation-journal await and immediately before the first bridge write.
      // This keeps a collaborator change during export preparation from being overwritten.
      let preWriteFingerprint = try await publicIDRepairBridgeFingerprint(
        for: herd,
        expectedLocation: expectedLocation,
        target: target
      )
      guard preWriteFingerprint == expectedFingerprint else {
        throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
          herdPublicID: herd.publicID
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

      let recordsToShare = try publicIDRepairManagedObjects(
        for: writeResult.managedObjectURIs
      )
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

  private func publicIDRepairBridgeTarget(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation
  ) throws -> PublicIDRepairResolvedBridgeTarget {
    let privateRecord = try privateStore.flatMap {
      try fetchSharedHerdRecord(publicID: herd.publicID, in: $0)
    }
    let sharedRecord = try sharedStore.flatMap {
      try fetchSharedHerdRecord(publicID: herd.publicID, in: $0)
    }
    let actualDescription = publicIDRepairActualTargetDescription(
      privateRecordExists: privateRecord != nil,
      sharedRecordExists: sharedRecord != nil
    )

    switch expectedLocation {
    case .ownerPrivateStore:
      guard let privateStore, let privateRecord, sharedRecord == nil else {
        throw HerdSharingPublicIDRepairBridgeError.targetChanged(
          expected: "owner private store",
          actual: actualDescription
        )
      }
      return PublicIDRepairResolvedBridgeTarget(
        store: privateStore,
        description: "owner private store",
        shouldUpdateShare: try existingShare(for: privateRecord) != nil
      )

    case .acceptedSharedStore:
      guard let sharedStore, let sharedRecord, privateRecord == nil else {
        throw HerdSharingPublicIDRepairBridgeError.targetChanged(
          expected: "accepted shared store",
          actual: actualDescription
        )
      }
      let share = try existingShare(for: sharedRecord)
      let permission = share.map { sharingPermission(from: $0) } ?? .unknown
      guard permission == .readWrite || permission == .owner else {
        throw HerdSharingActionError.readOnlyShareCannotWrite
      }
      return PublicIDRepairResolvedBridgeTarget(
        store: sharedStore,
        description: "accepted shared store",
        shouldUpdateShare: false
      )

    case .bridgeRecordMissing:
      guard privateRecord == nil, sharedRecord == nil else {
        throw HerdSharingPublicIDRepairBridgeError.targetChanged(
          expected: "no bridge record yet",
          actual: actualDescription
        )
      }
      guard let privateStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The private sharing bridge store was not loaded."
        )
      }
      return PublicIDRepairResolvedBridgeTarget(
        store: privateStore,
        description: "owner private store",
        shouldUpdateShare: false
      )
    }
  }

  private func publicIDRepairBridgeFingerprint(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation,
    target: PublicIDRepairResolvedBridgeTarget
  ) async throws -> String {
    if expectedLocation == .bridgeRecordMissing {
      return Self.publicIDRepairDigest(
        "missing|\(herd.publicID.uuidString.lowercased())"
      )
    }

    let snapshot = try await readBridgeSnapshot(
      from: target.store,
      requestedHerdPublicID: herd.publicID,
      storeDescription: target.description
    )
    return snapshot.publicIDRepairFingerprint
  }

  private func publicIDRepairActualTargetDescription(
    privateRecordExists: Bool,
    sharedRecordExists: Bool
  ) -> String {
    switch (privateRecordExists, sharedRecordExists) {
    case (true, true):
      return "both owner private and accepted shared stores"
    case (true, false):
      return "owner private store"
    case (false, true):
      return "accepted shared store"
    case (false, false):
      return "no bridge record yet"
    }
  }

  private func publicIDRepairManagedObjects(
    for objectURIs: [String]
  ) throws -> [NSManagedObject] {
    let coordinator = persistentContainer.persistentStoreCoordinator
    let context = persistentContainer.viewContext
    return try objectURIs.compactMap { rawURI in
      guard let url = URL(string: rawURI),
        let objectID = coordinator.managedObjectID(forURIRepresentation: url)
      else { return nil }
      return try context.existingObject(with: objectID)
    }
  }

  nonisolated fileprivate static func publicIDRepairDigest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private extension HerdSharingBridgeStoreSnapshot {
  var publicIDRepairFingerprint: String {
    var components = ["herd|\(herdPublicID.uuidString.lowercased())"]
    for step in HerdSharingBridgeStep.entitySteps {
      let records = records(for: step)
        .map(\.publicIDRepairCanonicalValue)
        .sorted()
      components.append("step|\(step.rawValue)|\(records.count)")
      components.append(contentsOf: records)
    }
    return HerdSharingCoreDataStore.publicIDRepairDigest(
      components.joined(separator: "\n")
    )
  }
}

private extension HerdSharingBridgeRecordSnapshot {
  var publicIDRepairCanonicalValue: String {
    var components = [
      "entity|\(entityName)",
      "publicID|\(publicID.lowercased())",
    ]
    for key in attributes.keys.sorted() {
      guard let value = attributes[key] else { continue }
      components.append("attribute|\(key)|\(value.publicIDRepairCanonicalValue)")
    }
    return components.joined(separator: "\n")
  }
}

private extension HerdSharingBridgeAttributeValue {
  var publicIDRepairCanonicalValue: String {
    switch self {
    case .null:
      return "null"
    case .string(let value):
      return "string|\(Data(value.utf8).base64EncodedString())"
    case .date(let value):
      return "date|\(value.timeIntervalSinceReferenceDate.bitPattern)"
    case .data(let value):
      return "data|\(value.base64EncodedString())"
    case .integer(let value):
      return "integer|\(value)"
    case .double(let value):
      return "double|\(value.bitPattern)"
    case .boolean(let value):
      return value ? "boolean|1" : "boolean|0"
    }
  }
}
