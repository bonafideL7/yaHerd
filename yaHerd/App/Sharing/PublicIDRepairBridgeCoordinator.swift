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
    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport
}

@MainActor
final class SwiftDataPublicIDRepairBridgeExporter: PublicIDRepairBridgeExporting {
    private let exportReader: any HerdSharingExportSnapshotReading
    private let bridgeStore: any PublicIDRepairBridgeStore

    init(
        modelContainer: ModelContainer,
        exportReader: (any HerdSharingExportSnapshotReading)? = nil,
        bridgeStore: (any PublicIDRepairBridgeStore)? = nil
    ) {
        self.exportReader = exportReader
            ?? SwiftDataHerdSharingActor(modelContainer: modelContainer)
        self.bridgeStore = bridgeStore ?? HerdSharingCoreDataStore()
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        try await bridgeStore.publicIDRepairFingerprint(
            for: herd,
            expectedLocation: access.bridgeLocation
        )
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        let expectedLocation = try bridgeLocation(for: target)
        guard let expectedFingerprint = target.bridgeFingerprint else {
            throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                herdPublicID: herd.publicID
            )
        }

        // Detect changes before spending time building the local export, then let the
        // specialized Core Data write path check again after that await and before writing.
        let currentFingerprint = try await bridgeStore.publicIDRepairFingerprint(
            for: herd,
            expectedLocation: expectedLocation
        )
        guard currentFingerprint == expectedFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }

        let export = try await exportReader.makeExport(
            for: herd,
            storeDescription: "public-ID repair convergence: \(target.location.rawValue)"
        )

        do {
            let result = try await bridgeStore.syncPublicIDRepairBridgeRecordsFromSnapshot(
                export,
                expectedLocation: expectedLocation,
                expectedFingerprint: expectedFingerprint
            )
            return result.reconciliationReport
        } catch let error as HerdSharingPublicIDRepairBridgeError {
            switch error {
            case .targetChanged(_, let actual):
                throw PublicIDRepairBridgeError.bridgeTargetChangedDuringExport(
                    herdPublicID: herd.publicID,
                    expected: target.location,
                    actual: actual
                )
            case .bridgeContentChanged:
                throw PublicIDRepairBridgeError.bridgeContentChanged(
                    herdPublicID: herd.publicID
                )
            }
        }
    }

    private func bridgeLocation(
        for target: PublicIDRepairBridgeTargetIdentity
    ) throws -> HerdSharingAccess.BridgeLocation {
        switch target.location {
        case .bridgeRecordMissing:
            return .bridgeRecordMissing
        case .ownerPrivateStore:
            return .ownerPrivateStore
        case .acceptedSharedStore:
            return .acceptedSharedStore
        case .unspecified:
            throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                herdPublicID: target.herdPublicID
            )
        }
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

        // A stale bridge import can itself reveal/create duplicate Herd rows after the first
        // preflight. Re-check before the repair worker is allowed to mutate SwiftData so a
        // newly ambiguous physical Herd is never repaired without a trustworthy bridge target.
        let postImportInventory = try await herdInventory.fetchHerds()
        try rejectAmbiguousDuplicateHerdTargets(in: postImportInventory)
        let postImportHerds = uniqueHerds(postImportInventory)
        let preflightIDs = Set(herds.map(\.publicID))
        if let unpreparedHerd = postImportHerds.first(where: {
            !preflightIDs.contains($0.publicID)
        }) {
            throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                herdPublicID: unpreparedHerd.publicID
            )
        }

        let postImportHerdByID = Dictionary(
            uniqueKeysWithValues: postImportHerds.map { ($0.publicID, $0) }
        )
        var targets: [PublicIDRepairBridgeTargetIdentity] = []
        targets.reserveCapacity(herds.count)

        // Capture the exact bridge contents that were imported. This baseline is persisted in
        // the durable repair journal and must still match before convergence may export.
        for originalHerd in herds {
            guard let herd = postImportHerdByID[originalHerd.publicID] else {
                throw PublicIDRepairBridgeError.preparedHerdMissing(
                    herdPublicID: originalHerd.publicID
                )
            }
            guard let preflightAccess = accessByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }
            let currentAccess = try await requireWritableAccess(for: herd)
            let expectedLocation = bridgeLocationIdentity(preflightAccess.bridgeLocation)
            let actualLocation = bridgeLocationIdentity(currentAccess.bridgeLocation)
            guard actualLocation == expectedLocation else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: expectedLocation,
                    actual: actualLocation
                )
            }
            let fingerprint = try await exporter.captureBridgeFingerprint(
                for: herd,
                access: currentAccess
            )
            targets.append(
                PublicIDRepairBridgeTargetIdentity(
                    herdPublicID: herd.publicID,
                    location: actualLocation,
                    bridgeFingerprint: fingerprint
                )
            )
        }

        return PublicIDRepairBridgePreparation(
            identity: bridgeIdentity,
            targets: targets
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

        // Refetch after repair rather than relying on pre-repair IDs. Do not collapse a
        // duplicate that appeared after preparation: bridge ownership is still keyed by the
        // duplicated public ID, so convergence must remain blocked rather than guess a store.
        let repairedInventoryHerds = try await herdInventory.fetchHerds()
        try rejectAmbiguousDuplicateHerdTargets(in: repairedInventoryHerds)
        let repairedHerds = uniqueHerds(repairedInventoryHerds)
        let repairedHerdIDs = Set(repairedHerds.map(\.publicID))
        if let missingTarget = preparation.targets.first(where: {
            $0.location != .unspecified && !repairedHerdIDs.contains($0.herdPublicID)
        }) {
            throw PublicIDRepairBridgeError.preparedHerdMissing(
                herdPublicID: missingTarget.herdPublicID
            )
        }

        // Current repair preparation rejects duplicate Herd roots, so the repair itself cannot
        // legitimately create a new Herd ID. Every herd exported during convergence must have
        // an exact, persisted pre-repair bridge target and content baseline.
        if let unpreparedHerd = repairedHerds.first(where: {
            expectedTargetByHerdID[$0.publicID] == nil
        }) {
            throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                herdPublicID: unpreparedHerd.publicID
            )
        }

        for herd in repairedHerds {
            guard let expectedTarget = expectedTargetByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }
            guard expectedTarget.location != .unspecified,
                  expectedTarget.bridgeFingerprint != nil else {
                throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                    herdPublicID: herd.publicID
                )
            }

            let access = try await requireWritableAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            guard actualLocation == expectedTarget.location else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: expectedTarget.location,
                    actual: actualLocation
                )
            }

            // Never call normal sync here. It imports first and can reintroduce obsolete IDs.
            let reconciliation = try await exporter.exportRepairedGraph(
                for: herd,
                target: expectedTarget
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

        // Core Data bridge ownership/access is looked up by Herd.publicID. Duplicate physical
        // Herd rows with the same public ID are therefore indistinguishable to the bridge.
        // Guessing a target could place a participant's reassigned row in the owner store.
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
    case bridgeTargetChangedDuringExport(
        herdPublicID: UUID,
        expected: PublicIDRepairBridgeLocationIdentity,
        actual: String
    )
    case bridgeBaselineUnavailable(herdPublicID: UUID)
    case bridgeContentChanged(herdPublicID: UUID)
    case preparedHerdMissing(herdPublicID: UUID)
    case duplicateHerdBridgeTargetAmbiguous(herdPublicID: UUID, recordCount: Int)
    case unpreparedHerdBridgeTarget(herdPublicID: UUID)

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
        case .bridgeTargetChangedDuringExport(let herdPublicID, let expected, let actual):
            "Public-ID repair was prepared against the \(expected.rawValue) bridge for herd \(herdPublicID.uuidString), but the bridge changed to \(actual) while the repaired export was being prepared. No repair export was written."
        case .bridgeBaselineUnavailable(let herdPublicID):
            "The durable public-ID repair journal for herd \(herdPublicID.uuidString) does not contain a verified pre-repair bridge fingerprint. Convergence remains blocked rather than risk overwriting shared data."
        case .bridgeContentChanged(let herdPublicID):
            "Shared bridge data for herd \(herdPublicID.uuidString) changed after public-ID repair preparation. Convergence remains blocked so newer collaborator changes are not overwritten."
        case .preparedHerdMissing(let herdPublicID):
            "Herd \(herdPublicID.uuidString) was part of the public-ID repair bridge journal but is no longer present. Shared-data convergence remains blocked until the original herd graph is restored or repaired."
        case .duplicateHerdBridgeTargetAmbiguous(let herdPublicID, let recordCount):
            "Public-ID repair found \(recordCount) Herd records sharing \(herdPublicID.uuidString). The iCloud bridge identifies herd ownership by that same public ID, so it cannot safely determine which bridge target belongs to each physical duplicate. Repair was blocked before importing or changing shared data."
        case .unpreparedHerdBridgeTarget(let herdPublicID):
            "Herd \(herdPublicID.uuidString) appeared after public-ID repair bridge preparation without a durable bridge target. Shared-data convergence remains blocked rather than guessing an owner/private versus accepted-shared store."
        }
    }
}
