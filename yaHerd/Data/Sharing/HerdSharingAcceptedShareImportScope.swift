import CloudKit
import Foundation

nonisolated struct HerdSharingAcceptedParticipantReference: Codable, Equatable, Sendable {
  let rootRecordName: String
  let rootZoneName: String
  let rootZoneOwnerName: String
  let participantAccountRecordName: String?

  init(
    rootRecordName: String,
    rootZoneName: String,
    rootZoneOwnerName: String,
    participantAccountRecordName: String? = nil
  ) {
    self.rootRecordName = rootRecordName
    self.rootZoneName = rootZoneName
    self.rootZoneOwnerName = rootZoneOwnerName
    self.participantAccountRecordName = participantAccountRecordName
  }

  init(scope: HerdSharingAcceptedShareImportScope) {
    self.init(
      rootRecordName: scope.rootRecordName,
      rootZoneName: scope.rootZoneName,
      rootZoneOwnerName: scope.rootZoneOwnerName,
      participantAccountRecordName: scope.participantAccountRecordName
    )
  }

  init(
    rootRecordID: CKRecord.ID,
    participantAccountRecordName: String? = nil
  ) {
    self.init(
      rootRecordName: rootRecordID.recordName,
      rootZoneName: rootRecordID.zoneID.zoneName,
      rootZoneOwnerName: rootRecordID.zoneID.ownerName,
      participantAccountRecordName: participantAccountRecordName
    )
  }

  var rootRecordID: CKRecord.ID {
    CKRecord.ID(
      recordName: rootRecordName,
      zoneID: CKRecordZone.ID(
        zoneName: rootZoneName,
        ownerName: rootZoneOwnerName
      )
    )
  }
}

nonisolated enum HerdSharingRemoteAcceptedParticipantStatus: Equatable, Sendable {
  case present(permission: HerdSharingAccess.Permission)
  case absent
}

@MainActor
protocol HerdSharingAcceptedParticipantReferenceRecording: AnyObject {
  func reference(for herdPublicID: UUID) -> HerdSharingAcceptedParticipantReference?
  func recoverableReference(for herdPublicID: UUID) throws -> HerdSharingAcceptedParticipantReference?
  func hasConflictingReference(for herdPublicID: UUID) -> Bool
  func record(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  )
  func replaceConflictingReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws
  func clearReference(for herdPublicID: UUID)
}

extension HerdSharingAcceptedParticipantReferenceRecording {
  func recoverableReference(for herdPublicID: UUID) throws -> HerdSharingAcceptedParticipantReference? {
    reference(for: herdPublicID)
  }

  func hasConflictingReference(for herdPublicID: UUID) -> Bool { false }

  func replaceConflictingReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    throw HerdSharingActionError.bridgeConsistencyFailed(
      "This accepted-share provenance store cannot replace conflicting copies recoverably. Participant state remains blocked."
    )
  }
}

