//
//  HerdSharingCreationStateGuard.swift
//  yaHerd
//

import Foundation
import SwiftData

enum HerdSharingSynchronizationDisposition: Equatable {
  case fullSync
  case importOnly
}

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

  func synchronizationDisposition(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingSynchronizationDisposition

  func confirmLocalOwnership(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess

  func detachStaleParticipantState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess

  func recordOwnerShareEstablished(herdPublicID: UUID)

  func prepareBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws

  func finalizeBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess
}

@MainActor
protocol HerdSharingVerifiedOwnerShareEstablishmentRecording: AnyObject {
  func recordVerifiedOwnerShareEstablished(herdPublicID: UUID)
}

extension HerdSharingCreationStateGuarding {
  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    throw HerdSharingActionError.ownerBridgeVerificationRequired
  }

  func detachStaleParticipantState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    throw HerdSharingActionError.herdOwnershipRequired
  }

  func recordOwnerShareEstablished(herdPublicID: UUID) {}
}

protocol HerdSharingOwnershipRecording: AnyObject {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership?
  func recordOwner(herdPublicID: UUID, deviceID: String)
  func recordParticipant(herdPublicID: UUID)
  func recordDetachedParticipant(herdPublicID: UUID)
  func clearOwnership(for herdPublicID: UUID)
}

extension HerdSharingOwnershipRecording {
  func recordDetachedParticipant(herdPublicID: UUID) {
    clearOwnership(for: herdPublicID)
  }

  func clearOwnership(for herdPublicID: UUID) {}
}

enum HerdSharingOwnership: Equatable {
  case owner(deviceID: String)
  case participant
  case detachedParticipant
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
    if value == "detachedParticipant" {
      return .detachedParticipant
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

  func recordDetachedParticipant(herdPublicID: UUID) {
    defaults.set("detachedParticipant", forKey: key(for: herdPublicID))
  }

  func clearOwnership(for herdPublicID: UUID) {
    defaults.removeObject(forKey: key(for: herdPublicID))
  }

  private func key(for herdPublicID: UUID) -> String {
    "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
  }
}

protocol HerdSharingAccountOwnershipRecording: AnyObject {
  func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool
  func recordEstablishedOwnerShare(for herdPublicID: UUID)
  func clearEstablishedOwnerShare(for herdPublicID: UUID)
}

final class UbiquitousHerdSharingAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
  private let store: NSUbiquitousKeyValueStore
  private let keyPrefix: String

  init(
    store: NSUbiquitousKeyValueStore = .default,
    keyPrefix: String = "HerdSharingOwnerShareEstablished"
  ) {
    self.store = store
    self.keyPrefix = keyPrefix
  }

  func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool {
    _ = store.synchronize()
    return store.bool(forKey: key(for: herdPublicID))
  }

  func recordEstablishedOwnerShare(for herdPublicID: UUID) {
    store.set(true, forKey: key(for: herdPublicID))
    _ = store.synchronize()
  }

