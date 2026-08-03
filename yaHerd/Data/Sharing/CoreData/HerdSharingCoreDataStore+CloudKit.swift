//
//  HerdSharingCoreDataStore+CloudKit.swift
//  yaHerd
//

import CloudKit
import CoreData

extension HerdSharingCoreDataStore {
  func shareRecords(
    _ records: [NSManagedObject],
    title: String
  ) async throws -> CKShare {
    let existingCKShare =
      try records
      .compactMap { record in
        try self.existingShare(for: record)
      }
      .first

    let share = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<CKShare, Error>) in
      persistentContainer.share(records, to: existingCKShare) { _, share, _, error in
        if let error {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
          return
        }

        guard let share else {
          continuation.resume(
            throwing: HerdSharingActionError.cloudKitSharingFailed(
              "Core Data did not return a CKShare."))
          return
        }

        share[CKShare.SystemFieldKey.title] = title as NSString
        continuation.resume(returning: share)
      }
    }
    registerCurrentParticipant(from: share)
    return share
  }

  func existingShare(for record: NSManagedObject) throws -> CKShare? {
    let shares = try persistentContainer.fetchShares(matching: [record.objectID])
    return shares[record.objectID]
  }

  func sharingPermission(from share: CKShare) -> HerdSharingAccess.Permission {
    guard let currentUserParticipant = share.currentUserParticipant else {
      return .unknown
    }
    registerCurrentParticipant(from: currentUserParticipant)

    switch currentUserParticipant.permission {
    case .readOnly:
      return .readOnly
    case .readWrite:
      return .readWrite
    case .unknown, .none:
      return .unknown
    @unknown default:
      return .unknown
    }
  }

  func persistUpdatedShare(_ share: CKShare) async {
    guard let privateStore else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      persistentContainer.persistUpdatedShare(
        share,
        in: privateStore
      ) { _, _ in
        continuation.resume()
      }
    }
  }

  func purgeStoppedShare(_ share: CKShare) async {
    guard let privateStore else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      persistentContainer.purgeObjectsAndRecordsInZone(
        with: share.recordID.zoneID,
        in: privateStore
      ) { _, _ in
        continuation.resume()
      }
    }
  }

  private func registerCurrentParticipant(from share: CKShare) {
    guard let participant = share.currentUserParticipant else { return }
    registerCurrentParticipant(from: participant)
  }

  private func registerCurrentParticipant(from participant: CKShare.Participant) {
    guard let participantID = participant.userIdentity.userRecordID?.recordName else { return }
    CollaborationIdentityProvider.registerParticipantID(participantID)
  }
}
