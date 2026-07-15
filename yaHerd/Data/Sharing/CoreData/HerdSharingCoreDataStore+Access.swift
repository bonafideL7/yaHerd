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

    if let privateStore,
      let privateHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
    {
      let share = try existingShare(for: privateHerdRecord)
      return .ownerPrivateStore(participantCount: share?.participants.count)
    }

    if let sharedStore,
      let sharedHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: sharedStore)
    {
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
    if let privateStore,
      let privateHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
    {
      let hasExistingShare = try existingShare(for: privateHerdRecord) != nil
      return (privateStore, "owner private store", hasExistingShare)
    }

    if let sharedStore,
      let sharedHerdRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: sharedStore)
    {
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
