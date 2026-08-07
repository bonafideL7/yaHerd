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

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport
}

@MainActor
final class SwiftDataPublicIDRepairBridgeExporter: PublicIDRepairBridgeExporting {
    private let exportReader: any HerdSharingExportSnapshotReading
    private let importer: any HerdSharingImportApplying
    private let bridgeStore: any PublicIDRepairBridgeStore

    init(
        modelContainer: ModelContainer,
        exportReader: (any HerdSharingExportSnapshotReading)? = nil,
        importer: (any HerdSharingImportApplying)? = nil,
        bridgeStore: (any PublicIDRepairBridgeStore)? = nil
    ) {
        let sharingActor = SwiftDataHerdSharingActor(modelContainer: modelContainer)
        self.exportReader = exportReader ?? sharingActor
        self.importer = importer ?? sharingActor
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

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        do {
            _ = try await bridgeStore.importPublicIDRepairBridgeRecordsIntoSwiftData(
                for: herd,
                expectedLocation: access.bridgeLocation,
                expectedFingerprint: expectedFingerprint,
                importer: importer,
                report: report
            )
        } catch let error as HerdSharingPublicIDRepairBridgeError {
            switch error {
            case .targetChanged(_, let actual):
                throw PublicIDRepairBridgeError.bridgeTargetChangedDuringExport(
                    herdPublicID: herd.publicID,
                    expected: bridgeLocationIdentity(access.bridgeLocation),
                    actual: actual
                )
            case .bridgeContentChanged:
                throw PublicIDRepairBridgeError.bridgeContentChanged(
                    herdPublicID: herd.publicID
                )
            }
        }
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

        // Building the local export is read-only. The bridge store then validates the exact
        // prepared location and accepts only the pre-import baseline or the exact desired
        // repaired snapshot from an earlier interrupted convergence attempt.
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

    private func bridgeLocationIdentity(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> PublicIDRepairBridgeLocationIdentity {
        switch location {
        case .bridgeRecordMissing: .bridgeRecordMissing
        case .ownerPrivateStore: .ownerPrivateStore
        case .acceptedSharedStore: .acceptedSharedStore
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
        let herds = uniqueHerds(inventoryHerds)
        var accessByHerdID: [UUID: HerdSharingAccess] = [:]

        // Duplicate physical Herd rows intentionally collapse by public ID during preflight.
        // Diagnostics chooses which physical Herd keeps that shared identity during the local
        // repair transaction. Bridge ownership/access itself is keyed by the public ID, so this
        // read-only preflight is safe before that choice is applied.
        for herd in herds {
            accessByHerdID[herd.publicID] = try await requireWritableAccess(for: herd)
        }

        // Do not use the normal importer here. It correctly rejects duplicate SwiftData public
        // IDs, which is precisely the state this repair exists to fix. The current bridge is
        // imported later, after the local repair commit has restored uniqueness and while the
        // durable mutation gate is still blocking ordinary edits and synchronization.
        let postPreflightInventory = try await herdInventory.fetchHerds()
        let postPreflightHerds = uniqueHerds(postPreflightInventory)
        let preflightIDs = Set(herds.map(\.publicID))
        if let unpreparedHerd = postPreflightHerds.first(where: {
            !preflightIDs.contains($0.publicID)
        }) {
            throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                herdPublicID: unpreparedHerd.publicID
            )
        }
        if let missingHerd = herds.first(where: { original in
            !postPreflightHerds.contains(where: { $0.publicID == original.publicID })
        }) {
            throw PublicIDRepairBridgeError.preparedHerdMissing(
                herdPublicID: missingHerd.publicID
            )
        }

        let postPreflightHerdByID = Dictionary(
            uniqueKeysWithValues: postPreflightHerds.map { ($0.publicID, $0) }
        )
        var targets: [PublicIDRepairBridgeTargetIdentity] = []
        targets.reserveCapacity(herds.count)

        // Persist the original bridge location and content baseline in the repair journal. A
        // later convergence imports the then-current bridge under an exact fingerprint before
        // exporting, so collaborator changes that arrive after this preparation are merged rather
        // than overwritten.
        for originalHerd in herds {
            guard let herd = postPreflightHerdByID[originalHerd.publicID] else {
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
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
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
        let repairedHerds = try validatedConvergenceHerds(
            preparation: preparation,
            expectedTargetByHerdID: expectedTargetByHerdID
        )
        var importBaselineByHerdID: [UUID: String] = [:]

        // Once the local repair commit has made public IDs unique, import the exact current
        // bridge using the production importer. Capture its fingerprint first and require that
        // same fingerprint at import and export boundaries so no collaborator change can be
        // overwritten in the gap between those operations.
        for herd in repairedHerds {
            guard let expectedTarget = expectedTargetByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }
            guard expectedTarget.location != .unspecified else {
                throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                    herdPublicID: herd.publicID
                )
            }

            let access = try await requireWritableAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            guard isCompatibleConvergenceLocation(
                expected: expectedTarget.location,
                actual: actualLocation
            ) else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: expectedTarget.location,
                    actual: actualLocation
                )
            }

            let baseline = try await exporter.captureBridgeFingerprint(
                for: herd,
                access: access
            )
            importBaselineByHerdID[herd.publicID] = baseline
            if access.bridgeLocation != .bridgeRecordMissing {
                try await exporter.importCurrentBridgeGraph(
                    for: herd,
                    access: access,
                    expectedFingerprint: baseline,
                    report: report
                )
            }
        }

        // The bridge import can add/update shared records. Re-read the Herd inventory before
        // export and verify that the local repair still produced exactly the journaled root set.
        let convergedHerds = try validatedConvergenceHerds(
            preparation: preparation,
            expectedTargetByHerdID: expectedTargetByHerdID
        )

        for herd in convergedHerds {
            guard let expectedTarget = expectedTargetByHerdID[herd.publicID],
                  let baseline = importBaselineByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }

            let access = try await requireWritableAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            guard isCompatibleConvergenceLocation(
                expected: expectedTarget.location,
                actual: actualLocation
            ) else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: expectedTarget.location,
                    actual: actualLocation
                )
            }

            let runtimeTarget = PublicIDRepairBridgeTargetIdentity(
                herdPublicID: expectedTarget.herdPublicID,
                location: expectedTarget.location,
                bridgeFingerprint: baseline
            )
            let reconciliation = try await exporter.exportRepairedGraph(
                for: herd,
                target: runtimeTarget
            )
            guard !reconciliation.hasUnresolvedDifferences else {
                throw PublicIDRepairBridgeError.reconciliationFailed(
                    herdPublicID: herd.publicID,
                    summary: reconciliation.summary
                )
            }
        }
    }

    private func validatedConvergenceHerds(
        preparation: PublicIDRepairBridgePreparation,
        expectedTargetByHerdID: [UUID: PublicIDRepairBridgeTargetIdentity]
    ) async throws -> [HerdSummary] {
        let inventoryHerds = try await herdInventory.fetchHerds()
        try rejectAmbiguousDuplicateHerdTargets(in: inventoryHerds)
        let herds = uniqueHerds(inventoryHerds)
        let herdIDs = Set(herds.map(\.publicID))
        if let missingTarget = preparation.targets.first(where: {
            $0.location != .unspecified && !herdIDs.contains($0.herdPublicID)
        }) {
            throw PublicIDRepairBridgeError.preparedHerdMissing(
                herdPublicID: missingTarget.herdPublicID
            )
        }
        if let unpreparedHerd = herds.first(where: {
            expectedTargetByHerdID[$0.publicID] == nil
        }) {
            throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                herdPublicID: unpreparedHerd.publicID
            )
        }
        return herds
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

    private func isCompatibleConvergenceLocation(
        expected: PublicIDRepairBridgeLocationIdentity,
        actual: PublicIDRepairBridgeLocationIdentity
    ) -> Bool {
        if expected == .bridgeRecordMissing {
            // A successful earlier convergence attempt legitimately transitions a missing bridge
            // to the owner-private store. The exporter still requires its content to equal the
            // exact captured baseline or desired repaired snapshot before accepting recovery.
            return actual == .bridgeRecordMissing || actual == .ownerPrivateStore
        }
        return actual == expected
    }

    private func rejectAmbiguousDuplicateHerdTargets(
        in herds: [HerdSummary]
    ) throws {
        let duplicateGroups = Dictionary(grouping: herds, by: \.publicID)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        guard let duplicate = duplicateGroups.first else { return }

        // Reaching convergence with duplicate Herd roots means the local repair did not finish
        // or a new duplicate arrived after the commit. Do not guess at a bridge target; a fresh
        // diagnostics scan can surface the deliberate Herd canonical selection again.
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
            "Public-ID repair was prepared against the \(expected.rawValue) bridge for herd \(herdPublicID.uuidString), but the bridge changed to \(actual) while repaired convergence was running. No repair export was written."
        case .bridgeBaselineUnavailable(let herdPublicID):
            "The durable public-ID repair journal for herd \(herdPublicID.uuidString) does not contain a usable bridge target. Convergence remains blocked rather than risk overwriting shared data."
        case .bridgeContentChanged(let herdPublicID):
            "Shared bridge data for herd \(herdPublicID.uuidString) changed after the repair import baseline was captured. Convergence remains blocked so newer collaborator changes are not overwritten."
        case .preparedHerdMissing(let herdPublicID):
            "Herd \(herdPublicID.uuidString) was part of the public-ID repair bridge journal but is no longer present. Shared-data convergence remains blocked until the original herd graph is restored or repaired."
        case .duplicateHerdBridgeTargetAmbiguous(let herdPublicID, let recordCount):
            "Public-ID repair found \(recordCount) Herd records still sharing \(herdPublicID.uuidString) after local repair. Scan again in Sync Diagnostics and choose which Herd keeps the existing shared identity before retrying convergence."
        case .unpreparedHerdBridgeTarget(let herdPublicID):
            "Herd \(herdPublicID.uuidString) appeared without a durable public-ID repair bridge target. Shared-data convergence remains blocked rather than guessing an owner/private versus accepted-shared store."
        }
    }
}
