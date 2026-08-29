//
//  HerdSharingCoreDataStore+Access.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func fetchSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess {
    try await loadIfNeeded()

    let privateHerdRecord = try privateStore.flatMap { store in
      try fetchUniqueSharingHerdRecord(
        publicID: herd.publicID,
        in: store,
        storeDescription: "owner private bridge store"
      )
    }
    let sharedHerdRecord = try sharedStore.flatMap { store in
      try fetchUniqueSharingHerdRecord(
        publicID: herd.publicID,
        in: store,
        storeDescription: "accepted shared store"
      )
    }

    let remotelyVerifiedParticipantPermission: HerdSharingAccess.Permission?
    if let sharedHerdRecord,
       let rootRecordID = acceptedShareRecordID(for: sharedHerdRecord.objectID)
    {
      remotelyVerifiedParticipantPermission = try await verifyAcceptedParticipantRelationship(
        herdPublicID: herd.publicID,
        sharedHerdRecord: sharedHerdRecord,
        rootRecordID: rootRecordID,
        verifyMatchingSavedReference: privateHerdRecord == nil
      )
    } else {
      remotelyVerifiedParticipantPermission = nil
    }

    if let permission = remotelyVerifiedParticipantPermission,
       permission == .readWrite || permission == .readOnly
    {
      // This is the account-aware migration boundary for legacy device-local participant lineage.
      // Never mirror a UserDefaults participant marker into the current iCloud account before the
      // exact accepted root and participant permission have been verified remotely.
      acceptedParticipantProvenanceRecorder(herd.publicID)
    }

    if let privateHerdRecord, let sharedHerdRecord {
      let ownerShare = try existingShare(for: privateHerdRecord)
      let participantShare = try existingShare(for: sharedHerdRecord)
      return .conflictingStores(
        ownerHasActiveSystemShare: ownerShare != nil,
        participantCount: participantShare?.participants.count
      )
    }

    if let privateHerdRecord {
      let share = try existingShare(for: privateHerdRecord)
      return .ownerPrivateStore(
        participantCount: share?.participants.count,
        hasActiveSystemShare: share != nil
      )
    }

    if let sharedHerdRecord {
      let share = try existingShare(for: sharedHerdRecord)
      return .acceptedSharedStore(
        permission: remotelyVerifiedParticipantPermission ?? .unknown,
        participantCount: share?.participants.count
      )
    }

    return .localOwnerBridgePending
  }

  func existingOwnerSystemShare(for herd: HerdSummary) async throws -> CloudKitSystemShare {
    let access = try await fetchSharingAccess(for: herd)
    guard !access.hasConflictingBridgeRecords,
      access.bridgeLocation == .ownerPrivateStore,
      access.hasActiveSystemShare,
      let privateStore
    else {
      throw HerdSharingActionError.shareManagementUnavailable
    }

    guard let herdRecord = try fetchUniqueSharingHerdRecord(
      publicID: herd.publicID,
      in: privateStore,
      storeDescription: "owner private bridge store"
    ), let share = try existingShare(for: herdRecord) else {
      throw HerdSharingActionError.shareManagementUnavailable
    }

    return CloudKitSystemShare(
      title: herd.name,
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

  func writableBridgeStore(for herd: HerdSummary) async throws -> (
    store: NSPersistentStore,
    description: String,
    shouldUpdateShare: Bool
  ) {
    let verifiedAccess = try await fetchSharingAccess(for: herd)
    let privateHerdRecord = try privateStore.flatMap { store in
      try fetchUniqueSharingHerdRecord(
        publicID: herd.publicID,
        in: store,
        storeDescription: "owner private bridge store"
      )
    }
    let sharedHerdRecord = try sharedStore.flatMap { store in
      try fetchUniqueSharingHerdRecord(
        publicID: herd.publicID,
        in: store,
        storeDescription: "accepted shared store"
      )
    }

    guard privateHerdRecord == nil || sharedHerdRecord == nil else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd root exists in both the owner private bridge store and the accepted shared store. Resolve the conflicting bridge records before exporting changes."
      )
    }

    if let privateStore, let privateHerdRecord {
      let hasExistingShare = try existingShare(for: privateHerdRecord) != nil
      return (privateStore, "owner private store", hasExistingShare)
    }

    if let sharedStore, sharedHerdRecord != nil {
      guard verifiedAccess.bridgeLocation == .acceptedSharedStore,
            verifiedAccess.permission == .readWrite
      else {
        throw HerdSharingActionError.readOnlyShareCannotWrite
      }
      return (sharedStore, "accepted shared store", false)
    }

    guard let privateStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The private sharing bridge store was not loaded.")
    }

    return (privateStore, "owner private store", false)
  }

  func acceptShareInvitation(metadata: CKShare.Metadata) async throws {
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("HerdSharingCoreDataStore.acceptShareInvitation.started")
    defer {
      PerformanceLog.logDuration(
        "HerdSharingCoreDataStore.acceptShareInvitation", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("HerdSharingCoreDataStore.acceptShareInvitation.finished")
    }
    try await loadIfNeeded()
    let participantAccountRecordName = try await acceptedShareImportScopeStore.currentAccountRecordName(
      allowingCorruptRecovery: true
    )
    let acceptedScope = try HerdSharingAcceptedShareImportScope(
      metadata: metadata,
      participantAccountRecordName: participantAccountRecordName
    )

    guard let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The shared CloudKit bridge store was not loaded.")
    }

    // Capture the current account-level detachment generation before CloudKit acceptance begins.
    // A later import may clear a participant-retirement tombstone only when this exact invitation
    // was deliberately accepted after that same detach generation. Older pending invitations remain
    // fail-closed across process recreation and cross-device detach races.
    if let acceptanceRecorder = acceptedParticipantReferenceStore
      as? any HerdSharingAcceptedParticipantExplicitAcceptanceRecording
    {
      try acceptanceRecorder.recordExplicitAcceptanceBoundary(
        for: HerdSharingAcceptedParticipantReference(scope: acceptedScope)
      )
    }

    try await commitAcceptedShareInvitationScope(acceptedScope) {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        persistentContainer.acceptShareInvitations(
          from: [metadata],
          into: sharedStore
        ) { _, error in
          if let error {
            continuation.resume(
              throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  /// Records the exact invitation root before CloudKit acceptance begins. Once the acceptance
  /// request has started, any returned error is commit-ambiguous: the server may have accepted the
  /// participant relationship even if local processing or the response failed. Retain the scope so
  /// recovery can verify that exact root remotely rather than falling back to the previously current
  /// Herd, and require sharing-access verification before local writes resume.
  func commitAcceptedShareInvitationScope(
    _ acceptedScope: HerdSharingAcceptedShareImportScope,
    acceptance: @MainActor () async throws -> Void
  ) async throws {
    // Exact invitation metadata is also the recovery authority for a previously backed-up corrupt
    // scope. The scope store preserves the old bytes before replacing lost identity.
    try acceptedShareImportScopeStore.record(acceptedScope)

    do {
      try await acceptance()
      acceptedShareImportScopeStore.markAccepted(acceptedScope)
    } catch {
      throw HerdSharingActionError.bridgeImportRequiresAccessVerification(
        "CloudKit invitation acceptance returned an error after the acceptance request began. The exact invitation scope was retained because the participant relationship may already have committed. \(error.localizedDescription)"
      )
    }
  }

  private func fetchUniqueSharingHerdRecord(
    publicID: UUID,
    in store: NSPersistentStore,
    storeDescription: String
  ) throws -> SharedHerdRecord? {
    let records = try fetchSharedHerdRecords(publicID: publicID, in: store)
    guard records.count <= 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Multiple Herd bridge roots with public ID \(publicID.uuidString) exist in the \(storeDescription). Repair duplicate bridge records before sharing or synchronization."
      )
    }
    return records.first
  }
}

@MainActor
protocol HerdSharingBridgeConflictResolving: AnyObject {
  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution
  ) async throws -> HerdSharingAccess

  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    discardedRelationshipDidCommit: @escaping @MainActor () -> Void
  ) async throws -> HerdSharingAccess
}