@MainActor
final class UserDefaultsHerdSharingAcceptedParticipantReferenceStore:
  HerdSharingAcceptedParticipantReferenceRecording
{
  private let defaults: UserDefaults
  private let keyPrefix: String

  init(
    defaults: UserDefaults = .standard,
    keyPrefix: String = "HerdSharingAcceptedParticipantReference"
  ) {
    self.defaults = defaults
    self.keyPrefix = keyPrefix
  }

  func reference(for herdPublicID: UUID) -> HerdSharingAcceptedParticipantReference? {
    try? recoverableReference(for: herdPublicID)
  }

  func recoverableReference(
    for herdPublicID: UUID
  ) throws -> HerdSharingAcceptedParticipantReference? {
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    let primaryData = defaults.data(forKey: primaryKey)
    let recoveryData = defaults.data(forKey: recoveryKey)
    let primaryReference = primaryData.flatMap(decode)
    let recoveryReference = recoveryData.flatMap(decode)

    if let primaryData, let primaryReference {
      if let recoveryData, let recoveryReference {
        guard primaryReference == recoveryReference else {
          _ = try backupCorruptData(
            primaryData,
            for: herdPublicID,
            source: "conflicting-primary"
          )
          _ = try backupCorruptData(
            recoveryData,
            for: herdPublicID,
            source: "conflicting-recovery"
          )
          throw HerdSharingActionError.bridgeConsistencyFailed(
            "The redundant accepted-share participant provenance copies identify different CloudKit relationships. Both exact values were preserved, and participant state was not detached. Reopen the currently accepted share so yaHerd can establish one authoritative participant relationship before retrying detachment."
          )
        }
      } else {
        if let recoveryData {
          _ = try backupCorruptData(
            recoveryData,
            for: herdPublicID,
            source: "recovery"
          )
        }
        defaults.set(primaryData, forKey: recoveryKey)
      }
      return primaryReference
    }

    if let recoveryData, let recoveryReference {
      if let primaryData {
        _ = try backupCorruptData(
          primaryData,
          for: herdPublicID,
          source: "primary"
        )
      }
      defaults.set(recoveryData, forKey: primaryKey)
      return recoveryReference
    }

    guard primaryData != nil || recoveryData != nil else { return nil }

    if let primaryData {
      _ = try backupCorruptData(
        primaryData,
        for: herdPublicID,
        source: "primary"
      )
    }
    if let recoveryData {
      _ = try backupCorruptData(
        recoveryData,
        for: herdPublicID,
        source: "recovery"
      )
    }
    throw HerdSharingActionError.bridgeConsistencyFailed(
      "The retained accepted-share participant provenance is corrupt and no valid redundant recovery copy is available. The corrupt bytes were preserved, and participant state was not detached. Reopen the original CloudKit share while it is available so yaHerd can backfill the exact accepted Herd root before retrying detachment."
    )
  }

  func hasConflictingReference(for herdPublicID: UUID) -> Bool {
    guard let primaryData = defaults.data(forKey: key(for: herdPublicID)),
          let recoveryData = defaults.data(forKey: recoveryKey(for: herdPublicID)),
          let primaryReference = decode(primaryData),
          let recoveryReference = decode(recoveryData)
    else {
      return false
    }
    return primaryReference != recoveryReference
  }

  func replaceConflictingReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    guard let primaryData = defaults.data(forKey: primaryKey),
          let recoveryData = defaults.data(forKey: recoveryKey),
          let primaryReference = decode(primaryData),
          let recoveryReference = decode(recoveryData),
          primaryReference != recoveryReference
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "No conflicting accepted-share provenance copies are available for authoritative replacement. Participant state remains blocked."
      )
    }

    _ = try backupCorruptData(
      primaryData,
      for: herdPublicID,
      source: "authoritative-replacement-primary"
    )
    _ = try backupCorruptData(
      recoveryData,
      for: herdPublicID,
      source: "authoritative-replacement-recovery"
    )
    guard let replacementData = try? JSONEncoder().encode(reference) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The authoritative accepted-share provenance could not be encoded. Conflicting copies remain active."
      )
    }
    defaults.set(replacementData, forKey: primaryKey)
    defaults.set(replacementData, forKey: recoveryKey)
    guard defaults.data(forKey: primaryKey) == replacementData,
          defaults.data(forKey: recoveryKey) == replacementData,
          try recoverableReference(for: herdPublicID) == reference
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The authoritative accepted-share provenance could not be persisted durably. Participant state remains blocked."
      )
    }
  }

  func record(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) {
    guard let data = try? JSONEncoder().encode(reference) else { return }
    defaults.set(data, forKey: key(for: herdPublicID))
    defaults.set(data, forKey: recoveryKey(for: herdPublicID))
  }

  func clearReference(for herdPublicID: UUID) {
    defaults.removeObject(forKey: key(for: herdPublicID))
    defaults.removeObject(forKey: recoveryKey(for: herdPublicID))
  }

  private func decode(_ data: Data) -> HerdSharingAcceptedParticipantReference? {
    try? JSONDecoder().decode(HerdSharingAcceptedParticipantReference.self, from: data)
  }

  @discardableResult
  private func backupCorruptData(
    _ data: Data,
    for herdPublicID: UUID,
    source: String
  ) throws -> String {
    let backupKey = "\(keyPrefix).corrupt-backup.\(herdPublicID.uuidString.lowercased()).\(source).\(UUID().uuidString.lowercased())"
    defaults.set(data, forKey: backupKey)
    guard defaults.data(forKey: backupKey) == data else {
      defaults.removeObject(forKey: backupKey)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The corrupt accepted-share participant provenance could not be backed up. The active provenance was left unchanged and participant state was not detached."
      )
    }
    return backupKey
  }

  private func key(for herdPublicID: UUID) -> String {
    "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
  }

  private func recoveryKey(for herdPublicID: UUID) -> String {
    "\(key(for: herdPublicID)).recovery"
  }
}

