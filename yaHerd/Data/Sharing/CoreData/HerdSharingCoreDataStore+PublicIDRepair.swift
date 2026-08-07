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

private struct PublicIDRepairResolvedBridgeState {
  let target: PublicIDRepairResolvedBridgeTarget
  let snapshot: HerdSharingBridgeStoreSnapshot?
  let fingerprint: String
}

private struct PublicIDRepairBridgeWriteOutcome {
  let snapshot: HerdSharingBridgeStoreSnapshot
  let managedObjectURIs: [String]
}

extension HerdSharingCoreDataStore: PublicIDRepairBridgeStore {
  func publicIDRepairFingerprint(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation
  ) async throws -> String {
    try await loadIfNeeded()
    let state = try await publicIDRepairBridgeState(
      for: herd,
      expectedLocation: expectedLocation,
      allowCreatedOwnerPrivateStore: false
    )
    return state.fingerprint
  }

  func syncPublicIDRepairBridgeRecordsFromSnapshot(
    _ export: HerdSharingSwiftDataExport,
    expectedLocation: HerdSharingAccess.BridgeLocation,
    expectedFingerprint: String
  ) async throws -> HerdSharingBridgeExportResult {
    try await loadIfNeeded()
    let herd = export.herd
    let desiredSnapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: export.snapshot.herdPublicID,
      storeDescription: "public-ID repair desired snapshot",
      recordsByStep: export.snapshot.recordsByStep
    )
    let desiredFingerprint = desiredSnapshot.publicIDRepairFingerprint

    // Resolve the prepared target after the SwiftData export has been built. A bridge can be in
    // only two safe states here: the exact pre-repair live graph, or the exact repaired live graph
    // from an earlier convergence attempt that committed before a crash/journal-clear failure.
    let initialState = try await publicIDRepairBridgeState(
      for: herd,
      expectedLocation: expectedLocation,
      allowCreatedOwnerPrivateStore: true
    )
    try validatePublicIDRepairBridgeState(
      initialState,
      baselineFingerprint: expectedFingerprint,
      desiredFingerprint: desiredFingerprint,
      herdPublicID: herd.publicID
    )