extension HerdSharingBridgeConflictResolving {
  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    discardedRelationshipDidCommit: @escaping @MainActor () -> Void
  ) async throws -> HerdSharingAccess {
    try await resolveBridgeConflict(for: herd, keeping: resolution)
  }
}

extension HerdSharingCoreDataStore: HerdSharingBridgeConflictResolving {
  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution
  ) async throws -> HerdSharingAccess {
    try await resolveBridgeConflict(
      for: herd,
      keeping: resolution,
      discardedRelationshipDidCommit: {}
    )
  }

  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    discardedRelationshipDidCommit: @escaping @MainActor () -> Void
  ) async throws -> HerdSharingAccess {
    try await loadIfNeeded()

    guard let privateStore, let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "Both owner and accepted shared stores must be loaded before resolving a bridge conflict."
      )
    }

    let ownerRecord = try uniqueConflictHerdRecord(
      publicID: herd.publicID,
      in: privateStore,
      storeDescription: "owner private bridge store"
    )
    let acceptedRecord = try uniqueConflictHerdRecord(
      publicID: herd.publicID,
      in: sharedStore,
      storeDescription: "accepted shared store"
    )
    guard let ownerRecord, let acceptedRecord else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd root is no longer present in both bridge stores. Refresh sharing access before choosing a conflict resolution."
      )
    }

    let ownerShare = try existingShare(for: ownerRecord)
    let acceptedShare = try existingShare(for: acceptedRecord)

    switch resolution {
    case .keepOwnerShare:
      if let acceptedShare {
        try await purgeConflictZone(
          share: acceptedShare,
          store: sharedStore,
          description: "accepted shared bridge"
        )
      } else if let acceptedRootRecordID = acceptedShareRecordID(for: acceptedRecord.objectID) {
        let remoteStatus = try await verifyAcceptedParticipantRelationshipForDiscard(
          sharedHerdRecord: acceptedRecord,
          rootRecordID: acceptedRootRecordID
        )
        let zoneID = try HerdSharingAcceptedConflictDiscardPlan.zoneID(
          for: acceptedRootRecordID,
          remoteStatus: remoteStatus
        )
        try await purgeConflictZone(
          zoneID: zoneID,
          store: sharedStore,
          description: "accepted shared bridge"
        )
      } else if !isCloudKitBacked(store: sharedStore) {
        // Plain non-CloudKit stores are used by deterministic local integration tests. They cannot
        // propagate participant writes, so exact graph deletion remains safe there. Production
        // shared stores are CloudKit-backed and always fail closed instead of taking this path.
        try await deleteOrphanConflictBridgeGraph(
          herdPublicID: herd.publicID,
          store: sharedStore,
          storeDescription: "orphan accepted shared bridge"
        )
      } else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted shared Herd root has no exact CloudKit record identity. The participant relationship cannot be discarded safely while keeping the owner share."
        )
      }
      discardedRelationshipDidCommit()

    case .keepAcceptedShare:
      guard let acceptedShare else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted shared Herd root has no CloudKit share metadata and cannot be retained as the active participant relationship. Keep the owner bridge or repair the accepted share first."
        )
      }
      _ = acceptedShare
      guard let acceptedRootRecordID = acceptedShareRecordID(for: acceptedRecord.objectID) else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted shared Herd root has no exact CloudKit record identity and cannot be verified before discarding the owner bridge."
        )
      }
      _ = try await verifyAcceptedParticipantRelationship(
        herdPublicID: herd.publicID,
        sharedHerdRecord: acceptedRecord,
        rootRecordID: acceptedRootRecordID,
        verifyMatchingSavedReference: true
      )
      if let ownerShare {
        try await purgeConflictZone(
          share: ownerShare,
          store: privateStore,
          description: "owner private bridge"
        )
      } else {
        try await deleteOrphanConflictBridgeGraph(
          herdPublicID: herd.publicID,
          store: privateStore,
          storeDescription: "owner private bridge"
        )
      }
      discardedRelationshipDidCommit()
    }

    let access = try await fetchSharingAccess(for: herd)
    guard !access.hasConflictingBridgeRecords,
      access.bridgeLocation == resolution.retainedLocation
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The selected bridge relationship did not become the sole surviving Herd root after conflict resolution."
      )
    }
    return access
  }

  private func verifyAcceptedParticipantRelationshipForDiscard(
    sharedHerdRecord: SharedHerdRecord,
    rootRecordID: CKRecord.ID
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    let participantAccountRecordName = try await acceptedShareImportScopeStore
      .currentAccountRecordName()
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordID: rootRecordID,
      participantAccountRecordName: participantAccountRecordName
    )
    let remoteStatus = try await acceptedParticipantRemoteVerifier.status(for: reference)
    guard acceptedShareRecordID(for: sharedHerdRecord.objectID) == rootRecordID else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted Herd root changed during CloudKit verification. No bridge relationship was discarded."
      )
    }
    return remoteStatus
  }

  private func verifyAcceptedParticipantRelationship(
    herdPublicID: UUID,
    sharedHerdRecord: SharedHerdRecord,
    rootRecordID: CKRecord.ID,
    verifyMatchingSavedReference: Bool
  ) async throws -> HerdSharingAccess.Permission? {
    let participantAccountRecordName = try await acceptedShareImportScopeStore
      .currentAccountRecordName()
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordID: rootRecordID,
      participantAccountRecordName: participantAccountRecordName
    )
    let savedReference: HerdSharingAcceptedParticipantReference?
    let hasConflictingSavedReference: Bool
    do {
      savedReference = try acceptedShareImportScopeStore.participantReference(
        for: herdPublicID
      )
      hasConflictingSavedReference = false
    } catch {
      guard acceptedShareImportScopeStore.hasConflictingParticipantReference(
        for: herdPublicID
      ) else {
        throw error
      }
      savedReference = nil
      hasConflictingSavedReference = true
    }
    guard verifyMatchingSavedReference || savedReference != reference
      || hasConflictingSavedReference
    else { return nil }

    let remoteStatus = try await acceptedParticipantRemoteVerifier.status(for: reference)
    guard case .present(let permission) = remoteStatus else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted Herd root is no longer available to the current iCloud account. The cached participant relationship was not trusted."
      )
    }
    guard permission == .readWrite || permission == .readOnly else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted Herd relationship did not expose an authoritative participant permission. The cached participant relationship was not trusted."
      )
    }
    guard acceptedShareRecordID(for: sharedHerdRecord.objectID) == rootRecordID else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted Herd root changed during CloudKit verification. No bridge relationship was discarded."
      )
    }

    if hasConflictingSavedReference {
      try acceptedShareImportScopeStore.replaceConflictingParticipantReferenceRecoverably(
        reference,
        for: herdPublicID
      )
    } else {
      // Re-record even when the device-local reference already matched. The injected production
      // store mirrors to iCloud only at this point, after exact account/root verification, which
      // migrates legacy local provenance without contaminating a newly signed-in account.
      acceptedShareImportScopeStore.recordParticipantReference(
        rootRecordID: rootRecordID,
        participantAccountRecordName: participantAccountRecordName,
        for: herdPublicID
      )
    }
    guard try acceptedShareImportScopeStore.participantReference(for: herdPublicID) == reference else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The verified accepted Herd reference could not be persisted durably. No bridge relationship was discarded."
      )
    }
    return permission
  }

  private func uniqueConflictHerdRecord(
    publicID: UUID,
    in store: NSPersistentStore,
    storeDescription: String
  ) throws -> SharedHerdRecord? {
    let records = try fetchSharedHerdRecords(publicID: publicID, in: store)
    guard records.count <= 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Multiple Herd bridge roots with public ID \(publicID.uuidString) exist in the \(storeDescription). Repair duplicate bridge records before resolving store ownership."
      )
    }
    return records.first
  }

  private func purgeConflictZone(
    share: CKShare,
    store: NSPersistentStore,
    description: String
  ) async throws {
    try await purgeConflictZone(
      zoneID: share.recordID.zoneID,
      store: store,
      description: description
    )
  }

  private func purgeConflictZone(
    zoneID: CKRecordZone.ID,
    store: NSPersistentStore,
    description: String
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      persistentContainer.purgeObjectsAndRecordsInZone(
        with: zoneID,
        in: store
      ) { _, error in
        if let error {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(
              "Could not stop the \(description): \(error.localizedDescription)"
            )
          )
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private func isCloudKitBacked(store: NSPersistentStore) -> Bool {
    guard let storeURL = store.url,
          let description = persistentContainer.persistentStoreDescriptions.first(where: {
            $0.url?.standardizedFileURL == storeURL.standardizedFileURL
          })
    else {
      return true
    }
    return description.cloudKitContainerOptions != nil
  }

  func deleteOrphanConflictBridgeGraph(
    herdPublicID: UUID,
    store: NSPersistentStore,
    storeDescription: String
  ) async throws {
    guard let storeURL = store.url else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The \(storeDescription) has no persistent URL."
      )
    }

    let context = persistentContainer.newBackgroundContext()
    context.name = "HerdSharingBridge.ConflictResolution"
    context.undoManager = nil
    context.mergePolicy = NSMergePolicy(
      merge: .mergeByPropertyObjectTrumpMergePolicyType
    )
    context.transactionAuthor = "yaHerd.bridge.conflictResolution"

    try await context.perform {
      guard let targetStore = context.persistentStoreCoordinator?.persistentStores.first(where: {
        $0.url?.standardizedFileURL == storeURL.standardizedFileURL
      }) else {
        throw HerdSharingActionError.sharingStoreUnavailable(
          "The exact \(storeDescription) could not be resolved for conflict cleanup."
        )
      }

      for step in HerdSharingBridgeStep.entitySteps.reversed() {
        guard let entityName = step.coreDataEntityName else { continue }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.affectedStores = [targetStore]
        if step == .herd {
          request.predicate = NSPredicate(
            format: "publicID == %@",
            herdPublicID.uuidString
          )
        } else {
          request.predicate = NSPredicate(
            format: "herdPublicID == %@",
            herdPublicID.uuidString
          )
        }
        for record in try context.fetch(request) {
          context.delete(record)
        }
      }

      if context.hasChanges {
        try context.save()
      }

      guard try Self.conflictResolutionRecordCount(
        herdPublicID: herdPublicID,
        in: context,
        store: targetStore
      ) == 0 else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The discarded \(storeDescription) still contains records for the Herd root."
        )
      }
    }
  }

  nonisolated private static func conflictResolutionRecordCount(
    herdPublicID: UUID,
    in context: NSManagedObjectContext,
    store: NSPersistentStore
  ) throws -> Int {
    var count = 0
    for step in HerdSharingBridgeStep.entitySteps {
      guard let entityName = step.coreDataEntityName else { continue }
      let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
      request.affectedStores = [store]
      if step == .herd {
        request.predicate = NSPredicate(
          format: "publicID == %@",
          herdPublicID.uuidString
        )
      } else {
        request.predicate = NSPredicate(
          format: "herdPublicID == %@",
          herdPublicID.uuidString
        )
      }
      count += try context.count(for: request)
    }
    return count
  }
}

enum HerdSharingAcceptedConflictDiscardPlan {
  static func zoneID(
    for rootRecordID: CKRecord.ID,
    remoteStatus: HerdSharingRemoteAcceptedParticipantStatus
  ) throws -> CKRecordZone.ID {
    if case .present(let permission) = remoteStatus,
       permission != .readWrite,
       permission != .readOnly
    {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted Herd relationship did not expose an authoritative participant permission. No bridge relationship was discarded."
      )
    }
    return rootRecordID.zoneID
  }
}