@MainActor
protocol HerdSharingRemoteAcceptedParticipantVerifying: AnyObject {
  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus
}

@MainActor
final class CloudKitHerdSharingRemoteAcceptedParticipantVerifier:
  HerdSharingRemoteAcceptedParticipantVerifying
{
  private let currentAccountRecordNameProvider: @MainActor () async throws -> String
  private let sharedRecordProvider: @MainActor (CKRecord.ID) async throws -> CKRecord
  private let sharedPermissionProvider: @MainActor (CKRecord) async throws
    -> HerdSharingAccess.Permission

  init(
    containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
    currentAccountRecordNameProvider: (@MainActor () async throws -> String)? = nil,
    sharedRecordProvider: (@MainActor (CKRecord.ID) async throws -> CKRecord)? = nil,
    sharedPermissionProvider: (@MainActor (CKRecord) async throws
      -> HerdSharingAccess.Permission)? = nil
  ) {
    if let currentAccountRecordNameProvider {
      self.currentAccountRecordNameProvider = currentAccountRecordNameProvider
    } else {
      self.currentAccountRecordNameProvider = {
        try await CKContainer(identifier: containerIdentifier).userRecordID().recordName
      }
    }
    let resolvedSharedRecordProvider = sharedRecordProvider ?? { recordID in
      try await CKContainer(identifier: containerIdentifier).sharedCloudDatabase.record(
        for: recordID
      )
    }
    self.sharedRecordProvider = resolvedSharedRecordProvider
    self.sharedPermissionProvider = sharedPermissionProvider ?? { rootRecord in
      guard let shareRecordID = rootRecord.share?.recordID else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted CloudKit Herd root did not expose its containing share. Participant permission remains unverified."
        )
      }
      let shareRecord = try await resolvedSharedRecordProvider(shareRecordID)
      guard let share = shareRecord as? CKShare,
            let participant = share.currentUserParticipant,
            participant.role != .owner
      else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted CloudKit share did not identify the current account as a participant. Participant permission remains unverified."
        )
      }
      return switch participant.permission {
      case .readWrite: .readWrite
      case .readOnly: .readOnly
      case .none, .unknown:
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted CloudKit share did not expose an authoritative participant permission. Participant access remains write-blocked."
        )
      @unknown default:
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The accepted CloudKit share returned an unsupported participant permission. Participant access remains write-blocked."
        )
      }
    }
  }

  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    do {
      guard let expectedParticipantAccount = reference.participantAccountRecordName else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "The stored accepted-share provenance has no originating iCloud account identity. Participant state was not detached."
        )
      }

      let currentAccount = try await currentAccountRecordNameProvider()
      try HerdSharingAcceptedParticipantProvenance.validateAccountCompatibility(
        expectedParticipantAccountRecordName: expectedParticipantAccount,
        currentAccountRecordName: currentAccount
      )

      let rootRecord: CKRecord
      do {
        rootRecord = try await sharedRecordProvider(reference.rootRecordID)
      } catch let error as CKError
        where error.code == .unknownItem || error.code == .zoneNotFound
      {
        try await validateAccountUnchanged(since: currentAccount)
        return .absent
      }
      let permission = try await sharedPermissionProvider(rootRecord)
      try await validateAccountUnchanged(since: currentAccount)
      return .present(permission: permission)
    } catch let error as HerdSharingActionError {
      throw error
    } catch {
      throw HerdSharingActionError.cloudKitSharingFailed(
        "Could not verify whether the accepted shared Herd still exists in CloudKit: \(error.localizedDescription)"
      )
    }
  }

  private func validateAccountUnchanged(since expectedAccountRecordName: String) async throws {
    let currentAccountRecordName = try await currentAccountRecordNameProvider()
    try HerdSharingAcceptedParticipantProvenance.validateAccountCompatibility(
      expectedParticipantAccountRecordName: expectedAccountRecordName,
      currentAccountRecordName: currentAccountRecordName
    )
  }
}

