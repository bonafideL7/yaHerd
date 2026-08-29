import Foundation
import SwiftData

private extension HerdSharingAccess {
    var allowsPublicIDRepairBridgeMutation: Bool {
        guard canExportLocalChangesToBridge else { return false }
        return switch creationState {
        case .ready, .existingOwnerShare, .acceptedParticipantShare, .unresolvedBridgeRecord:
            true
        case .unknown, .conflictingBridgeRecords, .pendingBridgeOperation,
             .ownerStopCleanupPending, .ownershipConfirmationRequired,
             .ownerBridgeVerificationRequired, .notOwnedByCurrentDevice:
            false
        }
    }
}

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

struct PublicIDRepairBridgeRecordIdentity: Hashable, Sendable {
    let step: HerdSharingBridgeStep
    let publicID: UUID
}

struct PublicIDRepairBridgePreflight: Sendable {
    let fingerprint: String
    let recordIdentities: Set<PublicIDRepairBridgeRecordIdentity>
    let localRecordIdentities: Set<PublicIDRepairBridgeRecordIdentity>
    let snapshot: HerdSharingBridgeStoreSnapshot?

    init(
        fingerprint: String,
        recordIdentities: Set<PublicIDRepairBridgeRecordIdentity>,
        localRecordIdentities: Set<PublicIDRepairBridgeRecordIdentity> = [],
        snapshot: HerdSharingBridgeStoreSnapshot? = nil
    ) {
        self.fingerprint = fingerprint
        self.recordIdentities = recordIdentities
        self.localRecordIdentities = localRecordIdentities
        self.snapshot = snapshot
    }
}

@MainActor
protocol PublicIDRepairBridgeExporting: AnyObject {
    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight

