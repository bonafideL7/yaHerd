import SwiftData

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
    private let herdRepository: any HerdRepository
    private let sharingRepository: any HerdSharingRepository
    private let storageMode: HerdStorageMode
    private let exporter: any PublicIDRepairBridgeExporting
    private var preparedHerd: HerdSummary?

    init(
        herdRepository: any HerdRepository,
        sharingRepository: any HerdSharingRepository,
        storageMode: HerdStorageMode,
        exporter: any PublicIDRepairBridgeExporting
    ) {
        self.herdRepository = herdRepository
        self.sharingRepository = sharingRepository
        self.storageMode = storageMode
        self.exporter = exporter
    }

    func prepareForRepair() async throws -> Bool {
        guard storageMode == .iCloud else {
            preparedHerd = nil
            return false
        }

        let herd = try requireCurrentHerd()
        let access = try await requireWritableAccess(for: herd)
        preparedHerd = herd

        // Import before scanning and repairing. This operation intentionally uses the
        // ungated base repository while the exclusive repair token is already held.
        if access.bridgeLocation != .bridgeRecordMissing {
            _ = try await sharingRepository.importSharedBridgeData(
                herd: herd,
                storageMode: storageMode
            )
        }
        return true
    }

    func convergeAfterRepair() async throws {
        guard storageMode == .iCloud else { return }
        let herd = try preparedHerd ?? requireCurrentHerd()
        let access = try await requireWritableAccess(for: herd)

        // Do not call normal sync here. Normal sync imports first and would reintroduce
        // obsolete identifiers from the bridge before the repaired graph is exported.
        let reconciliation = try await exporter.exportRepairedGraph(
            for: herd,
            access: access
        )
        guard !reconciliation.hasUnresolvedDifferences else {
            throw PublicIDRepairBridgeError.reconciliationFailed(reconciliation.summary)
        }
        preparedHerd = nil
    }

    private func requireCurrentHerd() throws -> HerdSummary {
        guard let herd = try herdRepository.fetchCurrentHerd() else {
            throw PublicIDRepairBridgeError.herdMissing
        }
        return herd
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
                access.permissionDescription
            )
        }
        return access
    }
}

enum PublicIDRepairBridgeError: LocalizedError, Equatable {
    case herdMissing
    case writePermissionRequired(String)
    case reconciliationFailed(String)

    var errorDescription: String? {
        switch self {
        case .herdMissing:
            "Public-ID repair cannot converge shared data because the current herd is unavailable."
        case .writePermissionRequired(let permission):
            "This device has \(permission) shared-herd access and cannot rewrite the repaired bridge. Run repair from the owner or a participant with read/write permission."
        case .reconciliationFailed(let summary):
            "The repaired SwiftData graph was exported, but bridge reconciliation did not pass. Normal edits and synchronization remain blocked. \(summary)"
        }
    }
}