@MainActor
enum HerdSharingAcceptedParticipantProvenance {
  static func verifyRecordedShareIsAbsent(
    for herdPublicID: UUID,
    referenceStore: any HerdSharingAcceptedParticipantReferenceRecording,
    remoteVerifier: any HerdSharingRemoteAcceptedParticipantVerifying
  ) async throws {
    guard let reference = try referenceStore.recoverableReference(for: herdPublicID) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The prior accepted CloudKit Herd root has no durable reference. Participant state was not detached because remote absence cannot be verified safely."
      )
    }

    guard try await remoteVerifier.status(for: reference) == .absent else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted CloudKit Herd is still available remotely. Participant state was not detached. Refresh sharing access or leave the share before detaching it locally."
      )
    }
  }

  static func validateAccountCompatibility(
    expectedParticipantAccountRecordName: String,
    currentAccountRecordName: String
  ) throws {
    guard expectedParticipantAccountRecordName == currentAccountRecordName else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted CloudKit Herd belongs to a different iCloud account than the account currently signed in. Participant state was not detached."
      )
    }
  }
}

nonisolated struct HerdSharingAcceptedShareImportScope: Codable, Equatable, Sendable {
  enum AcceptanceState: String, Codable, Equatable, Sendable {
    case legacyUnknown
    case pending
    case accepted
  }

  let shareIdentifier: String
  let rootRecordName: String
  let rootZoneName: String
  let rootZoneOwnerName: String
  let acceptedAt: Date
  let participantAccountRecordName: String?
  let acceptanceState: AcceptanceState
  let remoteAbsenceObservedAt: Date?
  let ignoredParticipantAccountRecordNames: [String]

  init(
    shareIdentifier: String,
    rootRecordName: String,
    rootZoneName: String,
    rootZoneOwnerName: String,
    acceptedAt: Date = .now,
    participantAccountRecordName: String? = nil,
    acceptanceState: AcceptanceState = .accepted,
    remoteAbsenceObservedAt: Date? = nil,
    ignoredParticipantAccountRecordNames: [String] = []
  ) {
    self.shareIdentifier = shareIdentifier
    self.rootRecordName = rootRecordName
    self.rootZoneName = rootZoneName
    self.rootZoneOwnerName = rootZoneOwnerName
    self.acceptedAt = acceptedAt
    self.participantAccountRecordName = participantAccountRecordName
    self.acceptanceState = acceptanceState
    self.remoteAbsenceObservedAt = remoteAbsenceObservedAt
    self.ignoredParticipantAccountRecordNames = ignoredParticipantAccountRecordNames.sorted()
  }

  init(
    metadata: CKShare.Metadata,
    participantAccountRecordName: String,
    acceptedAt: Date = .now
  ) throws {
    guard let rootRecordID = metadata.hierarchicalRootRecordID else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The CloudKit invitation did not identify the shared Herd root. The invitation was not accepted because yaHerd could not safely scope participant recovery."
      )
    }

    self.init(
      shareIdentifier: metadata.share.recordID.recordName,
      rootRecordName: rootRecordID.recordName,
      rootZoneName: rootRecordID.zoneID.zoneName,
      rootZoneOwnerName: rootRecordID.zoneID.ownerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: participantAccountRecordName,
      acceptanceState: .pending
    )
  }

  var rootRecordID: CKRecord.ID {
    CKRecord.ID(
      recordName: rootRecordName,
      zoneID: CKRecordZone.ID(
        zoneName: rootZoneName,
        ownerName: rootZoneOwnerName
      )
    )
  }

  func markingAccepted(participantAccountRecordName: String? = nil) -> Self {
    Self(
      shareIdentifier: shareIdentifier,
      rootRecordName: rootRecordName,
      rootZoneName: rootZoneName,
      rootZoneOwnerName: rootZoneOwnerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: self.participantAccountRecordName ?? participantAccountRecordName,
      acceptanceState: .accepted,
      ignoredParticipantAccountRecordNames: ignoredParticipantAccountRecordNames
    )
  }

  func recordingRemoteAbsence(at date: Date) -> Self {
    Self(
      shareIdentifier: shareIdentifier,
      rootRecordName: rootRecordName,
      rootZoneName: rootZoneName,
      rootZoneOwnerName: rootZoneOwnerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: participantAccountRecordName,
      acceptanceState: acceptanceState,
      remoteAbsenceObservedAt: date,
      ignoredParticipantAccountRecordNames: ignoredParticipantAccountRecordNames
    )
  }

  func clearingRemoteAbsence() -> Self {
    Self(
      shareIdentifier: shareIdentifier,
      rootRecordName: rootRecordName,
      rootZoneName: rootZoneName,
      rootZoneOwnerName: rootZoneOwnerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: participantAccountRecordName,
      acceptanceState: acceptanceState,
      remoteAbsenceObservedAt: nil,
      ignoredParticipantAccountRecordNames: ignoredParticipantAccountRecordNames
    )
  }

  func retiringForParticipantAccount(_ accountRecordName: String) -> Self {
    Self(
      shareIdentifier: shareIdentifier,
      rootRecordName: rootRecordName,
      rootZoneName: rootZoneName,
      rootZoneOwnerName: rootZoneOwnerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: participantAccountRecordName,
      acceptanceState: acceptanceState,
      remoteAbsenceObservedAt: remoteAbsenceObservedAt,
      ignoredParticipantAccountRecordNames: Array(
        Set(ignoredParticipantAccountRecordNames + [accountRecordName])
      ).sorted()
    )
  }

  func bindingParticipantAccountForRecovery(_ accountRecordName: String) -> Self {
    Self(
      shareIdentifier: shareIdentifier,
      rootRecordName: rootRecordName,
      rootZoneName: rootZoneName,
      rootZoneOwnerName: rootZoneOwnerName,
      acceptedAt: acceptedAt,
      participantAccountRecordName: accountRecordName,
      acceptanceState: acceptanceState,
      remoteAbsenceObservedAt: remoteAbsenceObservedAt,
      ignoredParticipantAccountRecordNames: ignoredParticipantAccountRecordNames
    )
  }

  private enum CodingKeys: String, CodingKey {
    case shareIdentifier
    case rootRecordName
    case rootZoneName
    case rootZoneOwnerName
    case acceptedAt
    case participantAccountRecordName
    case acceptanceState
    case remoteAbsenceObservedAt
    case ignoredParticipantAccountRecordNames
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    shareIdentifier = try container.decode(String.self, forKey: .shareIdentifier)
    rootRecordName = try container.decode(String.self, forKey: .rootRecordName)
    rootZoneName = try container.decode(String.self, forKey: .rootZoneName)
    rootZoneOwnerName = try container.decode(String.self, forKey: .rootZoneOwnerName)
    acceptedAt = try container.decode(Date.self, forKey: .acceptedAt)
    participantAccountRecordName = try container.decodeIfPresent(
      String.self,
      forKey: .participantAccountRecordName
    )
    acceptanceState = try container.decodeIfPresent(
      AcceptanceState.self,
      forKey: .acceptanceState
    ) ?? .legacyUnknown
    remoteAbsenceObservedAt = try container.decodeIfPresent(
      Date.self,
      forKey: .remoteAbsenceObservedAt
    )
    ignoredParticipantAccountRecordNames = try container.decodeIfPresent(
      [String].self,
      forKey: .ignoredParticipantAccountRecordNames
    ) ?? []
  }
}