    func translatedBridgePreflight(
        for herd: HerdSummary,
        preflight: PublicIDRepairBridgePreflight,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreflight

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

    func retirePreparedBridge(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws
}

extension PublicIDRepairBridgeExporting {
    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        PublicIDRepairBridgePreflight(
            fingerprint: try await captureBridgeFingerprint(for: herd, access: access),
            recordIdentities: []
        )
    }

    func translatedBridgePreflight(
        for herd: HerdSummary,
        preflight: PublicIDRepairBridgePreflight,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreflight {
        preflight
    }

    func retirePreparedBridge(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws {
        throw PublicIDRepairBridgeError.bridgeRetirementUnavailable(
            herdPublicID: herd.publicID
        )
    }
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

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        if let preflightReader = bridgeStore as? any PublicIDRepairBridgePreflightReading {
            return try await preflightReader.publicIDRepairPreflight(
                for: herd,
                expectedLocation: access.bridgeLocation
            )
        }
        return try await PublicIDRepairBridgePreflight(
            fingerprint: captureBridgeFingerprint(for: herd, access: access),
            recordIdentities: []
        )
    }

    func translatedBridgePreflight(
        for herd: HerdSummary,
        preflight: PublicIDRepairBridgePreflight,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreflight {
        guard let sourceSnapshot = preflight.snapshot else { return preflight }
        let adjustedSnapshot = try sourceSnapshot
            .applyingPublicIDRepairBridgeCollisionResolutions(report: report)
        let localExport = try await exportReader.makeExport(
            for: herd,
            storeDescription: "public-ID repair staged preflight"
        )
        let translatedSnapshot = try adjustedSnapshot.preparingForPublicIDRepairImport(
            report: report,
            localRepairedSnapshot: localExport.snapshot
        )
        return PublicIDRepairBridgePreflight(
            fingerprint: preflight.fingerprint,
            recordIdentities: translatedSnapshot.publicIDRepairRecordIdentities,
            localRecordIdentities: localLiveRecordIdentities(from: localExport.snapshot),
            snapshot: sourceSnapshot
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

    func retirePreparedBridge(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws {
        guard let retiringStore = bridgeStore as? any PublicIDRepairBridgeRetiringStore else {
            throw PublicIDRepairBridgeError.bridgeRetirementUnavailable(
                herdPublicID: herd.publicID
            )
        }
        guard let expectedFingerprint = target.bridgeFingerprint else {
            throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                herdPublicID: herd.publicID
            )
        }
        let expectedLocation = try bridgeLocation(for: target)
        guard bridgeLocationIdentity(access.bridgeLocation) == target.location else {
            throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                herdPublicID: herd.publicID,
                expected: target.location,
                actual: bridgeLocationIdentity(access.bridgeLocation)
            )
        }
        try await retiringStore.retirePublicIDRepairBridge(
            for: herd,
            expectedLocation: expectedLocation,
            expectedFingerprint: expectedFingerprint
        )
    }

    private func localLiveRecordIdentities(
        from snapshot: HerdSharingBridgeStoreSnapshot
    ) -> Set<PublicIDRepairBridgeRecordIdentity> {
        let liveSteps = HerdSharingBridgeStep.entitySteps.filter {
            $0 != .herd && $0 != .deletions
        }
        return Set(liveSteps.flatMap { step in
            snapshot.records(for: step).compactMap { record in
                record.parsedPublicID.map {
                    PublicIDRepairBridgeRecordIdentity(step: step, publicID: $0)
                }
            }
        })
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
    private let mutationAuthorityRepository: (any HerdSharingRepository)?
    private let storageMode: HerdStorageMode
    private let exporter: any PublicIDRepairBridgeExporting

    init(
        herdInventory: any PublicIDRepairHerdInventoryReading,
        sharingRepository: any HerdSharingRepository,
        mutationAuthorityRepository: (any HerdSharingRepository)? = nil,
        storageMode: HerdStorageMode,
        exporter: any PublicIDRepairBridgeExporting
    ) {
        self.herdInventory = herdInventory
        self.sharingRepository = sharingRepository
        self.mutationAuthorityRepository = mutationAuthorityRepository
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

        // Preparation is observation, not mutation authority. Read-only accepted shares must
        // remain visible so their identities can participate in collision discovery.
        for herd in herds {
            accessByHerdID[herd.publicID] = try await observedAccess(for: herd)
        }

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
            let currentAccess = try await observedAccess(for: herd)
            let expectedLocation = bridgeLocationIdentity(preflightAccess.bridgeLocation)
            let actualLocation = bridgeLocationIdentity(currentAccess.bridgeLocation)
            guard actualLocation == expectedLocation else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: expectedLocation,
                    actual: actualLocation
                )
            }
            let preflight = try await exporter.captureBridgePreflight(
                for: herd,
                access: currentAccess
            )
            targets.append(
                PublicIDRepairBridgeTargetIdentity(
                    herdPublicID: herd.publicID,
                    location: actualLocation,
                    bridgeFingerprint: preflight.fingerprint
                )
            )
        }

        return PublicIDRepairBridgePreparation(
            identity: bridgeIdentity,
            targets: targets
        )
    }

    func validateMutationAuthority(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreparation {
        let observed = try await observePreparedHerdsForMutationAuthority(
            preparation: preparation,
            report: report
        )
        let affectedHerdIDs = affectedBridgeHerdIDs(
            report: report,
            rawPreflightByHerdID: observed.rawPreflightByHerdID,
            preparedHerdIDs: Set(preparation.herdPublicIDs)
        )
        for herdID in affectedHerdIDs {
            guard let herd = observed.herdByID[herdID],
                  let access = observed.accessByHerdID[herdID] else {
                if let target = preparation.targets.first(where: { $0.herdPublicID == herdID }) {
                    throw PublicIDRepairBridgeResolutionRequired(
                        issues: [missingPreparedHerdRecoveryIssue(for: target)]
                    )
                }
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herdID
                )
            }
            try await requireMutationAuthority(observedAccess: access, for: herd)
        }
        return preparation
    }

    func rebasePendingRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws -> PublicIDRepairBridgePreparation {
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

        let currentHerds = uniqueHerds(try await herdInventory.fetchHerds())
        let existingTargets = Dictionary(
            uniqueKeysWithValues: preparation.targets.map { ($0.herdPublicID, $0) }
        )
        var rebasedTargets = preparation.targets
        rebasedTargets.reserveCapacity(max(preparation.targets.count, currentHerds.count))

        for herd in currentHerds {
            let access = try await observedAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            if let existing = existingTargets[herd.publicID] {
                guard isCompatibleConvergenceLocation(
                    expected: existing.location,
                    actual: actualLocation
                ) else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: herd.publicID,
                        expected: existing.location,
                        actual: actualLocation
                    )
                }
            } else {
                let preflight = try await exporter.captureBridgePreflight(
                    for: herd,
                    access: access
                )
                rebasedTargets.append(
                    PublicIDRepairBridgeTargetIdentity(
                        herdPublicID: herd.publicID,
                        location: actualLocation,
                        bridgeFingerprint: preflight.fingerprint
                    )
                )
            }
        }

        return PublicIDRepairBridgePreparation(
            identity: preparation.identity,
            targets: rebasedTargets
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
        let retiredMissingHerdIDs = try await recoverMissingPreparedHerdsIfRequested(
            preparation: preparation,
            report: report
        )
        let observedHerds = try await validatedConvergenceHerds(
            preparation: preparation,
            expectedTargetByHerdID: expectedTargetByHerdID,
            retiredMissingHerdIDs: retiredMissingHerdIDs
        )
        var accessByHerdID: [UUID: HerdSharingAccess] = [:]
        var rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight] = [:]
        var translatedPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight] = [:]

        // Observe every prepared Herd, including read-only bridges, before deciding which bridge
        // is mutable. This preserves cross-Herd collision discovery without granting write scope.
        for herd in observedHerds {
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

            let access = try await observedAccess(for: herd)
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

            accessByHerdID[herd.publicID] = access
            let rawPreflight = try await exporter.captureBridgePreflight(
                for: herd,
                access: access
            )
            rawPreflightByHerdID[herd.publicID] = rawPreflight
            translatedPreflightByHerdID[herd.publicID] = try await exporter
                .translatedBridgePreflight(
                    for: herd,
                    preflight: rawPreflight,
                    report: report
                )
        }

        try rejectCrossHerdBridgeIdentityCollisions(
            preflightByHerdID: translatedPreflightByHerdID,
            rawPreflightByHerdID: rawPreflightByHerdID,
            herds: observedHerds,
            report: report
        )

