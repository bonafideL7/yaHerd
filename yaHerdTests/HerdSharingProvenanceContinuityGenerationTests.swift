import Foundation
import XCTest

@testable import yaHerd

@MainActor
extension HerdSharingProvenanceContinuityTests {
  func testLegacyRetirementWithoutGenerationAllowsFreshExplicitReacceptance() throws {
    let herdID = UUID()
    let referencePrefix = "ParticipantLegacyRetirement.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantLegacyRetirement.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearGenerationTestState(ubiquitous, herdID: herdID, referencePrefix: referencePrefix)
    }

    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    ubiquitous.set(true, forKey: "\(referenceKey).retired")
    ubiquitous.removeObject(forKey: "\(referencePrefix).detachment-generation")
    _ = ubiquitous.synchronize()

    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "legacy-retirement-root",
      rootZoneName: "legacy-retirement-zone",
      rootZoneOwnerName: "legacy-retirement-owner",
      participantAccountRecordName: "participant-account"
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )

    // Older app versions wrote the retirement tombstone without a generation. A deliberate new
    // acceptance after upgrade records the normalized legacy generation and may replace it.
    try referenceStore.recordExplicitAcceptanceBoundary(for: reference)
    try referenceStore.recordExplicitlyAcceptedRecoverably(reference, for: herdID)

    XCTAssertFalse(ubiquitous.bool(forKey: "\(referenceKey).retired"))
    XCTAssertNil(ubiquitous.string(forKey: "\(referencePrefix).detachment-generation"))
    XCTAssertEqual(try referenceStore.recoverableReference(for: herdID), reference)
  }

  func testFailedNewerDetachGenerationCannotBeSatisfiedByOlderTombstone() throws {
    let herdID = UUID()
    let referencePrefix = "ParticipantPendingGeneration.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantPendingGeneration.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearGenerationTestState(ubiquitous, herdID: herdID, referencePrefix: referencePrefix)
    }

    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    let generationKey = "\(referencePrefix).detachment-generation"
    ubiquitous.set("older-generation", forKey: generationKey)
    ubiquitous.set(true, forKey: "\(referenceKey).retired")
    _ = ubiquitous.synchronize()

    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "pending-generation-root",
      rootZoneName: "pending-generation-zone",
      rootZoneOwnerName: "pending-generation-owner",
      participantAccountRecordName: "participant-account"
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    try referenceStore.recordExplicitAcceptanceBoundary(for: reference)

    // Model a newer detach that persisted its exact local pending generation but failed before KVS
    // replaced the older generation. The old tombstone must not be accepted as proof of the newer
    // detach's durability.
    let pendingKey = "\(referenceKey).retirement-write-pending"
    defaults.set("newer-generation", forKey: pendingKey)

    XCTAssertThrowsError(
      try referenceStore.recordExplicitlyAcceptedRecoverably(reference, for: herdID)
    ) { error in
      guard let actionError = error as? HerdSharingActionError,
            case .bridgeConsistencyFailed(let message) = actionError
      else {
        return XCTFail("Expected incomplete detach mirroring to fail closed, got \(error)")
      }
      XCTAssertTrue(message.contains("has not finished mirroring to iCloud"))
    }

    XCTAssertEqual(defaults.string(forKey: pendingKey), "newer-generation")
    XCTAssertTrue(ubiquitous.bool(forKey: "\(referenceKey).retired"))
    XCTAssertEqual(ubiquitous.string(forKey: generationKey), "older-generation")
  }

  private func clearGenerationTestState(
    _ store: NSUbiquitousKeyValueStore,
    herdID: UUID,
    referencePrefix: String
  ) {
    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    store.removeObject(forKey: referenceKey)
    store.removeObject(forKey: "\(referenceKey).recovery")
    store.removeObject(forKey: "\(referenceKey).retired")
    store.removeObject(forKey: "\(referencePrefix).detachment-generation")
    _ = store.synchronize()
  }
}