@MainActor
final class HerdSharingAcceptedShareImportScopeStore {
  private let defaults: UserDefaults
  private let storageKey: String
  private let participantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording
  private let currentAccountRecordNameProvider: @MainActor () async throws -> String
  private(set) var immediateImportScope: HerdSharingAcceptedShareImportScope?

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = "HerdSharingAcceptedShareImportScopes.v1",
    participantReferenceStore: (any HerdSharingAcceptedParticipantReferenceRecording)? = nil,
    currentAccountRecordNameProvider: (@MainActor () async throws -> String)? = nil
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.participantReferenceStore = participantReferenceStore
      ?? UserDefaultsHerdSharingAcceptedParticipantReferenceStore(defaults: defaults)
    if let currentAccountRecordNameProvider {
      self.currentAccountRecordNameProvider = currentAccountRecordNameProvider
    } else {
      let containerIdentifier = ModelContainerFactory.cloudKitContainerIdentifier
      self.currentAccountRecordNameProvider = {
        let recordID = try await CKContainer(identifier: containerIdentifier).userRecordID()
        return recordID.recordName
      }
    }
  }

  var hasCorruptPersistedState: Bool {
    guard let data = defaults.data(forKey: storageKey) else { return false }
    return (try? JSONDecoder().decode([HerdSharingAcceptedShareImportScope].self, from: data)) == nil
  }

  var hasCorruptRecoveryPending: Bool {
    defaults.bool(forKey: corruptRecoveryPendingKey)
  }

  func pendingScopes() throws -> [HerdSharingAcceptedShareImportScope] {
    guard let data = defaults.data(forKey: storageKey) else { return [] }
    do {
      return try JSONDecoder().decode(
        [HerdSharingAcceptedShareImportScope].self,
        from: data
      ).sorted(by: Self.scopeSort)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The retained CloudKit invitation recovery state could not be decoded. Sharing and unscoped imports remain blocked. Reopen the original CloudKit share invitation so yaHerd can restore its exact Herd root and zone identity without guessing."
      )
    }
  }

  @discardableResult
  func backupAndResetCorruptStateForRecovery() throws -> String {
    guard let corruptData = defaults.data(forKey: storageKey), hasCorruptPersistedState else {
      if hasCorruptRecoveryPending {
        return defaults.string(forKey: corruptRecoveryBackupPointerKey) ?? ""
      }
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "No corrupt retained invitation state is available to recover."
      )
    }

    let backupKey = "\(storageKey).corrupt-backup-\(UUID().uuidString.lowercased())"
    defaults.set(corruptData, forKey: backupKey)
    guard defaults.data(forKey: backupKey) == corruptData else {
      defaults.removeObject(forKey: backupKey)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The corrupt retained invitation state could not be backed up. The active recovery state was left unchanged."
      )
    }

    defaults.set(backupKey, forKey: corruptRecoveryBackupPointerKey)
    defaults.set(true, forKey: corruptRecoveryPendingKey)
    defaults.removeObject(forKey: corruptRecoveryCandidateKey)
    defaults.removeObject(forKey: storageKey)
    immediateImportScope = nil
    return backupKey
  }

  func completeCorruptRecovery() {
    defaults.removeObject(forKey: corruptRecoveryPendingKey)
    defaults.removeObject(forKey: corruptRecoveryBackupPointerKey)
    defaults.removeObject(forKey: corruptRecoveryCandidateKey)
    immediateImportScope = nil
  }

  func currentAccountRecordName(
    allowingCorruptRecovery: Bool = false
  ) async throws -> String {
    guard allowingCorruptRecovery || !hasCorruptRecoveryPending else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The corrupt CloudKit invitation state was backed up, but its exact invitation identity was lost. yaHerd will not guess from the shared roots already on this device. Reopen the original CloudKit share invitation so the exact Herd root and zone can be recorded before recovery continues."
      )
    }
    return try await currentAccountRecordNameProvider()
  }

  func pendingScopesForCurrentAccount() async throws -> [HerdSharingAcceptedShareImportScope] {
    guard !hasCorruptRecoveryPending else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Corrupt CloudKit invitation recovery is pending. Reopen the original CloudKit share invitation and accept that same invitation twice: the first attempt stages its exact identity without contacting CloudKit, and the second explicitly confirms it as the recovery target."
      )
    }

    let scopes = try pendingScopes()
    guard !scopes.isEmpty else { return [] }

    let accountRecordName = try await currentAccountRecordName()
    var matchingScopes: [HerdSharingAcceptedShareImportScope] = []
    matchingScopes.reserveCapacity(scopes.count)

    for scope in scopes {
      if let participantAccountRecordName = scope.participantAccountRecordName {
        guard participantAccountRecordName == accountRecordName else {
          throw HerdSharingActionError.bridgeConsistencyFailed(
            "A retained CloudKit invitation belongs to or may belong to a different iCloud account. Sign back into the account that accepted the invitation and finish or retire that recovery before this account can edit, share, or import the local Herd."
          )
        }
        matchingScopes.append(scope)
        continue
      }

      if scope.acceptanceState == .legacyUnknown {
        if scope.ignoredParticipantAccountRecordNames.contains(accountRecordName) {
          // This account already confirmed the account-less legacy root absent twice. Preserve
          // the scope so another account can still recover it, but retire it as a blocker here.
          continue
        }
        matchingScopes.append(scope.bindingParticipantAccountForRecovery(accountRecordName))
        continue
      }

      throw HerdSharingActionError.bridgeConsistencyFailed(
        "A retained CloudKit invitation belongs to or may belong to a different iCloud account. Sign back into the account that accepted the invitation and finish or retire that recovery before this account can edit, share, or import the local Herd."
      )
    }

    return matchingScopes
  }

  func hasPendingScopeForCurrentAccount() async throws -> Bool {
    // A recovery marker remains a write/share block after the corrupt bytes are moved aside. It is
    // cleared only after the user explicitly confirms the same exact invitation identity twice or
    // a scoped recovery completes.
    if hasCorruptRecoveryPending { return true }
    return !(try await pendingScopesForCurrentAccount()).isEmpty
  }

  func record(_ scope: HerdSharingAcceptedShareImportScope) throws {
    if hasCorruptPersistedState {
      try backupAndResetCorruptStateForRecovery()
    }

    if hasCorruptRecoveryPending {
      if let candidate = corruptRecoveryCandidate(),
         Self.sameCorruptRecoveryCandidate(candidate, scope)
      {
        defaults.removeObject(forKey: corruptRecoveryPendingKey)
        defaults.removeObject(forKey: corruptRecoveryBackupPointerKey)
        defaults.removeObject(forKey: corruptRecoveryCandidateKey)
        persist([scope])
        immediateImportScope = scope
        return
      }

      persistCorruptRecoveryCandidate(scope)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The retained invitation identity was lost when corrupt recovery state was backed up. No CloudKit acceptance was attempted. This exact invitation has been staged as the proposed recovery target. Review its owner and root details, then press Accept Invitation again only if you deliberately want this same invitation to replace the lost recovery identity. Opening a different invitation will stage that different invitation instead and will not clear the recovery block."
      )
    }

    var scopes = try pendingScopes().filter { !Self.sameScope($0, scope) }
    scopes.append(scope)
    persist(scopes.sorted(by: Self.scopeSort))
    immediateImportScope = scope
  }

  @discardableResult
  func markAccepted(
    _ scope: HerdSharingAcceptedShareImportScope,
    participantAccountRecordName: String? = nil
  ) -> HerdSharingAcceptedShareImportScope {
    update(scope) {
      $0.markingAccepted(participantAccountRecordName: participantAccountRecordName)
    }
  }

  @discardableResult
  func recordRemoteAbsence(
    for scope: HerdSharingAcceptedShareImportScope,
    at date: Date
  ) -> HerdSharingAcceptedShareImportScope {
    update(scope) { $0.recordingRemoteAbsence(at: date) }
  }

  @discardableResult
  func clearRemoteAbsence(
    for scope: HerdSharingAcceptedShareImportScope
  ) -> HerdSharingAcceptedShareImportScope {
    update(scope) { $0.clearingRemoteAbsence() }
  }

  @discardableResult
  func retireLegacyScope(
    _ scope: HerdSharingAcceptedShareImportScope,
    forParticipantAccount accountRecordName: String
  ) -> HerdSharingAcceptedShareImportScope {
    update(scope) { $0.retiringForParticipantAccount(accountRecordName) }
  }

  func participantReference(
    for herdPublicID: UUID
  ) throws -> HerdSharingAcceptedParticipantReference? {
    try participantReferenceStore.recoverableReference(for: herdPublicID)
  }

  func hasConflictingParticipantReference(for herdPublicID: UUID) -> Bool {
    participantReferenceStore.hasConflictingReference(for: herdPublicID)
  }

  func replaceConflictingParticipantReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    try participantReferenceStore.replaceConflictingReferenceRecoverably(
      reference,
      for: herdPublicID
    )
  }

  func recordParticipantReference(
    _ scope: HerdSharingAcceptedShareImportScope,
    for herdPublicID: UUID
  ) {
    participantReferenceStore.record(
      HerdSharingAcceptedParticipantReference(scope: scope),
      for: herdPublicID
    )
  }

  func recordParticipantReference(
    rootRecordID: CKRecord.ID,
    participantAccountRecordName: String? = nil,
    for herdPublicID: UUID
  ) {
    participantReferenceStore.record(
      HerdSharingAcceptedParticipantReference(
        rootRecordID: rootRecordID,
        participantAccountRecordName: participantAccountRecordName
      ),
      for: herdPublicID
    )
  }

  func remove(_ scope: HerdSharingAcceptedShareImportScope) {
    guard let scopes = try? pendingScopes() else { return }
    persist(scopes.filter { !Self.sameScope($0, scope) })
    if let immediateImportScope, Self.sameScope(immediateImportScope, scope) {
      self.immediateImportScope = nil
    }
  }

  private func update(
    _ scope: HerdSharingAcceptedShareImportScope,
    transform: (HerdSharingAcceptedShareImportScope) -> HerdSharingAcceptedShareImportScope
  ) -> HerdSharingAcceptedShareImportScope {
    guard var scopes = try? pendingScopes() else { return scope }
    guard let index = scopes.firstIndex(where: { Self.sameScope($0, scope) }) else {
      return scope
    }
    let updated = transform(scopes[index])
    scopes[index] = updated
    persist(scopes.sorted(by: Self.scopeSort))
    if let immediateImportScope, Self.sameScope(immediateImportScope, scope) {
      self.immediateImportScope = updated
    }
    return updated
  }

  private func persist(_ scopes: [HerdSharingAcceptedShareImportScope]) {
    guard !scopes.isEmpty else {
      defaults.removeObject(forKey: storageKey)
      return
    }
    guard let data = try? JSONEncoder().encode(scopes) else { return }
    defaults.set(data, forKey: storageKey)
  }

  private func corruptRecoveryCandidate() -> HerdSharingAcceptedShareImportScope? {
    guard let data = defaults.data(forKey: corruptRecoveryCandidateKey) else { return nil }
    return try? JSONDecoder().decode(HerdSharingAcceptedShareImportScope.self, from: data)
  }

  private func persistCorruptRecoveryCandidate(_ scope: HerdSharingAcceptedShareImportScope) {
    guard let data = try? JSONEncoder().encode(scope) else { return }
    defaults.set(data, forKey: corruptRecoveryCandidateKey)
  }

  private var corruptRecoveryPendingKey: String {
    "\(storageKey).corruptRecoveryPending"
  }

  private var corruptRecoveryBackupPointerKey: String {
    "\(storageKey).corruptRecoveryBackupKey"
  }

  private var corruptRecoveryCandidateKey: String {
    "\(storageKey).corruptRecoveryCandidate"
  }

  nonisolated private static func sameScope(
    _ lhs: HerdSharingAcceptedShareImportScope,
    _ rhs: HerdSharingAcceptedShareImportScope
  ) -> Bool {
    lhs.rootRecordID == rhs.rootRecordID
  }

  nonisolated private static func sameCorruptRecoveryCandidate(
    _ lhs: HerdSharingAcceptedShareImportScope,
    _ rhs: HerdSharingAcceptedShareImportScope
  ) -> Bool {
    lhs.rootRecordID == rhs.rootRecordID
      && lhs.shareIdentifier == rhs.shareIdentifier
      && lhs.participantAccountRecordName == rhs.participantAccountRecordName
  }

  nonisolated private static func scopeSort(
    _ lhs: HerdSharingAcceptedShareImportScope,
    _ rhs: HerdSharingAcceptedShareImportScope
  ) -> Bool {
    if lhs.acceptedAt != rhs.acceptedAt {
      return lhs.acceptedAt < rhs.acceptedAt
    }
    if lhs.shareIdentifier != rhs.shareIdentifier {
      return lhs.shareIdentifier < rhs.shareIdentifier
    }
    if lhs.rootZoneOwnerName != rhs.rootZoneOwnerName {
      return lhs.rootZoneOwnerName < rhs.rootZoneOwnerName
    }
    if lhs.rootZoneName != rhs.rootZoneName {
      return lhs.rootZoneName < rhs.rootZoneName
    }
    return lhs.rootRecordName < rhs.rootRecordName
  }
}