    let operation = try await operationCoordinator.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: initialState.target.description
    )

    do {
      // Re-resolve both the exact store location and its content after the operation-journal
      // await. This prevents normal writable-store fallback and catches a target/content change
      // immediately before the first bridge mutation.
      let preWriteState = try await publicIDRepairBridgeState(
        for: herd,
        expectedLocation: expectedLocation,
        allowCreatedOwnerPrivateStore: true
      )
      try validatePublicIDRepairBridgeState(
        preWriteState,
        baselineFingerprint: expectedFingerprint,
        desiredFingerprint: desiredFingerprint,
        herdPublicID: herd.publicID
      )

      let outcome: PublicIDRepairBridgeWriteOutcome
      if preWriteState.fingerprint == desiredFingerprint {
        guard let currentSnapshot = preWriteState.snapshot else {
          throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
            herdPublicID: herd.publicID
          )
        }
        outcome = PublicIDRepairBridgeWriteOutcome(
          snapshot: currentSnapshot,
          managedObjectURIs: repairSnapshotManagedObjectURIs(
            for: currentSnapshot
          )
        )
      } else {
        let targetSnapshot = HerdSharingBridgeStoreSnapshot(
          herdPublicID: export.snapshot.herdPublicID,
          storeDescription: preWriteState.target.description,
          recordsByStep: export.snapshot.recordsByStep
        )
        let writeResult = try await writeBridgeSnapshot(
          targetSnapshot,
          to: preWriteState.target.store,
          failureInjector: operationCoordinator.backgroundFailureInjector
        )
        guard writeResult.snapshot.publicIDRepairFingerprint == desiredFingerprint else {
          throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
            herdPublicID: herd.publicID
          )
        }
        outcome = PublicIDRepairBridgeWriteOutcome(
          snapshot: writeResult.snapshot,
          managedObjectURIs: writeResult.managedObjectURIs
        )
      }

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
          bridgePublicIDs: outcome.snapshot.publicIDsByStep,
          deletionTombstoneCount: outcome.snapshot.deletionTombstoneCount
        )
      }

      let recordsToShare = try publicIDRepairManagedObjects(
        for: outcome.managedObjectURIs
      )
      guard let herdRecord = recordsToShare.first(where: {
        $0.entity.name == SharedHerdRecord.entityName
          && ($0.value(forKey: "publicID") as? String) == herd.publicID.uuidString
      }) else {
        throw HerdSharingActionError.shareRootMissing
      }

      var didUpdateExistingCloudKitShare = false
      if preWriteState.target.shouldUpdateShare, try existingShare(for: herdRecord) != nil {
        _ = try await operationCoordinator.execute(
          .cloudKitShareUpdate,
          operationID: operation.id
        ) {
          try await shareRecords(recordsToShare, title: herd.name)
        }
        didUpdateExistingCloudKitShare = true
      }

      let finalSnapshot = outcome.snapshot
      let result = HerdSharingBridgeExportResult(
        herdName: herd.name,
        writeTargetDescription: preWriteState.target.description,
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

  private func publicIDRepairBridgeState(
    for herd: HerdSummary,
    expectedLocation: HerdSharingAccess.BridgeLocation,
    allowCreatedOwnerPrivateStore: Bool
  ) async throws -> PublicIDRepairResolvedBridgeState {
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

    let target: PublicIDRepairResolvedBridgeTarget
    let snapshot: HerdSharingBridgeStoreSnapshot?

    switch expectedLocation {
    case .ownerPrivateStore:
      guard let privateStore, let privateRecord, sharedRecord == nil else {
        throw HerdSharingPublicIDRepairBridgeError.targetChanged(
          expected: "owner private store",
          actual: actualDescription
        )
      }
      target = PublicIDRepairResolvedBridgeTarget(
        store: privateStore,
        description: "owner private store",
        shouldUpdateShare: try existingShare(for: privateRecord) != nil
      )
      snapshot = try await readBridgeSnapshot(
        from: privateStore,
        requestedHerdPublicID: herd.publicID,
        storeDescription: target.description
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
      target = PublicIDRepairResolvedBridgeTarget(
        store: sharedStore,
        description: "accepted shared store",
        shouldUpdateShare: false
      )
      snapshot = try await readBridgeSnapshot(
        from: sharedStore,
        requestedHerdPublicID: herd.publicID,
        storeDescription: target.description
      )

    case .bridgeRecordMissing:
      guard sharedRecord == nil else {
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

      if let privateRecord {
        guard allowCreatedOwnerPrivateStore else {
          throw HerdSharingPublicIDRepairBridgeError.targetChanged(
            expected: "no bridge record yet",
            actual: actualDescription
          )
        }
        target = PublicIDRepairResolvedBridgeTarget(
          store: privateStore,
          description: "owner private store",
          shouldUpdateShare: try existingShare(for: privateRecord) != nil
        )
        snapshot = try await readBridgeSnapshot(
          from: privateStore,
          requestedHerdPublicID: herd.publicID,
          storeDescription: target.description
        )
      } else {
        target = PublicIDRepairResolvedBridgeTarget(
          store: privateStore,
          description: "owner private store",
          shouldUpdateShare: false
        )
        snapshot = nil
      }
    }

    let fingerprint = snapshot?.publicIDRepairFingerprint
      ?? Self.publicIDRepairDigest(
        "missing|\(herd.publicID.uuidString.lowercased())"
      )
    return PublicIDRepairResolvedBridgeState(
      target: target,
      snapshot: snapshot,
      fingerprint: fingerprint
    )
  }

  private func validatePublicIDRepairBridgeState(
    _ state: PublicIDRepairResolvedBridgeState,
    baselineFingerprint: String,
    desiredFingerprint: String,
    herdPublicID: UUID
  ) throws {
    guard state.fingerprint == baselineFingerprint
      || state.fingerprint == desiredFingerprint
    else {
      throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
        herdPublicID: herdPublicID
      )
    }
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

  private func repairSnapshotManagedObjectURIs(
    for snapshot: HerdSharingBridgeStoreSnapshot
  ) -> [String] {
    HerdSharingBridgeStep.entitySteps
      .filter { $0 != .deletions }
      .flatMap { step in
        snapshot.records(for: step).map(\.sourceObjectURI)
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

extension HerdSharingBridgeStoreSnapshot {
  /// Stable fingerprint of the live shared graph. Deletion tombstones are intentionally excluded:
  /// the repair writer can create tombstones for replaced IDs, and their revision/timestamp metadata
  /// is generated at commit time. `lastMirroredAt` is transport bookkeeping and changes on every
  /// export. All live entity IDs, domain attributes, and collaboration revision metadata remain in
  /// the fingerprint, so collaborator additions, edits, or deletions of live records still change it.
  var publicIDRepairFingerprint: String {
    var components = ["herd|\(herdPublicID.uuidString.lowercased())"]
    for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
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
    for key in attributes.keys.sorted() where key != "lastMirroredAt" {
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
