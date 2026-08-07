import Foundation
import SwiftData

protocol PublicIDRepairHerdInventoryReading: Sendable {
    func fetchHerds() async throws -> [HerdSummary]
}

@ModelActor
actor SwiftDataPublicIDRepairHerdInventory: PublicIDRepairHerdInventoryReading {
    func fetchHerds() throws -> [HerdSummary] {
        try modelContext.fetch(FetchDescriptor<Herd>())
            .map { $0.toSummary() }
            .sorted { $0.publicID.uuidString < $1.publicID.uuidString }
    }
}

@MainActor
protocol PublicIDRepairBridgeExporting: AnyObject {
    func exportRepairedGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> HerdSharingBridgeReconciliationReport
}

@MainActor
final class SwiftDataPublicIDRepairBridgeExporter: PublicIDRepairBridgeExporting {
    private let exportReader: any HerdSharingExportSnapshotReading
    private let bridgeStore: any HerdSharingBridgeSyncStore

    init(
        modelContainer: ModelContainer,
        exportReader: (any HerdSharingExportSnapshotReading)? = nil,
        bridgeStore: (any HerdSharingBridgeSyncStore)? = nil
    ) {
        self.exportReader = exportReader
            ?? SwiftDataHerdSharingActor(modelContainer: modelContainer)
        self.bridgeStore = bridgeStore ?? HerdSharingCoreDataStore()
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> HerdSharingBridgeReconciliationReport {
        let export = try await exportReader.makeExport(
            for: herd,
            storeDescription: "public-ID repair convergence: \(access.locationDescription)"
        )
        let result = try await bridgeStore.syncBridgeRecordsFromSnapshot(export)
        return result.reconciliationReport
    }
}

@MainActor
final class DefaultPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
    let bridgeIdentity: PublicIDRepairBridgeIdentity = .iCloud

    private let herdInventory: any PublicIDRepairHerdInventoryReading
    private let sharingRepository: any HerdSharingRepository
    private let storageMode: HerdStorageMode
    private let exporter: any PublicIDRepairBridgeExporting

    init(
        herdInventory: any PublicIDRepairHerdInventoryReading,
        sharingRepository: any HerdSharingRepository,
        storageMode: HerdStorageMode,
        exporter: any PublicIDRepairBridgeExporting
    ) {
        self.herdInventory = herdInventory
        self.sharingRepository = sharingRepository
        self.storageMode = storageMode
        self.exporter = exporter
    }

    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation {
        guard storageMode == .iCloud else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: .iCloud,
                actual: .localOnly
            )
        }

        let inventoryHerds = try await herdInventory.fetchHerds()
        try rejectAmbiguousDuplicateHerdTargets(in: inventoryHerds)
        let herds = uniqueHerds(inventoryHerds)
        var accessByHerdID: [UUID: HerdSharingAccess] = [:]

        // Preflight every herd before importing any bridge. The global repair can mutate
        // records from every herd, so one read-only bridge must block the whole operation.
        for herd in herds {
            accessByHerdID[herd.publicID] = try await requireWritableAccess(for: herd)
        }

        // Import all existing bridges while the exclusive repair gate is held. Missing
        // bridges are still journaled because convergence will create/update their bridge
        // representation from the repaired SwiftData graph.
        for herd in herds {
            guard let access = accessByHerdID[herd.publicID] else { continue }
            if access.bridgeLocation != .bridgeRecordMissing {
                _ = try await sharingRepository.importSharedBridgeData(
                    herd: herd,
                    storageMode: storageMode
                )
            }
        }

        return PublicIDRepairBridgePreparation(
            identity: bridgeIdentity,
            targets: herds.compactMap { herd in
                guard let access = accessByHerdID[herd.publicID] else { return nil }
                return PublicIDRepairBridgeTargetIdentity(
                    herdPublicID: herd.publicID,
                    location: bridgeLocationIdentity(access.bridgeLocation)
                )
            }
        )
    }

    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws {
        guard preparation.identity == bridgeIdentity else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: preparation.identity,
                actual: bridgeIdentity
            )
        }
        guard storageMode == .iCloud else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: .iCloud,
                actual: .localOnly
            )
        }

        let expectedTargetByHerdID = Dictionary(
            uniqueKeysWithValues: preparation.targets.map { ($0.herdPublicID, $0) }
        )

        // Refetch after repair rather than relying on pre-repair IDs. Duplicate Herd IDs are
        // rejected during preparation because the bridge cannot distinguish their physical
        // rows before repair. Any remaining herd therefore has one prepared bridge identity.
        let repairedHerds = uniqueHerds(try await herdInventory.fetchHerds())
        let repairedHerdIDs = Set(repairedHerds.map(\.publicID))
        if let missingTarget = preparation.targets.first(where: {
            $0.location != .unspecified && !repairedHerdIDs.contains($0.herdPublicID)
        }) {
            throw PublicIDRepairBridgeError.preparedHerdMissing(
                herdPublicID: missingTarget.herdPublicID
            )
        }

        for herd in repairedHerds {
            let access = try await requireWritableAccess(for: herd)
            if let expectedTarget = expectedTargetByHerdID[herd.publicID],
               expectedTarget.location != .unspecified {
                let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
                guard actualLocation == expectedTarget.location else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: herd.publicID,
                        expected: expectedTarget.location,
                        actual: actualLocation
                    )
                }
            }

            // Never call normal sync here. It imports first and can reintroduce obsolete IDs.
            let reconciliation = try await exporter.exportRepairedGraph(
                for: herd,
                access: access
            )
            guard !reconciliation.hasUnresolvedDifferences else {
                throw PublicIDRepairBridgeError.reconciliationFailed(
                    herdPublicID: herd.publicID,
                    summary: reconciliation.summary
                )
            }
        }
    }

    private func requireWritableAccess(
        for herd: HerdSummary
    ) async throws -> HerdSharingAccess {
        let access = try await sharingRepository.fetchSharingAccess(
            for: herd,
            storageMode: storageMode
        )
        guard access.canExportLocalChangesToBridge else {
            throw PublicIDRepairBridgeError.writePermissionRequired(
                herdPublicID: herd.publicID,
                permission: access.permissionDescription
            )
        }
        return access
    }

    private func rejectAmbiguousDuplicateHerdTargets(
        in herds: [HerdSummary]
    ) throws {
        let duplicateGroups = Dictionary(grouping: herds, by: \.publicID)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        guard let duplicate = duplicateGroups.first else { return }

        // Core Data bridge ownership/access is looked up by Herd.publicID. Before repair,
        // duplicate physical Herd rows with the same public ID are therefore indistinguishable
        // to the bridge. Guessing a target would let a read/write participant's reassigned row
        // fall through to the private owner store after it receives a new ID.
        throw PublicIDRepairBridgeError.duplicateHerdBridgeTargetAmbiguous(
            herdPublicID: duplicate.key,
            recordCount: duplicate.value.count
        )
    }

    private func bridgeLocationIdentity(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> PublicIDRepairBridgeLocationIdentity {
        switch location {
        case .bridgeRecordMissing: .bridgeRecordMissing
        case .ownerPrivateStore: .ownerPrivateStore
        case .acceptedSharedStore: .acceptedSharedStore
        }
    }

    private func uniqueHerds(_ herds: [HerdSummary]) -> [HerdSummary] {
        Dictionary(grouping: herds, by: \.publicID)
            .values
            .compactMap { group in
                group.sorted(by: herdPortableSort).first
            }
            .sorted { $0.publicID.uuidString < $1.publicID.uuidString }
    }

    private func herdPortableSort(_ lhs: HerdSummary, _ rhs: HerdSummary) -> Bool {
        let lhsKey = [
            lhs.name,
            String(lhs.createdAt.timeIntervalSinceReferenceDate),
            String(lhs.updatedAt.timeIntervalSinceReferenceDate),
            String(lhs.schemaVersion),
        ].joined(separator: "|")
        let rhsKey = [
            rhs.name,
            String(rhs.createdAt.timeIntervalSinceReferenceDate),
            String(rhs.updatedAt.timeIntervalSinceReferenceDate),
            String(rhs.schemaVersion),
        ].joined(separator: "|")
        return lhsKey < rhsKey
    }
}

