import Foundation

@MainActor
protocol HerdSharingAcceptedParticipantReferenceDurablyRecording: AnyObject {
  func recordRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws

  func recordExplicitlyAcceptedRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws
}

@MainActor
protocol HerdSharingAcceptedParticipantExplicitAcceptanceRecording: AnyObject {
  func recordExplicitAcceptanceBoundary(
    for reference: HerdSharingAcceptedParticipantReference
  ) throws
}

/// Mirrors participant lineage across the current iCloud account while keeping device-owner
/// authorization local. Local legacy lineage is never copied into the currently signed-in account
/// merely because it was found in UserDefaults; only an authoritative participant operation calls
/// recordParticipant and publishes it. A durable detached value prevents a stale second device from
/// resurrecting participant authority after deliberate detachment.
final class MirroredHerdSharingOwnershipRegistry: HerdSharingOwnershipRecording {
  private enum ParticipantLineage: String {
    case participant
    case detached
  }

  private let local: UserDefaultsHerdSharingOwnershipRegistry
  private let defaults: UserDefaults
  private let ubiquitous: NSUbiquitousKeyValueStore
  private let participantKeyPrefix: String
  private let participantReferenceKeyPrefix: String

  init(
    defaults: UserDefaults = .standard,
    ubiquitous: NSUbiquitousKeyValueStore = .default,
    ownershipKeyPrefix: String = "HerdSharingOwnership",
    participantKeyPrefix: String = "HerdSharingParticipantLineage",
    participantReferenceKeyPrefix: String = "HerdSharingAcceptedParticipantReference"
  ) {
    local = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: ownershipKeyPrefix
    )
    self.defaults = defaults
    self.ubiquitous = ubiquitous
    self.participantKeyPrefix = participantKeyPrefix
    self.participantReferenceKeyPrefix = participantReferenceKeyPrefix
  }

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    _ = ubiquitous.synchronize()
    let localOwnership = local.ownership(for: herdPublicID)

    // The exact-reference retirement marker is stronger than a stale participant lineage write.
    // Check it before the lineage key so out-of-order KVS delivery cannot resurrect participation.
    if isParticipantReferenceRetired(for: herdPublicID) {
      if case .owner? = localOwnership {
        return localOwnership
      }
      local.recordDetachedParticipant(herdPublicID: herdPublicID)
      persistLineage(.detached, for: herdPublicID)
      return .detachedParticipant
    }

    if let rawValue = ubiquitous.string(forKey: participantKey(for: herdPublicID)),
       let lineage = ParticipantLineage(rawValue: rawValue)
    {
      switch lineage {
      case .participant:
        local.recordParticipant(herdPublicID: herdPublicID)
        return .participant
      case .detached:
        if case .owner? = localOwnership {
          return localOwnership
        }
        local.recordDetachedParticipant(herdPublicID: herdPublicID)
        return .detachedParticipant
      }
    }

    // An account-less local marker may belong to the previously signed-in iCloud account. Return it
    // for fail-closed local behavior, but do not publish it to the current account until CloudKit
    // verification reaches recordParticipant.
    return localOwnership
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {
    local.recordOwner(herdPublicID: herdPublicID, deviceID: deviceID)
    persistLineage(.detached, for: herdPublicID)
  }

  func recordParticipant(herdPublicID: UUID) {
    // Exact accepted-reference retirement is the monotonic detachment boundary. A stale access
    // evaluation may resume after another device detached the relationship, but it must not be able
    // to republish participant lineage. A deliberately accepted invitation first persists its exact
    // reference through recordExplicitlyAcceptedRecoverably, which clears this tombstone only at the
    // invitation-import commit boundary.
    if isParticipantReferenceRetired(for: herdPublicID) {
      local.recordDetachedParticipant(herdPublicID: herdPublicID)
      persistLineage(.detached, for: herdPublicID)
      return
    }

    local.recordParticipant(herdPublicID: herdPublicID)
    persistLineage(.participant, for: herdPublicID)
  }

  func recordDetachedParticipant(herdPublicID: UUID) {
    local.recordDetachedParticipant(herdPublicID: herdPublicID)

    // Commit the cross-device retirement boundary as part of the same ownership mutation. The outer
    // sharing repository subsequently removes retained reference bytes, but a process death between
    // these steps must still leave a tombstone that dominates stale participant writes.
    persistParticipantRetirementBoundary(for: herdPublicID)
    persistLineage(.detached, for: herdPublicID)
  }

  func clearOwnership(for herdPublicID: UUID) {
    local.clearOwnership(for: herdPublicID)
    persistLineage(.detached, for: herdPublicID)
  }

  private func persistLineage(_ lineage: ParticipantLineage, for herdPublicID: UUID) {
    ubiquitous.set(lineage.rawValue, forKey: participantKey(for: herdPublicID))
    _ = ubiquitous.synchronize()
  }

  private func persistParticipantRetirementBoundary(for herdPublicID: UUID) {
    let generation = UUID().uuidString.lowercased()
    defaults.set(generation, forKey: participantRetirementWritePendingKey(for: herdPublicID))
    _ = defaults.synchronize()

    ubiquitous.set(generation, forKey: participantDetachmentGenerationKey)
    ubiquitous.set(true, forKey: participantRetirementKey(for: herdPublicID))
    _ = ubiquitous.synchronize()

    if ubiquitous.bool(forKey: participantRetirementKey(for: herdPublicID)),
       ubiquitous.string(forKey: participantDetachmentGenerationKey) == generation
    {
      defaults.removeObject(forKey: participantRetirementWritePendingKey(for: herdPublicID))
      _ = defaults.synchronize()
    }
  }

  private func isParticipantReferenceRetired(for herdPublicID: UUID) -> Bool {
    if defaults.string(forKey: participantRetirementWritePendingKey(for: herdPublicID)) != nil {
      return true
    }
    _ = ubiquitous.synchronize()
    return ubiquitous.bool(forKey: participantRetirementKey(for: herdPublicID))
  }

  private func participantRetirementKey(for herdPublicID: UUID) -> String {
    "\(participantReferenceKeyPrefix).\(herdPublicID.uuidString.lowercased()).retired"
  }

  private func participantRetirementWritePendingKey(for herdPublicID: UUID) -> String {
    "\(participantReferenceKeyPrefix).\(herdPublicID.uuidString.lowercased()).retirement-write-pending"
  }

  private var participantDetachmentGenerationKey: String {
    "\(participantReferenceKeyPrefix).detachment-generation"
  }

  private func participantKey(for herdPublicID: UUID) -> String {
    "\(participantKeyPrefix).\(herdPublicID.uuidString.lowercased())"
  }
}

