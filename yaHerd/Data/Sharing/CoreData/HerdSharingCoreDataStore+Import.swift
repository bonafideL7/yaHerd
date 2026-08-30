//
//  HerdSharingCoreDataStore+Import.swift
//  yaHerd
//

import CloudKit
@preconcurrency import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func importSharedRecordsIntoSwiftData(
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    do {
      try await loadIfNeeded()

      if acceptedShareImportScopeStore.hasCorruptPersistedState {
        try acceptedShareImportScopeStore.backupAndResetCorruptStateForRecovery()
      }
      if acceptedShareImportScopeStore.hasCorruptRecoveryPending {
        return try await recoverCorruptAcceptedInvitationState(importer: importer)
      }

      let pendingScopes = try await recoverPendingAcceptedShareScopes()

      // An invitation accepted by this live store instance must import that exact CloudKit root.
      // Do not fall through to an older pending scope merely because its records arrived first.
      if let immediateScope = acceptedShareImportScopeStore.immediateImportScope,
         let activeImmediateScope = pendingScopes.first(where: {
           Self.sameAcceptedShareScope($0, immediateScope)
         })
      {
        guard let scopedImport = try acceptedShareImport(matching: activeImmediateScope) else {
          throw HerdSharingActionError.bridgeImportFailed(
            "The newly accepted CloudKit invitation is recorded, but its exact shared Herd root has not arrived in the Core Data bridge yet. No other accepted Herd was imported. Try Import Shared Data again after CloudKit finishes syncing."
          )
        }
        let result = try await performBridgeImport(
          for: nil,
          access: nil,
          requestedHerdPublicID: scopedImport.herdPublicID,
          participantRelationshipWasExplicitlyAccepted: true,
          importer: importer
        )
        try acceptedShareImportScopeStore.removeRecoverably(scopedImport.scope)
        return result
      }

      // After process recreation there is no live acceptance call to bind. Resume any durable
      // pending invitation whose exact root is present, while still refusing arbitrary roots.
      if let scopedImport = try nextPendingAcceptedShareImport(from: pendingScopes) {
        let result = try await performBridgeImport(
          for: nil,
          access: nil,
          requestedHerdPublicID: scopedImport.herdPublicID,
          participantRelationshipWasExplicitlyAccepted: true,
          importer: importer
        )
        try acceptedShareImportScopeStore.removeRecoverably(scopedImport.scope)
        return result
      }
      if !pendingScopes.isEmpty {
        throw HerdSharingActionError.bridgeImportFailed(
          "The accepted CloudKit invitation is recorded, but its exact shared Herd root has not arrived in the Core Data bridge yet. No other accepted Herd was imported. Try Import Shared Data again after CloudKit finishes syncing."
        )
      }

      return try await performBridgeImport(
        for: nil,
        access: nil,
        importer: importer
      )
    } catch {
      throw Self.unscopedImportBoundaryError(error)
    }
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

  func importAcceptedBridgeRecordsIntoSwiftData(
    for herdPublicID: UUID,
    importer: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    do {
      return try await performBridgeImport(
        for: nil,
        access: nil,
        requestedHerdPublicID: herdPublicID,
        importer: importer
      )
    } catch {
      throw Self.unscopedImportBoundaryError(error)
    }
  }

  func acceptedHerdPublicID(
    matching scope: HerdSharingAcceptedShareImportScope,
    in store: NSPersistentStore,
    recordIDProvider: ((NSManagedObjectID) -> CKRecord.ID?)? = nil
  ) throws -> UUID? {
    let provider = recordIDProvider ?? { [self] objectID in
      acceptedShareRecordID(for: objectID)
    }
    let matchingRecords = try fetchSharedHerdRecords(in: store).filter { record in
      guard let recordID = provider(record.objectID) else { return false }
      return recordID.recordName == scope.rootRecordName
        && recordID.zoneID.zoneName == scope.rootZoneName
        && recordID.zoneID.ownerName == scope.rootZoneOwnerName
    }

    guard matchingRecords.count <= 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Multiple shared Herd roots resolved to the same accepted CloudKit invitation. No participant provenance was recorded."
      )
    }
    guard let matchingRecord = matchingRecords.first else { return nil }
    guard let publicIDString = matchingRecord.publicID,
          let publicID = UUID(uuidString: publicIDString)
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd root for the accepted CloudKit invitation has no valid public ID. No participant provenance was recorded."
      )
    }
    return publicID
  }

  private func recoverCorruptAcceptedInvitationState(
    importer _: any HerdSharingImportApplying
  ) async throws -> HerdSharingBridgeImportResult {
    throw HerdSharingActionError.bridgeConsistencyFailed(
      "The corrupt CloudKit invitation state was backed up, but its exact invitation identity was lost. yaHerd will not infer the pending invitation from currently visible shared Herd roots. Reopen the original CloudKit share invitation so its exact root, zone, owner, and participant account can be recorded before recovery continues."
    )
  }

  private func recoverPendingAcceptedShareScopes() async throws
    -> [HerdSharingAcceptedShareImportScope]
  {
    let activeScopes = try await acceptedShareImportScopeStore.pendingScopesForCurrentAccount()
    for scope in activeScopes {
      // A matching local row proves only that Core Data cached this exact root previously. The
      // owner may have revoked participation since that cache was written, so every pending scope
      // must be revalidated against the current CloudKit account before it can be imported.
      let remoteStatus = try await acceptedParticipantRemoteVerifier.status(
        for: HerdSharingAcceptedParticipantReference(scope: scope)
      )
      switch remoteStatus {
      case .present:
        if scope.acceptanceState != .accepted {
          let accountRecordName: String
          if let participantAccountRecordName = scope.participantAccountRecordName {
            accountRecordName = participantAccountRecordName
          } else {
            accountRecordName = try await acceptedShareImportScopeStore.currentAccountRecordName()
          }
          acceptedShareImportScopeStore.markAccepted(
            scope,
            participantAccountRecordName: accountRecordName
          )
        }
        if scope.remoteAbsenceObservedAt != nil {
          acceptedShareImportScopeStore.clearRemoteAbsence(for: scope)
        }

      case .absent:
        let now = nowProvider()
        if let observedAt = scope.remoteAbsenceObservedAt,
           now.timeIntervalSince(observedAt) >= acceptedScopeRemoteAbsenceConfirmationInterval
        {
          if scope.acceptanceState == .legacyUnknown {
            let accountRecordName = try await acceptedShareImportScopeStore.currentAccountRecordName()
            acceptedShareImportScopeStore.retireLegacyScope(
              scope,
              forParticipantAccount: accountRecordName
            )
          } else {
            try acceptedShareImportScopeStore.removeRecoverably(scope)
          }
          throw HerdSharingActionError.bridgeImportFailed(
            "The retained CloudKit invitation scope was remotely verified again and no accepted Herd root exists for this iCloud account. The stale recovery scope was retired for this account. Retry the requested import or synchronization."
          )
        }

        acceptedShareImportScopeStore.recordRemoteAbsence(for: scope, at: now)
        throw HerdSharingActionError.bridgeImportFailed(
          "The retained CloudKit invitation scope has no accepted Herd root in this iCloud account yet. yaHerd kept the scope fail-closed and will verify remote absence again on a later retry before clearing it."
        )
      }
    }

    return try await acceptedShareImportScopeStore.pendingScopesForCurrentAccount()
  }

  private func acceptedShareImport(
    matching scope: HerdSharingAcceptedShareImportScope
  ) throws -> (scope: HerdSharingAcceptedShareImportScope, herdPublicID: UUID)? {
    guard let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The shared CloudKit bridge store was not loaded."
      )
    }
    guard let herdPublicID = try acceptedHerdPublicID(
      matching: scope,
      in: sharedStore
    ) else {
      return nil
    }
    return (scope, herdPublicID)
  }

  private func nextPendingAcceptedShareImport(
    from scopes: [HerdSharingAcceptedShareImportScope]
  ) throws -> (scope: HerdSharingAcceptedShareImportScope, herdPublicID: UUID)? {
    for scope in scopes {
      if let scopedImport = try acceptedShareImport(matching: scope) {
        return scopedImport
      }
    }
    return nil
  }

  private func performBridgeImport(
    for requestedHerd: HerdSummary?,
    access: HerdSharingAccess?,
    requestedHerdPublicID: UUID? = nil,
    participantRelationshipWasExplicitlyAccepted: Bool = false,
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
        requestedHerdPublicID: requestedHerd?.publicID ?? requestedHerdPublicID,
        storeDescription: source.description
      )
    } catch {
      throw Self.importBoundaryError(
        error,
        requestedHerd: requestedHerd,
        sourceDescription: source.description
      )
    }

    // Once an accepted shared-store snapshot exposes the stable Herd public ID, the participant
    // relationship has crossed the durable CloudKit acceptance boundary. Persist both the exact
    // shared root/account reference and the ownership marker before revision hydration, journal
    // creation, or SwiftData application so process termination or any started-import failure
    // cannot strand a retained Herd without the provenance required for safe remote detachment.
    // Only a durable invitation-scope import may deliberately supersede a previous detach tombstone;
    // ordinary access/backfill and unscoped imports remain monotonic and fail closed.
    if source.recordsAcceptedParticipantProvenance {
      try await persistAcceptedParticipantReference(
        for: snapshot.herdPublicID,
        in: source.store,
        explicitlyAccepted: participantRelationshipWasExplicitlyAccepted
      )
      acceptedParticipantProvenanceRecorder(snapshot.herdPublicID)
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
      throw Self.startedImportBoundaryError(
        committedFailure.underlyingError,
        requestedHerd: requestedHerd
      )
    } catch {
      await operationCoordinator.fail(operationID: operation.id, error: error)
      throw Self.startedImportBoundaryError(
        error,
        requestedHerd: requestedHerd
      )
    }
  }

  private func persistAcceptedParticipantReference(
    for herdPublicID: UUID,
    in sharedStore: NSPersistentStore,
    explicitlyAccepted: Bool
  ) async throws {
    let matchingRecords = try fetchSharedHerdRecords(
      publicID: herdPublicID,
      in: sharedStore
    )
    guard matchingRecords.count <= 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Multiple accepted shared Herd roots have the same public ID. Participant provenance was not committed."
      )
    }
    guard let sharedHerdRecord = matchingRecords.first,
          let rootRecordID = acceptedShareRecordID(for: sharedHerdRecord.objectID)
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted shared Herd root has no exact CloudKit record identity. Participant provenance was not committed."
      )
    }

    let participantAccountRecordName = try await acceptedShareImportScopeStore
      .currentAccountRecordName()
    let currentMatchingRecords = try fetchSharedHerdRecords(
      publicID: herdPublicID,
      in: sharedStore
    )
    guard currentMatchingRecords.count == 1,
          let currentRecord = currentMatchingRecords.first,
          acceptedShareRecordID(for: currentRecord.objectID) == rootRecordID
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted shared Herd root changed while participant provenance was being prepared. Participant provenance was not committed."
      )
    }

    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordID: rootRecordID,
      participantAccountRecordName: participantAccountRecordName
    )
    let savedReference: HerdSharingAcceptedParticipantReference?
    let hasConflictingSavedReference: Bool
    do {
      savedReference = try recoverableAcceptedParticipantReference(for: herdPublicID)
      hasConflictingSavedReference = false
    } catch {
      guard hasConflictingAcceptedParticipantReference(for: herdPublicID) else {
        throw error
      }
      savedReference = nil
      hasConflictingSavedReference = true
    }
    if let savedReference, savedReference != reference {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The retained accepted-share provenance identifies a different CloudKit Herd root or participant account. Participant provenance was not replaced."
      )
    }
    if hasConflictingSavedReference {
      guard case .present(let permission) = try await acceptedParticipantRemoteVerifier.status(
        for: reference
      ), permission == .readWrite || permission == .readOnly else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The exact accepted shared Herd could not be verified remotely. Conflicting participant provenance was not replaced."
        )
      }
      let remotelyVerifiedRecords = try fetchSharedHerdRecords(
        publicID: herdPublicID,
        in: sharedStore
      )
      guard remotelyVerifiedRecords.count == 1,
            let remotelyVerifiedRecord = remotelyVerifiedRecords.first,
            acceptedShareRecordID(for: remotelyVerifiedRecord.objectID) == rootRecordID
      else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted shared Herd root changed during authoritative provenance recovery. Conflicting participant provenance was not replaced."
        )
      }
      try replaceConflictingAcceptedParticipantReferenceRecoverably(
        reference,
        for: herdPublicID
      )
    } else if savedReference == nil {
      try recordAcceptedParticipantReferenceRecoverably(
        reference,
        for: herdPublicID,
        explicitlyAccepted: explicitlyAccepted
      )
    }
    guard try recoverableAcceptedParticipantReference(for: herdPublicID) == reference else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted shared Herd reference could not be persisted durably. Participant ownership was not committed."
      )
    }
  }

  private func recoverableAcceptedParticipantReference(
    for herdPublicID: UUID
  ) throws -> HerdSharingAcceptedParticipantReference? {
    if let acceptedParticipantReferenceStore {
      return try acceptedParticipantReferenceStore.recoverableReference(for: herdPublicID)
    }
    return try acceptedShareImportScopeStore.participantReference(for: herdPublicID)
  }

  private func hasConflictingAcceptedParticipantReference(for herdPublicID: UUID) -> Bool {
    if let acceptedParticipantReferenceStore {
      return acceptedParticipantReferenceStore.hasConflictingReference(for: herdPublicID)
    }
    return acceptedShareImportScopeStore.hasConflictingParticipantReference(for: herdPublicID)
  }

  private func replaceConflictingAcceptedParticipantReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    if let acceptedParticipantReferenceStore {
      try acceptedParticipantReferenceStore.replaceConflictingReferenceRecoverably(
        reference,
        for: herdPublicID
      )
      return
    }
    try acceptedShareImportScopeStore.replaceConflictingParticipantReferenceRecoverably(
      reference,
      for: herdPublicID
    )
  }

  private func recordAcceptedParticipantReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID,
    explicitlyAccepted: Bool
  ) throws {
    if let durableStore = acceptedParticipantReferenceStore
      as? any HerdSharingAcceptedParticipantReferenceDurablyRecording
    {
      if explicitlyAccepted {
        try durableStore.recordExplicitlyAcceptedRecoverably(reference, for: herdPublicID)
      } else {
        try durableStore.recordRecoverably(reference, for: herdPublicID)
      }
      return
    }

    if let acceptedParticipantReferenceStore {
      acceptedParticipantReferenceStore.record(reference, for: herdPublicID)
      guard try acceptedParticipantReferenceStore.recoverableReference(for: herdPublicID) == reference else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted shared Herd reference could not be persisted durably. Participant ownership was not committed."
        )
      }
      return
    }

    acceptedShareImportScopeStore.recordParticipantReference(
      rootRecordID: reference.rootRecordID,
      participantAccountRecordName: reference.participantAccountRecordName,
      for: herdPublicID
    )
    guard try acceptedShareImportScopeStore.participantReference(for: herdPublicID) == reference else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted shared Herd reference could not be persisted durably. Participant ownership was not committed."
      )
    }
  }

  nonisolated static func unscopedImportBoundaryError(_ error: Error) -> Error {
    if let actionError = error as? HerdSharingActionError {
      switch actionError {
      case .bridgeImportFailed, .bridgeImportRequiresAccessVerification:
        return actionError
      default:
        break
      }
    }

    return HerdSharingActionError.bridgeImportRequiresAccessVerification(
      error.localizedDescription
    )
  }

  nonisolated static func unscopedStartedImportBoundaryError(_ error: Error) -> Error {
    startedImportBoundaryError(error, requestedHerd: nil)
  }

  nonisolated private static func startedImportBoundaryError(
    _ error: Error,
    requestedHerd: HerdSummary?
  ) -> Error {
    guard requestedHerd == nil else { return error }
    if let actionError = error as? HerdSharingActionError,
       case .bridgeImportRequiresAccessVerification = actionError
    {
      return actionError
    }
    return HerdSharingActionError.bridgeImportRequiresAccessVerification(
      error.localizedDescription
    )
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
  ) throws -> (
    store: NSPersistentStore,
    description: String,
    recordsAcceptedParticipantProvenance: Bool
  ) {
    guard let herd, let access else {
      guard let sharedStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The shared CloudKit bridge store was not loaded."
        )
      }
      return (sharedStore, "accepted shared store", true)
    }

    switch access.bridgeLocation {
    case .ownerPrivateStore:
      guard let privateStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The private sharing bridge store was not loaded."
        )
      }
      return (privateStore, "owner private store", false)
    case .acceptedSharedStore:
      guard let sharedStore else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The shared CloudKit bridge store was not loaded."
        )
      }
      return (sharedStore, "accepted shared store", true)
    case .bridgeRecordMissing:
      throw HerdSharingActionError.bridgeImportFailed(
        "No bridge record exists for \(herd.name)."
      )
    }
  }

  nonisolated static func sameAcceptedShareScope(
    _ lhs: HerdSharingAcceptedShareImportScope,
    _ rhs: HerdSharingAcceptedShareImportScope
  ) -> Bool {
    lhs.rootRecordID == rhs.rootRecordID
  }
}
