import Foundation

@MainActor
final class MirroredHerdSharingOwnerShareReferenceStore: HerdSharingOwnerShareReferenceRecording {
    private struct StoredValue {
        let source: String
        let value: String
        let reference: HerdSharingRemoteOwnerShareReference?
    }

    private struct RetirementBackupSnapshot: Codable, Equatable {
        let valuesBySource: [String: String]
    }

    private let ubiquitous: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        ubiquitous: NSUbiquitousKeyValueStore = .default,
        defaults: UserDefaults = .standard,
        keyPrefix: String = "HerdSharingOwnerShareReference"
    ) {
        self.ubiquitous = ubiquitous
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? {
        try? recoverableReference(for: herdPublicID)
    }

    func recoverableReference(
        for herdPublicID: UUID
    ) throws -> HerdSharingRemoteOwnerShareReference? {
        let storedValues = currentStoredValues(for: herdPublicID)
        guard !storedValues.isEmpty else { return nil }

        let decodedValues = storedValues.filter { $0.reference != nil }
        guard !decodedValues.isEmpty else {
            try prepareReferenceForRetirement(for: herdPublicID)
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "All retained owner-share provenance copies are corrupt or incompatible. The exact bytes were backed up and active provenance was left unchanged."
            )
        }

        let validReferences = decodedValues.compactMap(\.reference)
        guard let recoveredReference = preferredCompatibleReference(in: validReferences) else {
            try prepareReferenceForRetirement(for: herdPublicID)
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Retained owner-share provenance copies identify different CloudKit shares. The conflicting values were backed up and left unchanged."
            )
        }

        let corruptValues = storedValues.filter { $0.reference == nil }
        if !corruptValues.isEmpty {
            try backup(corruptValues, herdPublicID: herdPublicID)
        }
        try persist(recoveredReference, for: herdPublicID)
        return recoveredReference
    }

    func hasBackedUpUnusableReference(for herdPublicID: UUID) -> Bool {
        let storedValues = currentStoredValues(for: herdPublicID)
        guard !storedValues.isEmpty,
              let snapshot = loadRetirementBackupSnapshot(for: herdPublicID)
        else {
            return false
        }
        return snapshot == retirementBackupSnapshot(for: storedValues)
    }

    func prepareReferenceForRetirement(for herdPublicID: UUID) throws {
        let storedValues = currentStoredValues(for: herdPublicID)
        guard !storedValues.isEmpty else { return }
        let snapshot = retirementBackupSnapshot(for: storedValues)
        if loadRetirementBackupSnapshot(for: herdPublicID) == snapshot { return }

        try backup(storedValues, herdPublicID: herdPublicID)
        let data = try JSONEncoder().encode(snapshot)
        let snapshotKey = retirementBackupSnapshotKey(for: herdPublicID)
        defaults.set(data, forKey: snapshotKey)
        guard defaults.data(forKey: snapshotKey) == data else {
            defaults.removeObject(forKey: snapshotKey)
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Owner-share recovery evidence could not be marked as safely backed up. Active provenance was left unchanged and owner reset remains blocked."
            )
        }
    }

    func record(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) {
        try? recordRecoverably(reference, for: herdPublicID)
    }

    func recordRecoverably(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) throws {
        try preserveUnusableEvidenceBeforeReplacement(for: herdPublicID)
        try persist(reference, for: herdPublicID)
        guard try recoverableReference(for: herdPublicID) == reference else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Owner-share provenance did not survive a durable read-back. Owner-share authority was not committed."
            )
        }
    }

    func clearReference(for herdPublicID: UUID) {
        let primaryKey = key(for: herdPublicID)
        let recoveryKey = recoveryKey(for: herdPublicID)
        ubiquitous.removeObject(forKey: primaryKey)
        ubiquitous.removeObject(forKey: recoveryKey)
        defaults.removeObject(forKey: primaryKey)
        defaults.removeObject(forKey: recoveryKey)
        defaults.removeObject(forKey: retirementBackupSnapshotKey(for: herdPublicID))
        _ = ubiquitous.synchronize()
    }

    private func currentStoredValues(for herdPublicID: UUID) -> [StoredValue] {
        _ = ubiquitous.synchronize()
        let primaryKey = key(for: herdPublicID)
        let recoveryKey = recoveryKey(for: herdPublicID)
        return [
            storedValue(source: "ubiquitous-primary", value: ubiquitous.string(forKey: primaryKey)),
            storedValue(source: "defaults-primary", value: defaults.string(forKey: primaryKey)),
            storedValue(source: "ubiquitous-recovery", value: ubiquitous.string(forKey: recoveryKey)),
            storedValue(source: "defaults-recovery", value: defaults.string(forKey: recoveryKey)),
        ].compactMap { $0 }
    }

    private func preserveUnusableEvidenceBeforeReplacement(for herdPublicID: UUID) throws {
        if hasBackedUpUnusableReference(for: herdPublicID) { return }
        let storedValues = currentStoredValues(for: herdPublicID)
        guard !storedValues.isEmpty else { return }

        let decodedValues = storedValues.filter { $0.reference != nil }
        guard !decodedValues.isEmpty else {
            try backup(storedValues, herdPublicID: herdPublicID)
            return
        }

        let validReferences = decodedValues.compactMap(\.reference)
        if preferredCompatibleReference(in: validReferences) == nil {
            try backup(storedValues, herdPublicID: herdPublicID)
            return
        }

        let corruptValues = storedValues.filter { $0.reference == nil }
        if !corruptValues.isEmpty {
            try backup(corruptValues, herdPublicID: herdPublicID)
        }
    }

    private func storedValue(source: String, value: String?) -> StoredValue? {
        guard let value else { return nil }
        return StoredValue(source: source, value: value, reference: decode(value))
    }

    private func retirementBackupSnapshot(
        for storedValues: [StoredValue]
    ) -> RetirementBackupSnapshot {
        RetirementBackupSnapshot(
            valuesBySource: Dictionary(
                uniqueKeysWithValues: storedValues.map { ($0.source, $0.value) }
            )
        )
    }

    private func loadRetirementBackupSnapshot(
        for herdPublicID: UUID
    ) -> RetirementBackupSnapshot? {
        guard let data = defaults.data(forKey: retirementBackupSnapshotKey(for: herdPublicID)) else {
            return nil
        }
        return try? JSONDecoder().decode(RetirementBackupSnapshot.self, from: data)
    }

    private func preferredCompatibleReference(
        in references: [HerdSharingRemoteOwnerShareReference]
    ) -> HerdSharingRemoteOwnerShareReference? {
        guard let first = references.first else { return nil }
        guard references.dropFirst().allSatisfy({ sameCloudKitIdentity(first, $0) }) else {
            return nil
        }
        return references.first(where: { $0.shareURL != nil }) ?? first
    }

    private func sameCloudKitIdentity(
        _ lhs: HerdSharingRemoteOwnerShareReference,
        _ rhs: HerdSharingRemoteOwnerShareReference
    ) -> Bool {
        guard lhs.shareIdentifier == rhs.shareIdentifier else { return false }

        let lhsIsScoped = lhs.shareRecordZoneName != nil
            || lhs.shareRecordOwnerName != nil
            || lhs.shareOwnerAccountRecordName != nil
        let rhsIsScoped = rhs.shareRecordZoneName != nil
            || rhs.shareRecordOwnerName != nil
            || rhs.shareOwnerAccountRecordName != nil
        if lhsIsScoped || rhsIsScoped {
            return lhs.shareRecordZoneName == rhs.shareRecordZoneName
                && lhs.shareRecordOwnerName == rhs.shareRecordOwnerName
                && lhs.shareOwnerAccountRecordName == rhs.shareOwnerAccountRecordName
        }

        if let lhsURL = lhs.shareURL, let rhsURL = rhs.shareURL {
            return lhsURL == rhsURL
        }
        return true
    }

    private func persist(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) throws {
        guard let value = encode(reference) else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Owner-share provenance could not be encoded. Existing provenance was left unchanged."
            )
        }
        let primaryKey = key(for: herdPublicID)
        let recoveryKey = recoveryKey(for: herdPublicID)
        ubiquitous.set(value, forKey: primaryKey)
        ubiquitous.set(value, forKey: recoveryKey)
        defaults.set(value, forKey: primaryKey)
        defaults.set(value, forKey: recoveryKey)
        defaults.removeObject(forKey: retirementBackupSnapshotKey(for: herdPublicID))
        _ = ubiquitous.synchronize()
    }

    private func backup(
        _ storedValues: [StoredValue],
        herdPublicID: UUID
    ) throws {
        for stored in storedValues {
            let backupKey = "\(keyPrefix).recovery-backup.\(herdPublicID.uuidString.lowercased()).\(stored.source).\(UUID().uuidString.lowercased())"
            defaults.set(stored.value, forKey: backupKey)
            guard defaults.string(forKey: backupKey) == stored.value else {
                defaults.removeObject(forKey: backupKey)
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Owner-share provenance could not be backed up safely. Active provenance was left unchanged and owner reset remains blocked."
                )
            }
        }
    }

    private func encode(_ reference: HerdSharingRemoteOwnerShareReference) -> String? {
        guard let data = try? JSONEncoder().encode(reference) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decode(_ value: String) -> HerdSharingRemoteOwnerShareReference? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HerdSharingRemoteOwnerShareReference.self, from: data)
    }

    private func key(for herdPublicID: UUID) -> String {
        "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    }

    private func recoveryKey(for herdPublicID: UUID) -> String {
        "\(key(for: herdPublicID)).recovery"
    }

    private func retirementBackupSnapshotKey(for herdPublicID: UUID) -> String {
        "\(key(for: herdPublicID)).retirementBackupSnapshot"
    }
}
