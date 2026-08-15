import CoreData
import Foundation

@MainActor
protocol PublicIDRepairBridgeRetiringStore: AnyObject {
    func retirePublicIDRepairBridge(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws
}

extension HerdSharingCoreDataStore: PublicIDRepairBridgeRetiringStore {
    func retirePublicIDRepairBridge(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws {
        try await loadIfNeeded()

        if expectedLocation == .bridgeRecordMissing {
            let preflight = try await publicIDRepairPreflight(
                for: herd,
                expectedLocation: .bridgeRecordMissing
            )
            guard preflight.fingerprint == expectedFingerprint,
                  preflight.recordIdentities.isEmpty else {
                throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                    herdPublicID: herd.publicID
                )
            }
            return
        }

        let preflight = try await publicIDRepairPreflight(
            for: herd,
            expectedLocation: expectedLocation
        )
        guard preflight.fingerprint == expectedFingerprint else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }

        let selectedStore: NSPersistentStore
        switch expectedLocation {
        case .ownerPrivateStore:
            guard let privateStore else {
                throw HerdSharingActionError.sharingStoreUnavailable(
                    "The prepared owner-private bridge store is unavailable."
                )
            }
            selectedStore = privateStore
        case .acceptedSharedStore:
            guard let sharedStore else {
                throw HerdSharingActionError.sharingStoreUnavailable(
                    "The prepared accepted-shared bridge store is unavailable."
                )
            }
            selectedStore = sharedStore
        case .bridgeRecordMissing:
            return
        }

        guard let storeURL = selectedStore.url else {
            throw HerdSharingActionError.sharingStoreUnavailable(
                "The prepared public-ID repair bridge store has no persistent URL."
            )
        }

        let context = persistentContainer.newBackgroundContext()
        context.name = "HerdSharingBridge.PublicIDRepairRetirement"
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        context.transactionAuthor = "yaHerd.bridge.publicIDRepair.retire"

        try await context.perform {
            guard let targetStore = context.persistentStoreCoordinator?.persistentStores.first(where: {
                $0.url?.standardizedFileURL == storeURL.standardizedFileURL
            }) else {
                throw HerdSharingActionError.sharingStoreUnavailable(
                    "The exact prepared bridge store could not be resolved for retirement."
                )
            }

            // The durable preparation must identify one physical store. A graph with this Herd
            // identity in another bridge store makes destructive retirement ambiguous.
            for store in context.persistentStoreCoordinator?.persistentStores ?? [] where store != targetStore {
                if try Self.publicIDRepairRetirementRecordCount(
                    herdPublicID: herd.publicID,
                    in: context,
                    store: store
                ) > 0 {
                    throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                        expected: expectedLocation == .ownerPrivateStore
                            ? "owner private store only"
                            : "accepted shared store only",
                        actual: "matching Herd records exist in another bridge store"
                    )
                }
            }

            for step in HerdSharingBridgeStep.entitySteps.reversed() {
                guard let entityName = step.coreDataEntityName else { continue }
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                request.affectedStores = [targetStore]
                if step == .herd {
                    request.predicate = NSPredicate(
                        format: "publicID == %@",
                        herd.publicID.uuidString
                    )
                } else {
                    request.predicate = NSPredicate(
                        format: "herdPublicID == %@",
                        herd.publicID.uuidString
                    )
                }
                for record in try context.fetch(request) {
                    context.delete(record)
                }
            }

            if context.hasChanges {
                try context.save()
            }

            guard try Self.publicIDRepairRetirementRecordCount(
                herdPublicID: herd.publicID,
                in: context,
                store: targetStore
            ) == 0 else {
                throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                    herdPublicID: herd.publicID
                )
            }
        }
    }

    nonisolated private static func publicIDRepairRetirementRecordCount(
        herdPublicID: UUID,
        in context: NSManagedObjectContext,
        store: NSPersistentStore
    ) throws -> Int {
        var count = 0
        for step in HerdSharingBridgeStep.entitySteps {
            guard let entityName = step.coreDataEntityName else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [store]
            if step == .herd {
                request.predicate = NSPredicate(
                    format: "publicID == %@",
                    herdPublicID.uuidString
                )
            } else {
                request.predicate = NSPredicate(
                    format: "herdPublicID == %@",
                    herdPublicID.uuidString
                )
            }
            count += try context.count(for: request)
        }
        return count
    }
}
