import CoreData
import Foundation

extension HerdSharingCoreDataStore {
    func publicIDRepairPreflight(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> PublicIDRepairBridgePreflight {
        try await loadIfNeeded()

        let privateRecord = try privateStore.flatMap {
            try fetchSharedHerdRecord(publicID: herd.publicID, in: $0)
        }
        let sharedRecord = try sharedStore.flatMap {
            try fetchSharedHerdRecord(publicID: herd.publicID, in: $0)
        }
        let actualDescription = publicIDRepairPreflightTargetDescription(
            privateRecordExists: privateRecord != nil,
            sharedRecordExists: sharedRecord != nil
        )

        let source: (store: NSPersistentStore, description: String)?
        switch expectedLocation {
        case .ownerPrivateStore:
            guard let privateStore, privateRecord != nil, sharedRecord == nil else {
                throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                    expected: "owner private store",
                    actual: actualDescription
                )
            }
            source = (privateStore, "owner private store")
        case .acceptedSharedStore:
            guard let sharedStore, sharedRecord != nil, privateRecord == nil else {
                throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                    expected: "accepted shared store",
                    actual: actualDescription
                )
            }
            source = (sharedStore, "accepted shared store")
        case .bridgeRecordMissing:
            guard privateRecord == nil, sharedRecord == nil else {
                throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                    expected: "no bridge record yet",
                    actual: actualDescription
                )
            }
            source = nil
        }

        guard let source else {
            return PublicIDRepairBridgePreflight(
                fingerprint: try await publicIDRepairFingerprint(
                    for: herd,
                    expectedLocation: expectedLocation
                ),
                recordIdentities: [],
                snapshot: nil
            )
        }

        let snapshot = try await readBridgeSnapshot(
            from: source.store,
            requestedHerdPublicID: herd.publicID,
            storeDescription: source.description
        )
        return PublicIDRepairBridgePreflight(
            fingerprint: snapshot.publicIDRepairFingerprint,
            recordIdentities: snapshot.publicIDRepairRecordIdentities,
            snapshot: snapshot
        )
    }

    private func publicIDRepairPreflightTargetDescription(
        privateRecordExists: Bool,
        sharedRecordExists: Bool
    ) -> String {
        switch (privateRecordExists, sharedRecordExists) {
        case (false, false):
            "no bridge record"
        case (true, false):
            "owner private store"
        case (false, true):
            "accepted shared store"
        case (true, true):
            "both owner private and accepted shared stores"
        }
    }
}