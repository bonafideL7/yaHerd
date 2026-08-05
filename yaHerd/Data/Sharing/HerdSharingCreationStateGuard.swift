//
//  HerdSharingCreationStateGuard.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
protocol HerdSharingCreationStateGuarding: AnyObject {
  func evaluate(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess

  func validateNewShare(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess
}

protocol HerdSharingOwnershipRecording: AnyObject {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership?
  func recordOwner(herdPublicID: UUID, deviceID: String)
  func recordParticipant(herdPublicID: UUID)
}

enum HerdSharingOwnership: Equatable {
  case owner(deviceID: String)
  case participant
}

final class UserDefaultsHerdSharingOwnershipRegistry: HerdSharingOwnershipRecording {
  private let defaults: UserDefaults
  private let keyPrefix: String

  init(
    defaults: UserDefaults = .standard,
    keyPrefix: String = "HerdSharingOwnership"
  ) {
    self.defaults = defaults
    self.keyPrefix = keyPrefix
  }

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    guard let value = defaults.string(forKey: key(for: herdPublicID)) else { return nil }
    if value == "participant" {
      return .participant
    }
    let ownerPrefix = "owner|"
    guard value.hasPrefix(ownerPrefix) else { return nil }
    return .owner(deviceID: String(value.dropFirst(ownerPrefix.count)))
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {
    defaults.set("owner|\(deviceID)", forKey: key(for: herdPublicID))
  }

  func recordParticipant(herdPublicID: UUID) {
    defaults.set("participant", forKey: key(for: herdPublicID))
  }

  private func key(for herdPublicID: UUID) -> String {
    "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
  }
}

@MainActor
final class HerdSharingCreationStateGuard: HerdSharingCreationStateGuarding {
  private let context: ModelContext
  private let journal: HerdSharingBridgeJournal
  private let ownershipRegistry: any HerdSharingOwnershipRecording

  init(
    context: ModelContext,
    journal: HerdSharingBridgeJournal? = nil,
    ownershipRegistry: (any HerdSharingOwnershipRecording)? = nil
  ) {
    self.context = context
    self.journal = journal ?? HerdSharingBridgeJournal(
      fileURL: HerdSharingCoreDataStore.defaultStoreDirectoryURL()
        .appendingPathComponent("HerdSharingSyncJournal.json")
    )
    self.ownershipRegistry = ownershipRegistry ?? UserDefaultsHerdSharingOwnershipRegistry()
  }

  func evaluate(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    let identity = CollaborationIdentityProvider.current()

    switch access.bridgeLocation {
    case .conflictingStores:
      return access.applyingCreationState(.conflictingBridgeRecords)

    case .acceptedSharedStore:
      ownershipRegistry.recordParticipant(herdPublicID: herd.publicID)
      return access.applyingCreationState(.acceptedParticipantShare)

    case .ownerPrivateStore where access.hasActiveSystemShare:
      ownershipRegistry.recordOwner(
        herdPublicID: herd.publicID,
        deviceID: identity.deviceID
      )
      return access.applyingCreationState(.existingOwnerShare)

    case .ownerPrivateStore, .bridgeRecordMissing:
      break
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    guard unfinishedOperations.isEmpty else {
      return access.applyingCreationState(.pendingBridgeOperation)
    }

    if access.bridgeLocation == .ownerPrivateStore {
      return access.applyingCreationState(.unresolvedBridgeRecord)
    }

    if let ownership = ownershipRegistry.ownership(for: herd.publicID) {
      switch ownership {
      case .participant:
        return access.applyingCreationState(.notOwnedByCurrentDevice)
      case .owner(let deviceID):
        guard deviceID == identity.deviceID else {
          return access.applyingCreationState(.notOwnedByCurrentDevice)
        }
        return access.applyingCreationState(.ready)
      }
    }

    guard try verifyLocalOwnership(
      herd: herd,
      currentDeviceID: identity.deviceID
    ) else {
      return access.applyingCreationState(.notOwnedByCurrentDevice)
    }

    // Legacy local herds may predate collaboration revision metadata. Once a
    // unique local root is verified, persist a device ownership marker without
    // inventing incomplete revision field snapshots.
    ownershipRegistry.recordOwner(
      herdPublicID: herd.publicID,
      deviceID: identity.deviceID
    )
    return access.applyingCreationState(.ready)
  }

  func validateNewShare(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    let evaluatedAccess = try await evaluate(herd: herd, access: access)

    switch evaluatedAccess.creationState {
    case .ready:
      return evaluatedAccess
    case .existingOwnerShare:
      throw HerdSharingActionError.shareAlreadyExists
    case .acceptedParticipantShare:
      throw HerdSharingActionError.acceptedParticipantShareCannotReshare
    case .unresolvedBridgeRecord, .conflictingBridgeRecords:
      throw HerdSharingActionError.unresolvedSharingBridge
    case .pendingBridgeOperation:
      throw HerdSharingActionError.sharingOperationPending
    case .notOwnedByCurrentDevice:
      throw HerdSharingActionError.herdOwnershipRequired
    case .unknown:
      throw HerdSharingActionError.sharingStateUnavailable
    }
  }

  private func verifyLocalOwnership(
    herd: HerdSummary,
    currentDeviceID: String
  ) throws -> Bool {
    let herdID = herd.publicID
    let aggregateKey = CollaborationAggregateKey(type: .herd, publicID: herdID).storageKey
    var revisionDescriptor = FetchDescriptor<CollaborationRevisionRecord>(
      predicate: #Predicate<CollaborationRevisionRecord> { record in
        record.aggregateKey == aggregateKey && record.herdPublicID == herdID
      },
      sortBy: [SortDescriptor(\CollaborationRevisionRecord.modifiedAt, order: .reverse)]
    )
    revisionDescriptor.fetchLimit = 2
    let revisionRecords = try context.fetch(revisionDescriptor)
    guard revisionRecords.count <= 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Multiple collaboration revision records exist for the Herd root. Repair duplicate metadata before sharing."
      )
    }

    if let revisionRecord = revisionRecords.first {
      return revisionRecord.modifiedByDeviceID == currentDeviceID
    }

    var herdDescriptor = FetchDescriptor<Herd>(
      predicate: #Predicate<Herd> { model in
        model.publicID == herdID
      },
      sortBy: [SortDescriptor(\Herd.createdAt)]
    )
    herdDescriptor.fetchLimit = 2
    let herdModels = try context.fetch(herdDescriptor)
    guard herdModels.count == 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The local Herd root could not be uniquely identified before sharing."
      )
    }
    return true
  }
}