enum PublicIDRepairBridgeError: LocalizedError, Equatable {
    case writePermissionRequired(herdPublicID: UUID, permission: String)
    case reconciliationFailed(herdPublicID: UUID, summary: String)
    case bridgeIdentityMismatch(
        expected: PublicIDRepairBridgeIdentity,
        actual: PublicIDRepairBridgeIdentity
    )
    case bridgeTargetMismatch(
        herdPublicID: UUID,
        expected: PublicIDRepairBridgeLocationIdentity,
        actual: PublicIDRepairBridgeLocationIdentity
    )
    case preparedHerdMissing(herdPublicID: UUID)
    case duplicateHerdBridgeTargetAmbiguous(herdPublicID: UUID, recordCount: Int)

    var errorDescription: String? {
        switch self {
        case .writePermissionRequired(let herdPublicID, let permission):
            "Herd \(herdPublicID.uuidString) has \(permission) shared-herd access and cannot rewrite its repaired bridge. Run repair from an owner or participant with read/write permission for every affected herd."
        case .reconciliationFailed(let herdPublicID, let summary):
            "The repaired SwiftData graph for herd \(herdPublicID.uuidString) was exported, but bridge reconciliation did not pass. Normal edits and synchronization remain blocked. \(summary)"
        case .bridgeIdentityMismatch(let expected, let actual):
            "Public-ID repair is waiting for the \(expected.rawValue) shared-data bridge, but this launch is using \(actual.rawValue) storage. Switch back to the original storage mode and retry repair convergence."
        case .bridgeTargetMismatch(let herdPublicID, let expected, let actual):
            "Public-ID repair was prepared against the \(expected.rawValue) bridge for herd \(herdPublicID.uuidString), but this launch sees \(actual.rawValue). Restore the original iCloud/share context before retrying convergence."
        case .preparedHerdMissing(let herdPublicID):
            "Herd \(herdPublicID.uuidString) was part of the public-ID repair bridge journal but is no longer present. Shared-data convergence remains blocked until the original herd graph is restored or repaired."
        case .duplicateHerdBridgeTargetAmbiguous(let herdPublicID, let recordCount):
            "Public-ID repair found \(recordCount) Herd records sharing \(herdPublicID.uuidString). The iCloud bridge identifies herd ownership by that same public ID, so it cannot safely determine which bridge target belongs to each physical duplicate. Repair was blocked before importing or changing shared data."
        }
    }
}