/// Keeps the exact accepted-root/account reference in device-local defaults and iCloud KVS.
/// Conflicting valid copies fail closed. Local-only legacy references are not copied into the
/// currently active iCloud account during a read; the verified CloudKit access path republishes them
/// through record(). A retirement tombstone prevents stale devices from re-uploading detached state.
@MainActor
final class MirroredHerdSharingAcceptedParticipantReferenceStore:
  HerdSharingAcceptedParticipantReferenceRecording,
  HerdSharingAcceptedParticipantReferenceDurablyRecording,
  HerdSharingAcceptedParticipantExplicitAcceptanceRecording
{
  private struct StoredValue {
    let source: String
    let data: Data
    let reference: HerdSharingAcceptedParticipantReference?
    let isUbiquitous: Bool
  }

  private static let noDetachmentGenerationToken = "no-detachment"

  private let defaults: UserDefaults
  private let ubiquitous: NSUbiquitousKeyValueStore
  private let keyPrefix: String

  init(
    defaults: UserDefaults = .standard,
    ubiquitous: NSUbiquitousKeyValueStore = .default,
    keyPrefix: String = "HerdSharingAcceptedParticipantReference"
  ) {
    self.defaults = defaults
    self.ubiquitous = ubiquitous
    self.keyPrefix = keyPrefix
  }

  func reference(for herdPublicID: UUID) -> HerdSharingAcceptedParticipantReference? {
    try? recoverableReference(for: herdPublicID)
  }

  func recoverableReference(
    for herdPublicID: UUID
  ) throws -> HerdSharingAcceptedParticipantReference? {
    if isRetired(for: herdPublicID) {
      clearLocalCopies(for: herdPublicID)
      defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
      return nil
    }

    guard !defaults.bool(forKey: mirrorWriteFailureKey(for: herdPublicID)) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted-share participant reference was written locally but did not survive the required iCloud mirror read-back. Participant authority remains blocked until the exact relationship is verified and mirrored again."
      )
    }

    let values = currentStoredValues(for: herdPublicID)
    guard !values.isEmpty else { return nil }

    let validReferences = uniqueReferences(in: values)
    guard let reference = validReferences.first else {
      try backup(values, for: herdPublicID)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The retained accepted-share participant provenance is corrupt on every redundant local and iCloud copy. The exact bytes were preserved, and participant state was not detached."
      )
    }
    guard validReferences.count == 1 else {
      try backup(values, for: herdPublicID)
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The redundant accepted-share participant provenance copies identify different CloudKit relationships. Every exact value was preserved, and participant state was not detached. Reopen the currently accepted share so yaHerd can establish one authoritative participant relationship before retrying detachment."
      )
    }

    let corruptValues = values.filter { $0.reference == nil }
    if !corruptValues.isEmpty {
      try backup(corruptValues, for: herdPublicID)
    }

    try persistLocal(reference, for: herdPublicID)
    if values.contains(where: { $0.isUbiquitous && $0.reference == reference }) {
      try persistUbiquitous(reference, for: herdPublicID, clearsRetirement: false)
    }
    return reference
  }

  func hasConflictingReference(for herdPublicID: UUID) -> Bool {
    guard !isRetired(for: herdPublicID) else { return false }
    return defaults.bool(forKey: mirrorWriteFailureKey(for: herdPublicID))
      || uniqueReferences(in: currentStoredValues(for: herdPublicID)).count > 1
  }

  func record(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) {
    // Keep the protocol's legacy nonthrowing surface for access backfill callers, but retain a
    // durable local failure marker so their required recoverableReference read-back cannot mistake
    // a successful UserDefaults write for successful cross-device persistence.
    guard !isRetired(for: herdPublicID) else {
      clearLocalCopies(for: herdPublicID)
      defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
      return
    }

    do {
      try recordRecoverably(reference, for: herdPublicID)
    } catch {
      defaults.set(true, forKey: mirrorWriteFailureKey(for: herdPublicID))
    }
  }

  func recordRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    guard !isRetired(for: herdPublicID) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The prior accepted-share provenance was deliberately retired. Ordinary access verification cannot reactivate participant state; accept the CloudKit invitation again first."
      )
    }
    try persistRecoverably(reference, for: herdPublicID, clearsRetirement: false)
    defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
  }

  func recordExplicitAcceptanceBoundary(
    for reference: HerdSharingAcceptedParticipantReference
  ) throws {
    let generation = currentDetachmentGenerationToken()
    let acceptanceKey = try explicitAcceptanceGenerationKey(for: reference)
    defaults.set(generation, forKey: acceptanceKey)
    _ = defaults.synchronize()
    guard defaults.string(forKey: acceptanceKey) == generation else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted invitation could not retain the participant-detachment generation needed for safe recovery. CloudKit acceptance was not started."
      )
    }
  }

  func recordExplicitlyAcceptedRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    let acceptanceKey = try explicitAcceptanceGenerationKey(for: reference)

    refreshRetirementWritePendingIfDurable(for: herdPublicID)
    if isRetired(for: herdPublicID) {
      guard defaults.string(forKey: retirementWritePendingKey(for: herdPublicID)) == nil else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Participant detachment has not finished mirroring to iCloud. The accepted invitation cannot supersede it yet."
        )
      }
      _ = ubiquitous.synchronize()
      let currentGeneration = currentDetachmentGenerationToken()
      guard let acceptedGeneration = defaults.string(forKey: acceptanceKey),
            acceptedGeneration == currentGeneration
      else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "This accepted invitation predates the current participant-detachment tombstone. Reopen and deliberately accept the invitation again before participant state can be reactivated."
        )
      }

      try persistExplicitlyAcceptedRecoverably(
        reference,
        for: herdPublicID,
        expectedDetachmentGeneration: acceptedGeneration
      )
    } else {
      try persistRecoverably(reference, for: herdPublicID, clearsRetirement: false)
    }

    defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
    defaults.removeObject(forKey: acceptanceKey)
  }

  func replaceConflictingReferenceRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    guard !isRetired(for: herdPublicID) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The prior accepted-share provenance was deliberately retired. Reaccept the CloudKit invitation before establishing a new participant relationship."
      )
    }
    let values = currentStoredValues(for: herdPublicID)
    let hasMirrorWriteFailure = defaults.bool(forKey: mirrorWriteFailureKey(for: herdPublicID))
    guard hasMirrorWriteFailure || uniqueReferences(in: values).count > 1 else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "No conflicting or incompletely mirrored accepted-share provenance is available for authoritative replacement. Participant state remains blocked."
      )
    }
    if !values.isEmpty {
      try backup(values, for: herdPublicID)
    }
    try persistRecoverably(reference, for: herdPublicID, clearsRetirement: false)
    defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
    guard try recoverableReference(for: herdPublicID) == reference else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The authoritative accepted-share provenance could not be persisted durably. Participant state remains blocked."
      )
    }
  }

  func clearReference(for herdPublicID: UUID) {
    // Set the exact expected generation locally before touching KVS. It remains set unless both the
    // new account-level generation and this Herd's retirement tombstone read back for that same
    // generation; an older already-present tombstone cannot satisfy a newer failed detach write.
    let generation = UUID().uuidString.lowercased()
    defaults.set(generation, forKey: retirementWritePendingKey(for: herdPublicID))
    _ = defaults.synchronize()

    clearLocalCopies(for: herdPublicID)
    defaults.removeObject(forKey: mirrorWriteFailureKey(for: herdPublicID))
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    ubiquitous.removeObject(forKey: primaryKey)
    ubiquitous.removeObject(forKey: recoveryKey)
    ubiquitous.set(generation, forKey: detachmentGenerationKey)
    ubiquitous.set(true, forKey: retirementKey(for: herdPublicID))
    _ = ubiquitous.synchronize()

    if ubiquitous.bool(forKey: retirementKey(for: herdPublicID)),
       ubiquitous.string(forKey: detachmentGenerationKey) == generation
    {
      defaults.removeObject(forKey: retirementWritePendingKey(for: herdPublicID))
      _ = defaults.synchronize()
    }
  }

  private func currentStoredValues(for herdPublicID: UUID) -> [StoredValue] {
    _ = ubiquitous.synchronize()
    guard !isRetired(for: herdPublicID) else {
      clearLocalCopies(for: herdPublicID)
      return []
    }
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    return [
      storedValue(
        source: "defaults-primary",
        data: defaults.data(forKey: primaryKey),
        isUbiquitous: false
      ),
      storedValue(
        source: "defaults-recovery",
        data: defaults.data(forKey: recoveryKey),
        isUbiquitous: false
      ),
      storedValue(
        source: "ubiquitous-primary",
        data: ubiquitous.data(forKey: primaryKey),
        isUbiquitous: true
      ),
      storedValue(
        source: "ubiquitous-recovery",
        data: ubiquitous.data(forKey: recoveryKey),
        isUbiquitous: true
      ),
    ].compactMap { $0 }
  }

  private func storedValue(
    source: String,
    data: Data?,
    isUbiquitous: Bool
  ) -> StoredValue? {
    guard let data else { return nil }
    return StoredValue(
      source: source,
      data: data,
      reference: try? JSONDecoder().decode(
        HerdSharingAcceptedParticipantReference.self,
        from: data
      ),
      isUbiquitous: isUbiquitous
    )
  }

  private func uniqueReferences(
    in values: [StoredValue]
  ) -> [HerdSharingAcceptedParticipantReference] {
    var references: [HerdSharingAcceptedParticipantReference] = []
    for reference in values.compactMap(\.reference) where !references.contains(reference) {
      references.append(reference)
    }
    return references
  }

  private func persistRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID,
    clearsRetirement: Bool
  ) throws {
    try persistLocal(reference, for: herdPublicID)
    try persistUbiquitous(
      reference,
      for: herdPublicID,
      clearsRetirement: clearsRetirement
    )
  }

  private func persistExplicitlyAcceptedRecoverably(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID,
    expectedDetachmentGeneration: String
  ) throws {
    try persistLocal(reference, for: herdPublicID)
    let data = try encoded(reference)
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    let retirementKey = retirementKey(for: herdPublicID)

    // Stage and verify the replacement provenance while the previous detach tombstone remains
    // authoritative. Also require the detachment generation to remain unchanged across both KVS
    // synchronization points so another detach racing this import always wins.
    ubiquitous.set(data, forKey: primaryKey)
    ubiquitous.set(data, forKey: recoveryKey)
    _ = ubiquitous.synchronize()
    guard ubiquitous.bool(forKey: retirementKey),
          detachmentGenerationMatches(expectedDetachmentGeneration),
          ubiquitous.data(forKey: primaryKey) == data,
          ubiquitous.data(forKey: recoveryKey) == data
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The explicitly accepted participant provenance did not survive iCloud read-back against the same detach generation. The prior detach tombstone remains authoritative."
      )
    }

    ubiquitous.removeObject(forKey: retirementKey)
    _ = ubiquitous.synchronize()
    guard !ubiquitous.bool(forKey: retirementKey),
          detachmentGenerationMatches(expectedDetachmentGeneration),
          ubiquitous.data(forKey: primaryKey) == data,
          ubiquitous.data(forKey: recoveryKey) == data
    else {
      ubiquitous.set(true, forKey: retirementKey)
      _ = ubiquitous.synchronize()
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The explicitly accepted participant provenance could not retire the prior detach tombstone durably. Participant authority was not committed."
      )
    }
  }

  private func persistLocal(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) throws {
    let data = try encoded(reference)
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    defaults.set(data, forKey: primaryKey)
    defaults.set(data, forKey: recoveryKey)
    guard defaults.data(forKey: primaryKey) == data,
          defaults.data(forKey: recoveryKey) == data
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Accepted-share participant provenance did not survive a durable local read-back. Participant authority was not committed."
      )
    }
  }

  private func persistUbiquitous(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID,
    clearsRetirement: Bool
  ) throws {
    let data = try encoded(reference)
    let primaryKey = key(for: herdPublicID)
    let recoveryKey = recoveryKey(for: herdPublicID)
    if clearsRetirement {
      ubiquitous.removeObject(forKey: retirementKey(for: herdPublicID))
    }
    ubiquitous.set(data, forKey: primaryKey)
    ubiquitous.set(data, forKey: recoveryKey)
    _ = ubiquitous.synchronize()
    guard !isRetired(for: herdPublicID),
          ubiquitous.data(forKey: primaryKey) == data,
          ubiquitous.data(forKey: recoveryKey) == data
    else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Accepted-share participant provenance did not survive an iCloud read-back. Participant authority was not committed."
      )
    }
  }

  private func encoded(_ reference: HerdSharingAcceptedParticipantReference) throws -> Data {
    do {
      return try JSONEncoder().encode(reference)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "Accepted-share participant provenance could not be encoded. Existing provenance was left unchanged."
      )
    }
  }

  private func backup(
    _ values: [StoredValue],
    for herdPublicID: UUID
  ) throws {
    for value in values {
      let backupKey =
        "\(keyPrefix).recovery-backup.\(herdPublicID.uuidString.lowercased()).\(value.source).\(UUID().uuidString.lowercased())"
      defaults.set(value.data, forKey: backupKey)
      guard defaults.data(forKey: backupKey) == value.data else {
        defaults.removeObject(forKey: backupKey)
        throw HerdSharingActionError.bridgeConsistencyFailed(
          "Accepted-share participant provenance could not be backed up. The active provenance was left unchanged and participant state remains blocked."
        )
      }
    }
  }

  private func clearLocalCopies(for herdPublicID: UUID) {
    defaults.removeObject(forKey: key(for: herdPublicID))
    defaults.removeObject(forKey: recoveryKey(for: herdPublicID))
  }

  private func refreshRetirementWritePendingIfDurable(for herdPublicID: UUID) {
    guard let pendingGeneration = defaults.string(
      forKey: retirementWritePendingKey(for: herdPublicID)
    ) else { return }
    _ = ubiquitous.synchronize()
    guard ubiquitous.bool(forKey: retirementKey(for: herdPublicID)),
          ubiquitous.string(forKey: detachmentGenerationKey) == pendingGeneration
    else { return }
    defaults.removeObject(forKey: retirementWritePendingKey(for: herdPublicID))
    _ = defaults.synchronize()
  }

  private func isRetired(for herdPublicID: UUID) -> Bool {
    if defaults.string(forKey: retirementWritePendingKey(for: herdPublicID)) != nil {
      return true
    }
    _ = ubiquitous.synchronize()
    return ubiquitous.bool(forKey: retirementKey(for: herdPublicID))
  }

  private func currentDetachmentGenerationToken() -> String {
    _ = ubiquitous.synchronize()
    return ubiquitous.string(forKey: detachmentGenerationKey)
      ?? Self.noDetachmentGenerationToken
  }

  private func detachmentGenerationMatches(_ expectedGeneration: String) -> Bool {
    let currentGeneration = ubiquitous.string(forKey: detachmentGenerationKey)
      ?? Self.noDetachmentGenerationToken
    return currentGeneration == expectedGeneration
  }

  private func explicitAcceptanceGenerationKey(
    for reference: HerdSharingAcceptedParticipantReference
  ) throws -> String {
    let data: Data
    do {
      data = try JSONEncoder().encode(reference)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The accepted invitation identity could not be encoded for detachment-generation tracking."
      )
    }
    return "\(keyPrefix).explicit-acceptance-generation.\(data.base64EncodedString())"
  }

  private var detachmentGenerationKey: String {
    "\(keyPrefix).detachment-generation"
  }

  private func key(for herdPublicID: UUID) -> String {
    "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
  }

  private func recoveryKey(for herdPublicID: UUID) -> String {
    "\(key(for: herdPublicID)).recovery"
  }

  private func retirementKey(for herdPublicID: UUID) -> String {
    "\(key(for: herdPublicID)).retired"
  }

  private func retirementWritePendingKey(for herdPublicID: UUID) -> String {
    "\(key(for: herdPublicID)).retirement-write-pending"
  }

  private func mirrorWriteFailureKey(for herdPublicID: UUID) -> String {
    "\(key(for: herdPublicID)).mirror-write-failed"
  }
}