  func clearEstablishedOwnerShare(for herdPublicID: UUID) {
    store.removeObject(forKey: key(for: herdPublicID))
    _ = store.synchronize()
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
  private let accountOwnershipRegistry: any HerdSharingAccountOwnershipRecording

  init(
    context: ModelContext,
    journal: HerdSharingBridgeJournal? = nil,
    ownershipRegistry: (any HerdSharingOwnershipRecording)? = nil,
    accountOwnershipRegistry: (any HerdSharingAccountOwnershipRecording)? = nil
  ) {
    self.context = context
    self.journal = journal ?? HerdSharingBridgeJournal(
      fileURL: HerdSharingCoreDataStore.defaultStoreDirectoryURL()
        .appendingPathComponent("HerdSharingSyncJournal.json")
    )
    self.ownershipRegistry = ownershipRegistry ?? UserDefaultsHerdSharingOwnershipRegistry()
    self.accountOwnershipRegistry = accountOwnershipRegistry
      ?? UbiquitousHerdSharingAccountOwnershipRegistry()
  }

  func evaluate(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    let identity = CollaborationIdentityProvider.current()

    if access.hasConflictingBridgeRecords {
      return access.applyingCreationState(.conflictingBridgeRecords)
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    if !unfinishedOperations.isEmpty {
      if access.bridgeLocation == .bridgeRecordMissing,
        let recoveryState = missingBridgeRecoveryState(
          for: herd.publicID,
          unfinishedOperations: unfinishedOperations
        )
      {
        return access.applyingCreationState(recoveryState)
      }

      let hasPendingImport = unfinishedOperations.contains { $0.direction == .importFromBridge }
      if hasPendingImport {
        return access.applyingCreationState(.pendingBridgeOperation)
      }

      let needsOwnerConfirmation = access.bridgeLocation != .acceptedSharedStore
        && !(access.bridgeLocation == .ownerPrivateStore && access.hasActiveSystemShare)
      if needsOwnerConfirmation {
        switch ownershipRegistry.ownership(for: herd.publicID) {
        case .participant?:
          return access.applyingCreationState(.notOwnedByCurrentDevice)
        case .detachedParticipant?:
          return access.applyingCreationState(.pendingBridgeOperation)
        case .owner(let deviceID)? where deviceID == identity.deviceID:
          break
        case .owner?, nil:
          try verifyOwnershipRecoveryCandidate(herd: herd)
          if access.bridgeLocation == .bridgeRecordMissing {
            return access.applyingCreationState(.ownerBridgeVerificationRequired)
          }
          return access.applyingCreationState(.ownershipConfirmationRequired)
        }
      }
      return access.applyingCreationState(.pendingBridgeOperation)
    }

    // A durable participant marker is more specific than stale owner-account history. Route the
    // missing-bridge case through authoritative participant detachment first; only after that
    // succeeds may prior owner provenance drive the separate stale-owner verification flow.
    if access.bridgeLocation == .bridgeRecordMissing,
       case .participant? = ownershipRegistry.ownership(for: herd.publicID)
    {
      return access.applyingCreationState(.notOwnedByCurrentDevice)
    }

    switch access.bridgeLocation {
    case .acceptedSharedStore:
      ownershipRegistry.recordParticipant(herdPublicID: herd.publicID)
      return access.applyingCreationState(.acceptedParticipantShare)

    case .ownerPrivateStore where access.hasActiveSystemShare:
      return access.applyingCreationState(.existingOwnerShare)

    case .ownerPrivateStore:
      return try evaluateUnsharedOwnerBridge(
        herd: herd,
        access: access,
        identity: identity
      )

    case .bridgeRecordMissing:
      return try evaluateMissingBridge(
        herd: herd,
        access: access,
        identity: identity
      )
    }
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
    case .ownershipConfirmationRequired:
      throw HerdSharingActionError.ownershipConfirmationRequired
    case .ownerBridgeVerificationRequired:
      throw HerdSharingActionError.ownerBridgeVerificationRequired
    case .ownerStopCleanupPending:
      throw HerdSharingActionError.ownerBridgeVerificationRequired
    case .notOwnedByCurrentDevice:
      throw HerdSharingActionError.herdOwnershipRequired
    case .unknown:
      throw HerdSharingActionError.sharingStateUnavailable
    }
  }

  func synchronizationDisposition(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingSynchronizationDisposition {
    let initialOperations = await journal.unfinishedOperations(for: herd.publicID)
    if initialOperations.contains(where: HerdSharingBridgeJournal.isCorruptJournalSafetyOperation) {
      try await recoverCorruptJournalForSynchronization(
        herd: herd,
        access: access
      )
      return try await synchronizationDisposition(herd: herd, access: access)
    }

    guard !access.hasConflictingBridgeRecords else {
      throw HerdSharingActionError.unresolvedSharingBridge
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    if !unfinishedOperations.isEmpty {
      let pendingImports = unfinishedOperations.filter { $0.direction == .importFromBridge }
      let pendingExports = unfinishedOperations.filter { $0.direction == .exportToBridge }
      if access.bridgeLocation == .bridgeRecordMissing, !pendingImports.isEmpty {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "A pending shared-data import exists, but its bridge root is no longer available. No local export was attempted. Restore or resolve the original sharing relationship before synchronizing."
        )
      }

      if access.bridgeLocation == .bridgeRecordMissing, pendingImports.isEmpty {
        if accountOwnershipRegistry.hasEstablishedOwnerShare(for: herd.publicID) {
          throw HerdSharingActionError.ownerBridgeVerificationRequired
        }

        let ownerPrivateLocation = HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
        guard unfinishedOperations.allSatisfy({ operation in
          operation.direction == .exportToBridge
            && operation.bridgeLocation == ownerPrivateLocation
        }) else {
          throw HerdSharingActionError.bridgeConsistencyFailed(
            "Pending export recovery targets a bridge relationship that is no longer available. No new owner bridge was created. Resolve the original sharing state before synchronizing."
          )
        }
      }

      if access.bridgeLocation != .bridgeRecordMissing {
        let currentLocation = access.bridgeLocation.journalDescription
        if unfinishedOperations.contains(where: { $0.bridgeLocation != currentLocation }) {
          throw HerdSharingActionError.bridgeConsistencyFailed(
            "Pending shared-data recovery targets a different bridge location than the current sharing relationship. No export was attempted. Resolve the sharing state before synchronizing."
          )
        }
      }

      if access.bridgeLocation == .acceptedSharedStore {
        switch access.permission {
        case .readOnly:
          if !pendingExports.isEmpty {
            let acceptedLocation = HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
            let recoveryImport = try await journal.begin(
              herdPublicID: herd.publicID,
              direction: .importFromBridge,
              bridgeLocation: acceptedLocation
            )
            try await journal.fail(
              operationID: recoveryImport.id,
              errorDescription: "The accepted share became read-only before a pending local export could finish. Retain local SwiftData changes and import the authoritative shared bridge; do not retry the obsolete export."
            )
            try await journal.abandonUnfinishedExports(
              for: herd.publicID,
              bridgeLocation: acceptedLocation,
              reason: "Superseded because the accepted CloudKit share is now read-only. Local SwiftData changes were retained and an import recovery was scheduled."
            )
          }
          return .importOnly

        case .unknown:
          if !pendingExports.isEmpty {
            throw HerdSharingActionError.sharingOperationPending
          }

        case .owner, .readWrite:
          break
        }
      }

      if !pendingImports.isEmpty,
        access.bridgeLocation == .ownerPrivateStore,
        !access.hasActiveSystemShare,
        !hasCurrentDeviceOwnerMarker(for: herd.publicID)
      {
        return .importOnly
      }

      if pendingImports.isEmpty,
        access.bridgeLocation != .acceptedSharedStore,
        !(access.bridgeLocation == .ownerPrivateStore && access.hasActiveSystemShare),
        !hasCurrentDeviceOwnerMarker(for: herd.publicID)
      {
        switch ownershipRegistry.ownership(for: herd.publicID) {
        case .participant?:
          throw HerdSharingActionError.herdOwnershipRequired
        case .detachedParticipant?:
          throw HerdSharingActionError.sharingOperationPending
        default:
          break
        }
        try verifyOwnershipRecoveryCandidate(herd: herd)
        if access.bridgeLocation == .bridgeRecordMissing {
          throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        throw HerdSharingActionError.ownershipConfirmationRequired
      }

      return .fullSync
    }

    if access.bridgeLocation == .acceptedSharedStore,
       access.permission == .readOnly
    {
      return .importOnly
    }

    let evaluatedAccess = try await evaluate(herd: herd, access: access)
    switch evaluatedAccess.creationState {
    case .ready, .existingOwnerShare, .acceptedParticipantShare, .unresolvedBridgeRecord:
      return .fullSync
    case .ownershipConfirmationRequired:
      throw HerdSharingActionError.ownershipConfirmationRequired
    case .ownerBridgeVerificationRequired:
      throw HerdSharingActionError.ownerBridgeVerificationRequired
    case .ownerStopCleanupPending:
      throw HerdSharingActionError.ownerBridgeVerificationRequired
    case .notOwnedByCurrentDevice:
      throw HerdSharingActionError.herdOwnershipRequired
    case .conflictingBridgeRecords:
      throw HerdSharingActionError.unresolvedSharingBridge
    case .pendingBridgeOperation:
      throw HerdSharingActionError.sharingOperationPending
    case .unknown:
      throw HerdSharingActionError.sharingStateUnavailable
    }
  }

  func confirmLocalOwnership(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    guard !access.hasConflictingBridgeRecords else {
      throw HerdSharingActionError.unresolvedSharingBridge
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    guard !unfinishedOperations.contains(where: { $0.direction == .importFromBridge }) else {
      throw HerdSharingActionError.sharingOperationPending
    }

    switch access.bridgeLocation {
    case .acceptedSharedStore:
      ownershipRegistry.recordParticipant(herdPublicID: herd.publicID)
      throw HerdSharingActionError.herdOwnershipRequired

    case .ownerPrivateStore where access.hasActiveSystemShare:
      return access.applyingCreationState(
        unfinishedOperations.isEmpty ? .existingOwnerShare : .pendingBridgeOperation
      )

    case .ownerPrivateStore:
      if case .participant? = ownershipRegistry.ownership(for: herd.publicID) {
        throw HerdSharingActionError.herdOwnershipRequired
      }
      try verifyOwnershipRecoveryCandidate(herd: herd)
      let identity = CollaborationIdentityProvider.current()
      ownershipRegistry.recordOwner(
        herdPublicID: herd.publicID,
        deviceID: identity.deviceID
      )
      return access.applyingCreationState(
        unfinishedOperations.isEmpty ? .unresolvedBridgeRecord : .pendingBridgeOperation
      )

    case .bridgeRecordMissing:
      if case .participant? = ownershipRegistry.ownership(for: herd.publicID) {
        throw HerdSharingActionError.herdOwnershipRequired
      }
      if accountOwnershipRegistry.hasEstablishedOwnerShare(for: herd.publicID) {
        throw HerdSharingActionError.ownerBridgeVerificationRequired
      }

      switch ownershipRegistry.ownership(for: herd.publicID) {
      case .participant?:
        throw HerdSharingActionError.herdOwnershipRequired

      case .detachedParticipant?:
        try verifyOwnershipRecoveryCandidate(herd: herd)
        let identity = CollaborationIdentityProvider.current()
        ownershipRegistry.recordOwner(
          herdPublicID: herd.publicID,
          deviceID: identity.deviceID
        )
        return access.applyingCreationState(
          unfinishedOperations.isEmpty ? .ready : .pendingBridgeOperation
        )

      case .owner(let deviceID)? where deviceID == CollaborationIdentityProvider.current().deviceID:
        return access.applyingCreationState(
          unfinishedOperations.isEmpty ? .ready : .pendingBridgeOperation
        )

      case .owner?:
        throw HerdSharingActionError.ownerBridgeVerificationRequired

      case nil:
        guard try isFreshLocalFirstShareCandidate(herd: herd) else {
          throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        let identity = CollaborationIdentityProvider.current()
        ownershipRegistry.recordOwner(
          herdPublicID: herd.publicID,
          deviceID: identity.deviceID
        )
        return access.applyingCreationState(
          unfinishedOperations.isEmpty ? .ready : .pendingBridgeOperation
        )
      }
    }
  }

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    guard !access.hasConflictingBridgeRecords,
      access.bridgeLocation == .bridgeRecordMissing,
      !access.hasActiveSystemShare
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Stale owner state can be reset only while no owner or accepted bridge root is locally available. Refresh sharing access before resetting."
      )
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    if !unfinishedOperations.isEmpty {
      let ownerPrivateLocation = HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
      guard unfinishedOperations.allSatisfy({ $0.bridgeLocation == ownerPrivateLocation }) else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Stale owner recovery contains unfinished work for a different bridge relationship. No recovery work was abandoned."
        )
      }
    }

    let evaluatedAccess = try await evaluate(herd: herd, access: access)
    guard evaluatedAccess.creationState == .ownerBridgeVerificationRequired else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd is no longer in stale owner-verification state. Refresh sharing access before resetting."
      )
    }

