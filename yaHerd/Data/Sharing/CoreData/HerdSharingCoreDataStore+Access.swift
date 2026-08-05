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
      try fetchSharedHerdRecord(publicID: herd.publicID, in: store)
    }
    let sharedHerdRecord = try sharedStore.flatMap { store in
      try fetchSharedHerdRecord(publicID: herd.publicID, in: store)
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
      let permission = share.map { sharingPermission(from: $0) } ?? .unknown
      return .acceptedSharedStore(
        permission: permission,
        participantCount: share?.participants.count
      )
    }

    return .localOwnerBridgePending
  }

  func writableBridgeStore(for herd: HerdSummary) throws -> (
    store: NSPersistentStore,
    description: String,
    shouldUpdateShare: Bool
  ) {
    let privateHerdRecord = try privateStore.flatMap { store in
      try fetchSharedHerdRecord(publicID: herd.publicID, in: store)
    }
    let sharedHerdRecord = try sharedStore.flatMap { store in
      try fetchSharedHerdRecord(publicID: herd.publicID, in: store)
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

    if let sharedStore, let sharedHerdRecord {
      let share = try existingShare(for: sharedHerdRecord)
      let permission = share.map { sharingPermission(from: $0) } ?? .unknown
      guard permission == .readWrite || permission == .owner else {
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

    guard let sharedStore else {
      throw HerdSharingActionError.sharingStoreUnavailable(
        "The shared CloudKit bridge store was not loaded.")
    }

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