        let affectedHerdIDs = affectedBridgeHerdIDs(
            report: report,
            rawPreflightByHerdID: rawPreflightByHerdID,
            preparedHerdIDs: Set(preparation.herdPublicIDs)
        ).subtracting(retiredMissingHerdIDs)
        var importBaselineByHerdID: [UUID: String] = [:]
        for herd in observedHerds where affectedHerdIDs.contains(herd.publicID) {
            guard let access = accessByHerdID[herd.publicID],
                  let preflight = rawPreflightByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }
            try await requireMutationAuthority(observedAccess: access, for: herd)
            importBaselineByHerdID[herd.publicID] = preflight.fingerprint
            if access.bridgeLocation != .bridgeRecordMissing {
                try await exporter.importCurrentBridgeGraph(
                    for: herd,
                    access: access,
                    expectedFingerprint: preflight.fingerprint,
                    report: report
                )
            }
        }

        let convergedHerds = try await validatedConvergenceHerds(
            preparation: preparation,
            expectedTargetByHerdID: expectedTargetByHerdID,
            retiredMissingHerdIDs: retiredMissingHerdIDs
        )

        for herd in convergedHerds where affectedHerdIDs.contains(herd.publicID) {
            guard let expectedTarget = expectedTargetByHerdID[herd.publicID],
                  let baseline = importBaselineByHerdID[herd.publicID] else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }

            let access = try await observedAccess(for: herd)
            try await requireMutationAuthority(observedAccess: access, for: herd)
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

    private struct ObservedPreparedHerds {
        let herdByID: [UUID: HerdSummary]
        let accessByHerdID: [UUID: HerdSharingAccess]
        let rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight]
    }

    private func observePreparedHerdsForMutationAuthority(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> ObservedPreparedHerds {
        let inventoryHerds = try await herdInventory.fetchHerds()
        let currentHerdByID = Dictionary(
            uniqueKeysWithValues: uniqueHerds(inventoryHerds).map { ($0.publicID, $0) }
        )
        var herdByID: [UUID: HerdSummary] = [:]
        var accessByHerdID: [UUID: HerdSharingAccess] = [:]
        var rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight] = [:]

        // This is the pre-commit capability check. Duplicate Herd rows are expected to still share
        // their old ID here because the manifest-authorized local split has not committed yet.
        // Observe that one already-journaled bridge target by public ID without treating the
        // duplicate local rows as a second bridge identity. Post-commit convergence still uses the
        // strict duplicate-Herd guard below.
        for target in preparation.targets {
            guard target.location != .unspecified else {
                throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                    herdPublicID: target.herdPublicID
                )
            }

            let herd: HerdSummary
            let isPlannedReplacementTarget: Bool
            if let current = currentHerdByID[target.herdPublicID] {
                herd = current
                isPlannedReplacementTarget = false
            } else if let planned = plannedReplacementHerdSummary(
                for: target,
                report: report,
                inventoryHerds: inventoryHerds
            ) {
                herd = planned
                isPlannedReplacementTarget = true
            } else {
                throw PublicIDRepairBridgeResolutionRequired(
                    issues: [missingPreparedHerdRecoveryIssue(for: target)]
                )
            }

            let access = try await observedAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            if isPlannedReplacementTarget {
                // Before local commit the replacement Herd does not exist yet, so there cannot be
                // a legitimate pre-existing bridge for its manifest-final ID. Require the exact
                // missing-bridge state here rather than accepting an unrelated bridge with the
                // same ID. The real repaired Herd is fetched and revalidated again after commit.
                guard target.location == .bridgeRecordMissing,
                      actualLocation == .bridgeRecordMissing else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: herd.publicID,
                        expected: target.location,
                        actual: actualLocation
                    )
                }
            } else {
                guard isCompatibleConvergenceLocation(
                    expected: target.location,
                    actual: actualLocation
                ) else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: herd.publicID,
                        expected: target.location,
                        actual: actualLocation
                    )
                }
            }

            herdByID[herd.publicID] = herd
            accessByHerdID[herd.publicID] = access
            rawPreflightByHerdID[herd.publicID] = try await exporter.captureBridgePreflight(
                for: herd,
                access: access
            )
        }

        return ObservedPreparedHerds(
            herdByID: herdByID,
            accessByHerdID: accessByHerdID,
            rawPreflightByHerdID: rawPreflightByHerdID
        )
    }

    private func plannedReplacementHerdSummary(
        for target: PublicIDRepairBridgeTargetIdentity,
        report: PublicIDRepairReport,
        inventoryHerds: [HerdSummary]
    ) -> HerdSummary? {
        guard target.location == .bridgeRecordMissing,
              let mapping = report.manifest.recordMappings.first(where: {
                  $0.origin == .localSwiftData
                      && $0.entityType == .herd
                      && !$0.retainedOriginalID
                      && $0.finalPublicID == target.herdPublicID
              }) else {
            return nil
        }
        guard let source = inventoryHerds
            .filter({ $0.publicID == mapping.originalPublicID })
            .sorted(by: herdPortableSort)
            .first else {
            return nil
        }

        // CoreDataHerdSharingRepository resolves bridge location and permission exclusively by
        // Herd public ID. This summary is therefore only a capability-probe envelope for the
        // manifest-authoritative final ID; it is never persisted, exported, or used to choose the
        // local canonical Herd. The real post-commit Herd summary is required before convergence.
        return HerdSummary(
            publicID: mapping.finalPublicID,
            name: mapping.recordDescription,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt,
            schemaVersion: source.schemaVersion
        )
    }

    private func observePreparedHerds(
        preparation: PublicIDRepairBridgePreparation
    ) async throws -> ObservedPreparedHerds {
        let herds = try await validatedConvergenceHerds(
            preparation: preparation,
            expectedTargetByHerdID: Dictionary(
                uniqueKeysWithValues: preparation.targets.map { ($0.herdPublicID, $0) }
            )
        )
        var herdByID: [UUID: HerdSummary] = [:]
        var accessByHerdID: [UUID: HerdSharingAccess] = [:]
        var rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight] = [:]
        for herd in herds {
            guard let target = preparation.targets.first(where: {
                $0.herdPublicID == herd.publicID
            }) else {
                throw PublicIDRepairBridgeError.unpreparedHerdBridgeTarget(
                    herdPublicID: herd.publicID
                )
            }
            let access = try await observedAccess(for: herd)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)
            guard isCompatibleConvergenceLocation(
                expected: target.location,
                actual: actualLocation
            ) else {
                throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: target.location,
                    actual: actualLocation
                )
            }
            herdByID[herd.publicID] = herd
            accessByHerdID[herd.publicID] = access
            rawPreflightByHerdID[herd.publicID] = try await exporter.captureBridgePreflight(
                for: herd,
                access: access
            )
        }
        return ObservedPreparedHerds(
            herdByID: herdByID,
            accessByHerdID: accessByHerdID,
            rawPreflightByHerdID: rawPreflightByHerdID
        )
    }

    private func affectedBridgeHerdIDs(
        report: PublicIDRepairReport,
        rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight],
        preparedHerdIDs: Set<UUID>
    ) -> Set<UUID> {
        var affected: Set<UUID> = []

        // Manifest ownership alone is not write authority. A prepared bridge is mutable only when
        // observation proves it still contains the pre-repair identity/reference that the durable
        // manifest authorizes us to change. A bridge already in final manifest state remains an
        // observed collision participant but is not an export target.
        for mapping in report.manifest.recordMappings where
            !mapping.retainedOriginalID && mapping.finalPublicID != mapping.originalPublicID {
            if mapping.origin == .localSwiftData, mapping.entityType == .herd {
                // Splitting a duplicate local Herd produces a new Herd ID. After local repair the
                // normal rebase records that final Herd as another prepared target. If no bridge
                // record exists for the final ID, that absence is the observed difference that
                // requires export. The old-ID bridge may belong to the retained canonical Herd,
                // so its mere presence must not make it writable for this replacement mapping.
                if preparedHerdIDs.contains(mapping.finalPublicID) {
                    let finalPreflight = rawPreflightByHerdID[mapping.finalPublicID]
                    let alreadyHasFinalHerd = finalPreflight?.snapshot?
                        .records(for: .herd)
                        .contains { $0.parsedPublicID == mapping.finalPublicID } == true
                    if !alreadyHasFinalHerd {
                        affected.insert(mapping.finalPublicID)
                    }
                }
                continue
            }

            if let owner = mapping.owningHerdPublicID,
               let preflight = rawPreflightByHerdID[owner],
               bridgeContainsManifestSource(mapping, preflight: preflight) {
                affected.insert(owner)
                continue
            }

            if mapping.owningHerdPublicID == nil {
                for (herdID, preflight) in rawPreflightByHerdID where
                    bridgeContainsManifestSource(mapping, preflight: preflight) {
                    affected.insert(herdID)
                }
            }
        }

        for transformation in report.manifest.referenceTransformations where
            transformation.previousPublicID != transformation.finalPublicID {
            if let owner = transformation.owningHerdPublicID,
               let preflight = rawPreflightByHerdID[owner],
               bridgeContainsManifestSource(
                    transformation,
                    preflight: preflight
               ) {
                affected.insert(owner)
                continue
            }

            if transformation.owningHerdPublicID == nil {
                for (herdID, preflight) in rawPreflightByHerdID where
                    bridgeContainsManifestSource(
                        transformation,
                        preflight: preflight
                    ) {
                    affected.insert(herdID)
                }
            }
        }

        // A collision in any observed bridge whose participant set touches an already-affected
        // Herd necessarily makes every participant part of the same convergence scope. This keeps
        // a read-only collision participant visible and blocks before an unsafe local commit.
        var herdIDsByIdentity: [PublicIDRepairBridgeRecordIdentity: Set<UUID>] = [:]
        for (herdID, preflight) in rawPreflightByHerdID {
            for identity in preflight.recordIdentities {
                herdIDsByIdentity[identity, default: []].insert(herdID)
            }
        }
        var changed = true
        while changed {
            changed = false
            for participants in herdIDsByIdentity.values where participants.count > 1 {
                guard !participants.isDisjoint(with: affected) else { continue }
                let previousCount = affected.count
                affected.formUnion(participants)
                if affected.count != previousCount { changed = true }
            }
        }

        return affected.intersection(preparedHerdIDs)
    }

    private func bridgeContainsManifestSource(
        _ mapping: PublicIDRepairManifestRecordMapping,
        preflight: PublicIDRepairBridgePreflight
    ) -> Bool {
        guard let step = publicIDRepairBridgeStep(for: mapping.entityType) else {
            return false
        }

        if step == .herd {
            guard let snapshot = preflight.snapshot else { return false }
            return snapshot.records(for: .herd).contains {
                $0.parsedPublicID == mapping.originalPublicID
            }
        }

        return preflight.recordIdentities.contains(
            PublicIDRepairBridgeRecordIdentity(
                step: step,
                publicID: mapping.originalPublicID
            )
        )
    }

    private func bridgeContainsManifestSource(
        _ transformation: PublicIDRepairManifestReferenceTransformation,
        preflight: PublicIDRepairBridgePreflight
    ) -> Bool {
        guard let snapshot = preflight.snapshot else { return false }

        if transformation.fieldName.hasPrefix("referencesTo:"),
           let previousPublicID = transformation.previousPublicID,
           let targetEntityType = manifestReferenceTargetEntityType(transformation) {
            for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
                for record in snapshot.records(for: step) {
                    for (attributeName, value) in record.attributes where
                        publicIDRepairReferencedEntityType(
                            entityName: record.entityName,
                            attributeName: attributeName
                        ) == targetEntityType
                        && bridgeReferenceValue(value, matches: previousPublicID) {
                        return true
                    }
                }
            }
            return false
        }

        if transformation.fieldName.hasPrefix("deletionTarget:"),
           let previousPublicID = transformation.previousPublicID,
           let targetEntityType = manifestReferenceTargetEntityType(transformation),
           let targetStep = publicIDRepairBridgeStep(for: targetEntityType) {
            return snapshot.records(for: .deletions).contains { tombstone in
                tombstone.parsedPublicID == previousPublicID
                    && tombstone.deletedSourceEntityNameForPublicIDRepair
                        == targetStep.coreDataEntityName
            }
        }

        guard let sourceEntityType = transformation.sourceEntityType,
              let sourceStep = publicIDRepairBridgeStep(for: sourceEntityType) else {
            return false
        }
        return snapshot.records(for: sourceStep).contains { record in
            guard let value = record.attributes[transformation.fieldName] else {
                return false
            }
            return bridgeReferenceValue(
                value,
                matches: transformation.previousPublicID
            )
        }
    }

    private func manifestReferenceTargetEntityType(
        _ transformation: PublicIDRepairManifestReferenceTransformation
    ) -> PublicIDRepairEntityType? {
        for prefix in ["referencesTo:", "deletionTarget:"] where
            transformation.fieldName.hasPrefix(prefix) {
            return PublicIDRepairEntityType(
                rawValue: String(transformation.fieldName.dropFirst(prefix.count))
            )
        }
        return nil
    }

    private func bridgeReferenceValue(
        _ value: HerdSharingBridgeAttributeValue,
        matches expectedPublicID: UUID?
    ) -> Bool {
        guard let expectedPublicID else {
            if case .null = value { return true }
            return false
        }
        guard case .string(let rawValue) = value else { return false }
        return UUID(uuidString: rawValue) == expectedPublicID
    }

    private func recoverMissingPreparedHerdsIfRequested(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> Set<UUID> {
        var currentHerdIDs = Set(try await herdInventory.fetchHerds().map(\.publicID))
        let explicitActions = (report.bridgeRecoveryActions ?? []).filter { action in
            switch action.kind {
            case .restoreMissingPreparedHerd, .retireIntentionallyDeletedPreparedHerd:
                true
            case .recoverMissingPreparedHerd:
                false
            }
        }
        let actionsByHerdID = Dictionary(grouping: explicitActions, by: \.herdPublicID)
        if let conflict = actionsByHerdID.first(where: { _, actions in
            Set(actions.map { $0.kind.rawValue }).count > 1
        }) {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair contains conflicting restore and intentional-deletion decisions for Herd \(conflict.key.uuidString). Convergence remains blocked rather than guess user intent."
            )
        }
        let actionByHerdID = actionsByHerdID.compactMapValues { $0.first?.kind }
        var retiredMissingHerdIDs: Set<UUID> = []

        for target in preparation.targets where target.location != .unspecified {
            guard !currentHerdIDs.contains(target.herdPublicID),
                  let action = actionByHerdID[target.herdPublicID] else {
                continue
            }

            let placeholder = HerdSummary(
                publicID: target.herdPublicID,
                name: "Recovered Herd",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                schemaVersion: 1
            )
            let access = try await observedAccess(for: placeholder)
            let actualLocation = bridgeLocationIdentity(access.bridgeLocation)

            switch action {
            case .restoreMissingPreparedHerd:
                guard actualLocation == target.location else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: target.herdPublicID,
                        expected: target.location,
                        actual: actualLocation
                    )
                }
                guard let expectedFingerprint = target.bridgeFingerprint else {
                    throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                        herdPublicID: target.herdPublicID
                    )
                }
                let preflight = try await exporter.captureBridgePreflight(
                    for: placeholder,
                    access: access
                )
                guard preflight.fingerprint == expectedFingerprint else {
                    throw PublicIDRepairBridgeError.bridgeContentChanged(
                        herdPublicID: target.herdPublicID
                    )
                }
                try await exporter.importCurrentBridgeGraph(
                    for: placeholder,
                    access: access,
                    expectedFingerprint: expectedFingerprint,
                    report: report
                )

                currentHerdIDs = Set(try await herdInventory.fetchHerds().map(\.publicID))
                guard currentHerdIDs.contains(target.herdPublicID) else {
                    throw PublicIDRepairBridgeError.preparedHerdMissing(
                        herdPublicID: target.herdPublicID
                    )
                }

            case .retireIntentionallyDeletedPreparedHerd:
                if actualLocation == .bridgeRecordMissing {
                    // The explicit destructive decision is already durable in the manifest, and
                    // exact observation proves there is no bridge graph left to mutate.
                    retiredMissingHerdIDs.insert(target.herdPublicID)
                    continue
                }
                guard actualLocation == target.location else {
                    throw PublicIDRepairBridgeError.bridgeTargetMismatch(
                        herdPublicID: target.herdPublicID,
                        expected: target.location,
                        actual: actualLocation
                    )
                }
                // A missing SwiftData Herd cannot pass the normal creation-state guard. This
                // destructive path instead remains bound to the user's exact durable retirement
                // decision plus the prepared location/fingerprint checks below.
                try requireObservedWritableAccess(access, for: placeholder)
                guard let expectedFingerprint = target.bridgeFingerprint else {
                    throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                        herdPublicID: target.herdPublicID
                    )
                }
                let preflight = try await exporter.captureBridgePreflight(
                    for: placeholder,
                    access: access
                )
                guard preflight.fingerprint == expectedFingerprint else {
                    throw PublicIDRepairBridgeError.bridgeContentChanged(
                        herdPublicID: target.herdPublicID
                    )
                }
                try await exporter.retirePreparedBridge(
                    for: placeholder,
                    access: access,
                    target: target
                )
                retiredMissingHerdIDs.insert(target.herdPublicID)

            case .recoverMissingPreparedHerd:
                break
            }
        }

        return retiredMissingHerdIDs
    }

    private func validatedConvergenceHerds(
        preparation: PublicIDRepairBridgePreparation,
        expectedTargetByHerdID: [UUID: PublicIDRepairBridgeTargetIdentity],
        retiredMissingHerdIDs: Set<UUID> = []
    ) async throws -> [HerdSummary] {
        let inventoryHerds = try await herdInventory.fetchHerds()
        try rejectAmbiguousDuplicateHerdTargets(in: inventoryHerds)
        let herds = uniqueHerds(inventoryHerds)
        let herdIDs = Set(herds.map(\.publicID))
        if let missingTarget = preparation.targets.first(where: {
            $0.location != .unspecified
                && !herdIDs.contains($0.herdPublicID)
                && !retiredMissingHerdIDs.contains($0.herdPublicID)
        }) {
            throw PublicIDRepairBridgeResolutionRequired(
                issues: [missingPreparedHerdRecoveryIssue(for: missingTarget)]
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

    private func missingPreparedHerdRecoveryIssue(
        for target: PublicIDRepairBridgeTargetIdentity
    ) -> PublicIDRepairUnresolvedReference {
        let issueStableID = [
            "prepared-herd-intent",
            target.herdPublicID.uuidString.lowercased(),
            target.location.rawValue,
        ].joined(separator: "|")
        let restoreStableID = [
            "restore-prepared-herd",
            target.herdPublicID.uuidString.lowercased(),
            target.location.rawValue,
        ].joined(separator: "|")
        let retireStableID = [
            "retire-prepared-herd",
            target.herdPublicID.uuidString.lowercased(),
            target.location.rawValue,
        ].joined(separator: "|")
        return PublicIDRepairUnresolvedReference(
            kind: .preparedHerdRecovery,
            entityType: .herd,
            recordDescription: "Missing prepared Herd",
            stableRecordIdentifier: issueStableID,
            fieldName: "preparedBridgeTarget",
            referencedPublicID: target.herdPublicID,
            reason: "This Herd is missing from SwiftData while its durable repair preparation still binds an exact shared bridge target. Neither store proves whether the Herd should be restored or was intentionally deleted. Choose the intended outcome; yaHerd will not infer it from stale bridge data or local absence.",
            candidates: [
                PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: restoreStableID,
                    recordDescription: "Restore missing Herd",
                    detail: "Restore only from this exact journaled bridge after its location and fingerprint are verified. No other bridge can be substituted.",
                    resultingPublicID: target.herdPublicID
                ),
                PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: retireStableID,
                    recordDescription: "Confirm intentional deletion",
                    detail: "Permanently retire only this exact journaled bridge graph after write authority, location, and fingerprint are verified. Live records and tombstones for this target must be gone before convergence can continue.",
                    resultingPublicID: target.herdPublicID
                ),
            ]
        )
    }

    private func observedAccess(
        for herd: HerdSummary
    ) async throws -> HerdSharingAccess {
        try await sharingRepository.fetchSharingAccess(
            for: herd,
            storageMode: storageMode
        )
    }

    private func requireMutationAuthority(
        observedAccess: HerdSharingAccess,
        for herd: HerdSummary
    ) async throws {
        let access: HerdSharingAccess
        if let mutationAuthorityRepository {
            access = try await mutationAuthorityRepository.fetchSharingAccess(
                for: herd,
                storageMode: storageMode
            )
            guard access.bridgeLocation == observedAccess.bridgeLocation else {
                throw PublicIDRepairBridgeError.bridgeTargetChangedDuringExport(
                    herdPublicID: herd.publicID,
                    expected: bridgeLocationIdentity(observedAccess.bridgeLocation),
                    actual: access.locationDescription
                )
            }
            guard access.canExportLocalChangesToBridge else {
                throw PublicIDRepairBridgeError.writePermissionRequired(
                    herdPublicID: herd.publicID,
                    permission: access.permissionDescription
                )
            }
            guard access.allowsPublicIDRepairBridgeMutation else {
                throw PublicIDRepairBridgeError.sharingRecoveryRequired(
                    herdPublicID: herd.publicID,
                    state: access.creationState.primaryActionTitle
                )
            }
        } else {
            // Compatibility for capability-level callers that already supply a repository whose
            // only contract is physical permission. App wiring must provide the guarded repository
            // above so durable sharing recovery state participates in mutation authorization.
            access = observedAccess
        }
        try requireObservedWritableAccess(access, for: herd)
    }

    private func requireObservedWritableAccess(
        _ access: HerdSharingAccess,
        for herd: HerdSummary
    ) throws {
        guard access.canExportLocalChangesToBridge else {
            throw PublicIDRepairBridgeError.writePermissionRequired(
                herdPublicID: herd.publicID,
                permission: access.permissionDescription
            )
        }
    }

    private func rejectCrossHerdBridgeIdentityCollisions(
        preflightByHerdID: [UUID: PublicIDRepairBridgePreflight],
        rawPreflightByHerdID: [UUID: PublicIDRepairBridgePreflight],
        herds: [HerdSummary],
        report: PublicIDRepairReport
    ) throws {
        var herdIDsByIdentity: [PublicIDRepairBridgeRecordIdentity: Set<UUID>] = [:]
        for (herdID, preflight) in preflightByHerdID {
            for identity in preflight.recordIdentities {
                herdIDsByIdentity[identity, default: []].insert(herdID)
            }
        }

        let collisions = herdIDsByIdentity
            .filter { $0.value.count > 1 }
            .sorted { lhs, rhs in
                if lhs.key.step.rawValue != rhs.key.step.rawValue {
                    return lhs.key.step.rawValue < rhs.key.step.rawValue
                }
                return lhs.key.publicID.uuidString < rhs.key.publicID.uuidString
            }
        guard let collision = collisions.first else { return }

        let affectedHerdIDs = collision.value.sorted { $0.uuidString < $1.uuidString }
        guard let entityType = publicIDRepairEntityType(for: collision.key.step) else {
            throw PublicIDRepairBridgeError.crossHerdBridgePublicIDCollision(
                step: collision.key.step,
                publicID: collision.key.publicID,
                herdPublicIDs: affectedHerdIDs
            )
        }

        let establishedResolution = report.bridgeCollisionResolutions?.first {
            $0.entityType == entityType && $0.retainedPublicID == collision.key.publicID
        }
        let liveLocalOwners = affectedHerdIDs.filter { herdID in
            preflightByHerdID[herdID]?.localRecordIdentities.contains(collision.key) == true
        }
        let authoritativeOwner: UUID?
        if let establishedResolution {
            guard affectedHerdIDs.contains(establishedResolution.selectedHerdPublicID) else {
                throw PublicIDRepairBridgeError.crossHerdBridgePublicIDCollision(
                    step: collision.key.step,
                    publicID: collision.key.publicID,
                    herdPublicIDs: affectedHerdIDs
                )
            }
            authoritativeOwner = establishedResolution.selectedHerdPublicID
        } else if liveLocalOwners.count == 1 {
            authoritativeOwner = liveLocalOwners[0]
        } else {
            authoritativeOwner = nil
        }

        let candidateHerdIDs = authoritativeOwner.map { [$0] } ?? affectedHerdIDs
        let herdByID = Dictionary(uniqueKeysWithValues: herds.map { ($0.publicID, $0) })
        let candidates = candidateHerdIDs.compactMap { herdID -> PublicIDRepairResolutionCandidate? in
            guard let herd = herdByID[herdID] else { return nil }
            let sourceRecord = rawPreflightByHerdID[herdID]?.snapshot?
                .records(for: collision.key.step)
                .first { $0.parsedPublicID == collision.key.publicID }
            let semanticRecord = sourceRecord?.publicIDRepairSemanticDescription(
                fallback: collision.key.step.displayName
            ) ?? collision.key.step.displayName
            let semanticDetail = sourceRecord?.publicIDRepairSemanticDetail ?? ""
            let herdContext = "\(herd.name), created \(herd.createdAt.formatted(date: .abbreviated, time: .omitted))"
            return PublicIDRepairResolutionCandidate(
                stableRecordIdentifier: [
                    "bridge-owner",
                    collision.key.step.rawValue,
                    collision.key.publicID.uuidString.lowercased(),
                    herdID.uuidString.lowercased(),
                ].joined(separator: "|"),
                recordDescription: "\(herdContext) — \(semanticRecord)",
                detail: semanticDetail.isEmpty
                    ? "Keep this Herd's shared record on the historical public ID."
                    : "Keep this Herd's shared record on the historical public ID. \(semanticDetail)",
                resultingPublicID: herdID
            )
        }
        guard candidates.count == candidateHerdIDs.count else {
            throw PublicIDRepairBridgeError.crossHerdBridgePublicIDCollision(
                step: collision.key.step,
                publicID: collision.key.publicID,
                herdPublicIDs: affectedHerdIDs
            )
        }

        let reason: String
        if establishedResolution != nil {
            reason = "A durable earlier repair choice already establishes which Herd keeps this historical public ID. yaHerd will preserve that owner and extend the deterministic replacement mapping only to Herds proven to own the colliding record before import."
        } else if authoritativeOwner != nil {
            reason = "The repaired local graph uniquely identifies which Herd owns this historical public ID. yaHerd will preserve that owner and assign deterministic replacement IDs to the other proven shared-record owners before import."
        } else {
            reason = "This public ID exists in more than one Herd bridge and the repaired local graph does not identify which shared record should retain it. Choose the Herd whose record keeps the historical ID; the other proven record owners will receive deterministic replacement IDs before import."
        }

        throw PublicIDRepairBridgeResolutionRequired(
            issues: [
                PublicIDRepairUnresolvedReference(
                    kind: .bridgeRecordOwner,
                    entityType: entityType,
                    recordDescription: "Shared \(collision.key.step.displayName.lowercased()) collision",
                    stableRecordIdentifier: [
                        "bridge-collision",
                        collision.key.step.rawValue,
                        collision.key.publicID.uuidString.lowercased(),
                    ].joined(separator: "|"),
                    fieldName: "sharedBridgeOwner",
                    referencedPublicID: collision.key.publicID,
                    reason: reason,
                    candidates: candidates,
                    bridgeParticipantHerdPublicIDs: affectedHerdIDs
                )
            ]
        )
    }

    private func isCompatibleConvergenceLocation(
        expected: PublicIDRepairBridgeLocationIdentity,
        actual: PublicIDRepairBridgeLocationIdentity
    ) -> Bool {
        if expected == .bridgeRecordMissing {
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
    case sharingRecoveryRequired(herdPublicID: UUID, state: String)
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
    case crossHerdBridgePublicIDCollision(
        step: HerdSharingBridgeStep,
        publicID: UUID,
        herdPublicIDs: [UUID]
    )
    case unpreparedHerdBridgeTarget(herdPublicID: UUID)
    case bridgeRetirementUnavailable(herdPublicID: UUID)

    var errorDescription: String? {
        switch self {
        case .writePermissionRequired(let herdPublicID, let permission):
            "Herd \(herdPublicID.uuidString) has \(permission) shared-herd access and cannot rewrite its repaired bridge. Run repair from an owner or participant with read/write permission for every affected herd."
        case .sharingRecoveryRequired(let herdPublicID, let state):
            "Herd \(herdPublicID.uuidString) cannot rewrite its repaired bridge until its durable sharing recovery gate is cleared (\(state)). Complete that sharing recovery first, then retry public-ID repair."
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
            "Shared bridge data for herd \(herdPublicID.uuidString) changed after the repair baseline was captured. Convergence remains blocked so newer collaborator changes are not overwritten."
        case .preparedHerdMissing(let herdPublicID):
            "Herd \(herdPublicID.uuidString) was part of the public-ID repair bridge journal but could not be restored from its verified bridge target. Shared-data convergence remains blocked."
        case .duplicateHerdBridgeTargetAmbiguous(let herdPublicID, let recordCount):
            "Public-ID repair found \(recordCount) Herd records still sharing \(herdPublicID.uuidString) after local repair. Scan again in Sync Diagnostics and choose which Herd keeps the existing shared identity before retrying convergence."
        case .crossHerdBridgePublicIDCollision(let step, let publicID, let herdPublicIDs):
            "Public-ID repair found the same \(step.displayName.lowercased()) ID \(publicID.uuidString) in multiple herd bridges (\(herdPublicIDs.map(\.uuidString).joined(separator: ", "))). No bridge data was imported. Resolve the shared-data collision before retrying repair convergence."
        case .unpreparedHerdBridgeTarget(let herdPublicID):
            "Herd \(herdPublicID.uuidString) appeared without a durable public-ID repair bridge target. Shared-data convergence remains blocked rather than guessing an owner/private versus accepted-shared store."
        case .bridgeRetirementUnavailable(let herdPublicID):
            "The exact prepared bridge for Herd \(herdPublicID.uuidString) cannot be retired by this bridge implementation. The destructive recovery decision remains journaled and convergence stays blocked."
        }
    }
}