    try verifyOwnershipRecoveryCandidate(herd: herd)
    if !unfinishedOperations.isEmpty {
      try await journal.abandonUnfinishedOperations(
        for: herd.publicID,
        reason: "Abandoned after explicit stale-owner reset confirmed that the owner bridge is no longer present. Local SwiftData was retained; missing remote data was not imported."
      )
    }
    accountOwnershipRegistry.clearEstablishedOwnerShare(for: herd.publicID)
    ownershipRegistry.clearOwnership(for: herd.publicID)
    let identity = CollaborationIdentityProvider.current()
    ownershipRegistry.recordOwner(herdPublicID: herd.publicID, deviceID: identity.deviceID)
    return access.applyingCreationState(.ready)
  }

  func detachStaleParticipantState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    guard !access.hasConflictingBridgeRecords,
      access.bridgeLocation == .bridgeRecordMissing,
      !access.hasActiveSystemShare
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Participant state can be detached only after the accepted shared bridge is no longer present. Refresh sharing access before detaching."
      )
    }

    guard case .participant? = ownershipRegistry.ownership(for: herd.publicID) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "No stale participant marker is present for this Herd."
      )
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    if !unfinishedOperations.isEmpty {
      let acceptedLocation = HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
      guard unfinishedOperations.allSatisfy({ $0.bridgeLocation == acceptedLocation }) else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Stale participant recovery contains unfinished work for a different bridge relationship. No recovery work was abandoned."
        )
      }
    }

    try verifyOwnershipRecoveryCandidate(herd: herd)
    if !unfinishedOperations.isEmpty {
      try await journal.abandonUnfinishedOperations(
        for: herd.publicID,
        reason: "Abandoned after explicit stale-participant detachment confirmed that the accepted bridge is no longer present. Local SwiftData was retained; missing remote data was not imported."
      )
    }
    ownershipRegistry.recordDetachedParticipant(herdPublicID: herd.publicID)

    if accountOwnershipRegistry.hasEstablishedOwnerShare(for: herd.publicID) {
      return access.applyingCreationState(.ownerBridgeVerificationRequired)
    }
    return access.applyingCreationState(.ownershipConfirmationRequired)
  }

  func recordOwnerShareEstablished(herdPublicID: UUID) {
    let identity = CollaborationIdentityProvider.current()
    ownershipRegistry.recordOwner(herdPublicID: herdPublicID, deviceID: identity.deviceID)
    accountOwnershipRegistry.recordEstablishedOwnerShare(for: herdPublicID)
  }

  func prepareBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws {
    guard access.hasConflictingBridgeRecords else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd root is no longer present in both bridge stores. Refresh before resolving the conflict."
      )
    }

    let unfinishedOperations = await journal.unfinishedOperations(for: herd.publicID)
    if unfinishedOperations.contains(where: HerdSharingBridgeJournal.isCorruptJournalSafetyOperation) {
      _ = try await journal.backupAndResetCorruptJournal()
    }

    let identity = CollaborationIdentityProvider.current()
    switch resolution {
    case .keepOwnerShare:
      ownershipRegistry.recordOwner(herdPublicID: herd.publicID, deviceID: identity.deviceID)
    case .keepAcceptedShare:
      ownershipRegistry.recordParticipant(herdPublicID: herd.publicID)
    }

    try await journal.abandonUnfinishedOperations(
      for: herd.publicID,
      reason: "Superseded by explicit bridge-conflict resolution."
    )
    let operation = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: resolution.retainedLocation.journalDescription
    )
    try await journal.fail(
      operationID: operation.id,
      errorDescription: "Recover the retained bridge after explicit bridge-conflict resolution before exporting or managing sharing."
    )
  }

  func finalizeBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    guard !access.hasConflictingBridgeRecords,
      access.bridgeLocation == resolution.retainedLocation
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The selected bridge relationship was not the only surviving Herd root after conflict resolution."
      )
    }

    switch resolution {
    case .keepOwnerShare:
      break
    case .keepAcceptedShare:
      accountOwnershipRegistry.clearEstablishedOwnerShare(for: herd.publicID)
    }

    return try await evaluate(herd: herd, access: access)
  }

  private func recoverCorruptJournalForSynchronization(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws {
    // If the bridge itself is gone, remove any device-local owner authority before replacing the
    // corrupt journal. This is a restrictive mutation: if backup/replacement subsequently fails,
    // the corrupt journal still blocks writes and the owner marker remains cleared.
    if access.bridgeLocation == .bridgeRecordMissing,
       case .owner? = ownershipRegistry.ownership(for: herd.publicID)
    {
      ownershipRegistry.clearOwnership(for: herd.publicID)
    }

    let recoveryPlan: HerdSharingCorruptJournalRecoveryPlan?
    if !access.hasConflictingBridgeRecords,
       access.bridgeLocation != .bridgeRecordMissing
    {
      recoveryPlan = HerdSharingCorruptJournalRecoveryPlan(
        herdPublicID: herd.publicID,
        bridgeLocation: access.bridgeLocation.journalDescription
      )
    } else {
      recoveryPlan = nil
    }

    _ = try await journal.backupAndResetCorruptJournal(recoveryPlan: recoveryPlan)
  }

  private func evaluateUnsharedOwnerBridge(
    herd: HerdSummary,
    access: HerdSharingAccess,
    identity: CollaborationMutationIdentity
  ) throws -> HerdSharingAccess {
    if let ownership = ownershipRegistry.ownership(for: herd.publicID) {
      switch ownership {
      case .participant:
        return access.applyingCreationState(.notOwnedByCurrentDevice)
      case .detachedParticipant:
        try verifyOwnershipRecoveryCandidate(herd: herd)
        return access.applyingCreationState(.ownershipConfirmationRequired)
      case .owner(let deviceID) where deviceID == identity.deviceID:
        return access.applyingCreationState(.unresolvedBridgeRecord)
      case .owner:
        try verifyOwnershipRecoveryCandidate(herd: herd)
        return access.applyingCreationState(.ownershipConfirmationRequired)
      }
    }

    try verifyOwnershipRecoveryCandidate(herd: herd)
    return access.applyingCreationState(.ownershipConfirmationRequired)
  }

  private func evaluateMissingBridge(
    herd: HerdSummary,
    access: HerdSharingAccess,
    identity: CollaborationMutationIdentity
  ) throws -> HerdSharingAccess {
    if accountOwnershipRegistry.hasEstablishedOwnerShare(for: herd.publicID) {
      return access.applyingCreationState(.ownerBridgeVerificationRequired)
    }

    if let ownership = ownershipRegistry.ownership(for: herd.publicID) {
      switch ownership {
      case .participant:
        return access.applyingCreationState(.notOwnedByCurrentDevice)
      case .detachedParticipant:
        try verifyOwnershipRecoveryCandidate(herd: herd)
        return access.applyingCreationState(.ownershipConfirmationRequired)
      case .owner(let deviceID) where deviceID == identity.deviceID:
        return access.applyingCreationState(.ready)
      case .owner:
        try verifyOwnershipRecoveryCandidate(herd: herd)
        return access.applyingCreationState(.ownerBridgeVerificationRequired)
      }
    }

    try verifyOwnershipRecoveryCandidate(herd: herd)
    if try isFreshLocalFirstShareCandidate(herd: herd) {
      return access.applyingCreationState(.ownershipConfirmationRequired)
    }
    return access.applyingCreationState(.ownerBridgeVerificationRequired)
  }

  private func missingBridgeRecoveryState(
    for herdPublicID: UUID,
    unfinishedOperations: [HerdSharingBridgeOperationRecord]
  ) -> HerdSharingAccess.CreationState? {
    let ownerPrivateLocation = HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    let acceptedLocation = HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription

    switch ownershipRegistry.ownership(for: herdPublicID) {
    case .participant?:
      guard unfinishedOperations.allSatisfy({ $0.bridgeLocation == acceptedLocation }) else {
        return nil
      }
      return .notOwnedByCurrentDevice

    case .detachedParticipant?:
      return nil

    case .owner?:
      guard unfinishedOperations.allSatisfy({ $0.bridgeLocation == ownerPrivateLocation }) else {
        return nil
      }
      return .ownerBridgeVerificationRequired

    case nil:
      guard accountOwnershipRegistry.hasEstablishedOwnerShare(for: herdPublicID),
        unfinishedOperations.allSatisfy({ $0.bridgeLocation == ownerPrivateLocation })
      else {
        return nil
      }
      return .ownerBridgeVerificationRequired
    }
  }

  private func hasCurrentDeviceOwnerMarker(for herdPublicID: UUID) -> Bool {
    guard case .owner(let deviceID)? = ownershipRegistry.ownership(for: herdPublicID) else {
      return false
    }
    return deviceID == CollaborationIdentityProvider.current().deviceID
  }

  private func isFreshLocalFirstShareCandidate(herd: HerdSummary) throws -> Bool {
    guard let revisionRecord = try validatedHerdRevisionRecord(herd: herd) else {
      return false
    }
    // Last-writer device metadata is not ownership proof. A base revision of zero means the Herd
    // has no imported/shared lineage; ownership is established only after the user explicitly
    // confirms the unique local Herd root.
    return revisionRecord.baseRevision == 0
      && !revisionRecord.deletionTombstone
  }

  private func verifyOwnershipRecoveryCandidate(
    herd: HerdSummary
  ) throws {
    _ = try validatedHerdRevisionRecord(herd: herd)

    let herdID = herd.publicID
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
  }

  private func validatedHerdRevisionRecord(
    herd: HerdSummary
  ) throws -> CollaborationRevisionRecord? {
    let herdID = herd.publicID
    let herdEntityName = CollaborationAggregateType.herd.rawValue
    var revisionDescriptor = FetchDescriptor<CollaborationRevisionRecord>(
      predicate: #Predicate<CollaborationRevisionRecord> { record in
        record.sourceEntityName == herdEntityName && record.aggregatePublicID == herdID
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
    guard let revisionRecord = revisionRecords.first else { return nil }
    guard revisionRecord.herdPublicID == herdID else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The Herd collaboration revision is scoped to a different Herd root. Repair the local collaboration metadata before sharing."
      )
    }
    if revisionRecord.deletionTombstone {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The local Herd root still exists, but its collaboration revision marks it deleted. Repair the local collaboration metadata before sharing."
      )
    }
    return revisionRecord
  }
}
