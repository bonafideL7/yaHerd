import Foundation

/// Capability used by repair convergence to stage every bridge identity before any import.
@MainActor
protocol PublicIDRepairBridgePreflightReading: AnyObject {
    func publicIDRepairPreflight(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> PublicIDRepairBridgePreflight
}

extension HerdSharingCoreDataStore: PublicIDRepairBridgePreflightReading {}

/// Keeps repair-time bridge imports from re-homing records that now belong to a Herd root which
/// received a replacement public ID. The ordinary bridge importer intentionally applies every
/// record in a snapshot under that snapshot's Herd root, so duplicate-Herd repair must partition
/// the old shared graph by the repaired local ownership before invoking it.
@MainActor
final class PublicIDRepairOwnershipSafeBridgeStore: PublicIDRepairBridgeStore,
    PublicIDRepairBridgePreflightReading,
    PublicIDRepairBridgeRetiringStore
{
    private let base: HerdSharingCoreDataStore

    init(base: HerdSharingCoreDataStore = HerdSharingCoreDataStore()) {
        self.base = base
    }

    func publicIDRepairFingerprint(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> String {
        try await base.publicIDRepairFingerprint(
            for: herd,
            expectedLocation: expectedLocation
        )
    }

    func publicIDRepairPreflight(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> PublicIDRepairBridgePreflight {
        try await base.publicIDRepairPreflight(
            for: herd,
            expectedLocation: expectedLocation
        )
    }

    func retirePublicIDRepairBridge(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws {
        try await base.retirePublicIDRepairBridge(
            for: herd,
            expectedLocation: expectedLocation,
            expectedFingerprint: expectedFingerprint
        )
    }

    func importPublicIDRepairBridgeRecordsIntoSwiftData(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String,
        importer: any HerdSharingImportApplying,
        report: PublicIDRepairReport
    ) async throws -> HerdSharingBridgeImportResult {
        let preflight = try await base.publicIDRepairPreflight(
            for: herd,
            expectedLocation: expectedLocation
        )
        guard preflight.fingerprint == expectedFingerprint,
              let rawSourceSnapshot = preflight.snapshot else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        let sourceSnapshot = try rawSourceSnapshot
            .applyingPublicIDRepairBridgeCollisionResolutions(report: report)

        let replacementHerds = report.replacements
            .filter {
                $0.entityType == .herd
                    && $0.retainedPublicID == herd.publicID
            }
            .sorted { $0.replacementPublicID.uuidString < $1.replacementPublicID.uuidString }

        let repairImporter: any HerdSharingImportApplying
        if replacementHerds.isEmpty {
            repairImporter = importer
        } else {
            guard let exportReader = importer as? any HerdSharingExportSnapshotReading else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Public-ID repair could not inspect every repaired Herd before importing the shared graph. Convergence remains blocked rather than move records between Herds."
                )
            }

            let repairedHerds = [herd] + replacementHerds.map { replacement in
                HerdSummary(
                    publicID: replacement.replacementPublicID,
                    name: replacement.recordDescription,
                    createdAt: report.completedAt,
                    updatedAt: report.completedAt,
                    schemaVersion: herd.schemaVersion
                )
            }
            repairImporter = PublicIDRepairPartitioningImporter(
                importer: importer,
                exportReader: exportReader,
                repairedHerds: repairedHerds
            )
        }

        return try await importRepairSnapshot(
            sourceSnapshot,
            importer: repairImporter,
            report: report,
            bridgeLocationDescription: bridgeLocationDescription(expectedLocation)
        )
    }

    func syncPublicIDRepairBridgeRecordsFromSnapshot(
        _ export: HerdSharingSwiftDataExport,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws -> HerdSharingBridgeExportResult {
        try await base.syncPublicIDRepairBridgeRecordsFromSnapshot(
            export,
            expectedLocation: expectedLocation,
            expectedFingerprint: expectedFingerprint
        )
    }

    private func importRepairSnapshot(
        _ sourceSnapshot: HerdSharingBridgeStoreSnapshot,
        importer: any HerdSharingImportApplying,
        report: PublicIDRepairReport,
        bridgeLocationDescription: String
    ) async throws -> HerdSharingBridgeImportResult {
        guard let exportReader = importer as? any HerdSharingExportSnapshotReading else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair could not read the repaired local graph before importing shared data. Convergence remains blocked rather than canonicalize duplicate bridge records without a portable mapping."
            )
        }
        let localExport = try await exportReader.makeExport(
            for: HerdSummary(
                publicID: sourceSnapshot.herdPublicID,
                name: "Public-ID repair import",
                createdAt: report.completedAt,
                updatedAt: report.completedAt,
                schemaVersion: 1
            ),
            storeDescription: "public-ID repair import mapping"
        )
        let snapshot = try sourceSnapshot.preparingForPublicIDRepairImportWithInvalidReferenceRecovery(
            report: report,
            localRepairedSnapshot: localExport.snapshot
        )

        if let revisionHydrator = importer as? any CollaborationRevisionHydrating {
            try await revisionHydrator.hydrateCollaborationRevisions(
                for: snapshot.herdPublicID
            )
        }

        let operation = try await base.operationCoordinator.begin(
            herdPublicID: snapshot.herdPublicID,
            direction: .importFromBridge,
            bridgeLocation: bridgeLocationDescription
        )

        do {
            let application = try await importer.applyImport(
                snapshot,
                pendingConflictReport: operation.pendingConflictReport,
                failureInjector: base.operationCoordinator.backgroundFailureInjector
            )
            await base.operationCoordinator.recordCommittedImportSuccess(
                completedSteps: application.completedSteps,
                conflictReport: application.result.conflictReport,
                operationID: operation.id,
                recordCounts: [:],
                reconciliationSummary: application.result.reconciliationSummary
            )
            return application.result
        } catch let committedFailure as HerdSharingSwiftDataCommittedImportFailure {
            await base.operationCoordinator.recordCommittedImportFailure(
                committedFailure,
                operationID: operation.id
            )
            throw committedFailure.underlyingError
        } catch {
            await base.operationCoordinator.fail(operationID: operation.id, error: error)
            throw error
        }
    }

    private func bridgeLocationDescription(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> String {
        switch location {
        case .bridgeRecordMissing: "no bridge record yet"
        case .ownerPrivateStore: "owner private store"
        case .acceptedSharedStore: "accepted shared store"
        }
    }
}

/// Presents a combined repaired-local graph to the existing public-ID translation logic, then
/// partitions the translated bridge snapshot back into one import per repaired Herd root.
private struct PublicIDRepairPartitioningImporter: HerdSharingImportApplying,
    HerdSharingExportSnapshotReading
{
    let importer: any HerdSharingImportApplying
    let exportReader: any HerdSharingExportSnapshotReading
    let repairedHerds: [HerdSummary]

    init(
        importer: any HerdSharingImportApplying,
        exportReader: any HerdSharingExportSnapshotReading,
        repairedHerds: [HerdSummary]
    ) {
        self.importer = importer
        self.exportReader = exportReader
        var byID: [UUID: HerdSummary] = [:]
        for herd in repairedHerds where byID[herd.publicID] == nil {
            byID[herd.publicID] = herd
        }
        self.repairedHerds = byID.values.sorted {
            $0.publicID.uuidString < $1.publicID.uuidString
        }
    }

    func makeExport(
        for requestedHerd: HerdSummary,
        storeDescription: String
    ) async throws -> HerdSharingSwiftDataExport {
        let exports = try await localExports(storeDescription: storeDescription)
        guard let requestedExport = exports.first(where: {
            $0.herd.publicID == requestedHerd.publicID
        }) else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair could not locate repaired Herd \(requestedHerd.publicID.uuidString) while preparing the shared import."
            )
        }

        var recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]] = [:]
        var publicIDsByStep: [HerdSharingBridgeStep: [UUID]] = [:]
        for step in HerdSharingBridgeStep.entitySteps {
            if step == .herd {
                recordsByStep[step] = requestedExport.snapshot.records(for: step)
                publicIDsByStep[step] = requestedExport.localPublicIDs[step, default: []]
            } else {
                recordsByStep[step] = exports.flatMap { $0.snapshot.records(for: step) }
                publicIDsByStep[step] = exports.flatMap { $0.localPublicIDs[step, default: []] }
            }
        }

        return HerdSharingSwiftDataExport(
            herd: requestedExport.herd,
            snapshot: HerdSharingBridgeStoreSnapshot(
                herdPublicID: requestedExport.herd.publicID,
                storeDescription: "\(storeDescription) — combined repaired Herd ownership",
                recordsByStep: recordsByStep
            ),
            localPublicIDs: publicIDsByStep
        )
    }

    func applyImport(
        _ snapshot: HerdSharingBridgeStoreSnapshot,
        pendingConflictReport: HerdSharingBridgeConflictReport?,
        failureInjector: HerdSharingBridgeFailureInjector
    ) async throws -> HerdSharingSwiftDataImportApplication {
        let exports = try await localExports(
            storeDescription: "public-ID repair ownership partition"
        )
        let partitions = try snapshot.partitioningPublicIDRepairImportByLocalOwnership(
            localRepairedSnapshots: exports.map(\.snapshot)
        )

        var applications: [HerdSharingSwiftDataImportApplication] = []
        for partition in partitions {
            do {
                if let revisionHydrator = importer as? any CollaborationRevisionHydrating {
                    try await revisionHydrator.hydrateCollaborationRevisions(
                        for: partition.herdPublicID
                    )
                }
                let application = try await importer.applyImport(
                    partition,
                    pendingConflictReport: partition.herdPublicID == snapshot.herdPublicID
                        ? pendingConflictReport
                        : nil,
                    failureInjector: failureInjector
                )
                applications.append(application)
            } catch let committedFailure as HerdSharingSwiftDataCommittedImportFailure {
                guard !applications.isEmpty else { throw committedFailure }
                throw HerdSharingSwiftDataCommittedImportFailure(
                    underlyingError: committedFailure.underlyingError,
                    conflictReport: mergedConflictReport(
                        applications.map(\.result.conflictReport)
                            + [committedFailure.conflictReport]
                    ),
                    completedSteps: mergedCompletedSteps(
                        applications.flatMap(\.completedSteps)
                            + committedFailure.completedSteps
                    )
                )
            } catch {
                guard !applications.isEmpty else { throw error }
                throw HerdSharingSwiftDataCommittedImportFailure(
                    underlyingError: error,
                    conflictReport: mergedConflictReport(
                        applications.map(\.result.conflictReport)
                    ),
                    completedSteps: mergedCompletedSteps(
                        applications.flatMap(\.completedSteps)
                    )
                )
            }
        }

        guard !applications.isEmpty else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair produced no safe Herd partition for the shared import."
            )
        }
        return mergedApplication(applications)
    }

    private func localExports(
        storeDescription: String
    ) async throws -> [HerdSharingSwiftDataExport] {
        var exports: [HerdSharingSwiftDataExport] = []
        exports.reserveCapacity(repairedHerds.count)
        for herd in repairedHerds {
            let export = try await exportReader.makeExport(
                for: herd,
                storeDescription: storeDescription
            )
            guard export.herd.publicID == herd.publicID,
                  export.snapshot.records(for: .herd).count == 1,
                  export.snapshot.records(for: .herd).first?.parsedPublicID == herd.publicID else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Public-ID repair could not verify repaired Herd \(herd.publicID.uuidString) before importing shared data."
                )
            }
            exports.append(export)
        }
        return exports
    }

    private func mergedApplication(
        _ applications: [HerdSharingSwiftDataImportApplication]
    ) -> HerdSharingSwiftDataImportApplication {
        let results = applications.map(\.result)
        let first = results[0]
        let result = HerdSharingBridgeImportResult(
            herdName: first.herdName,
            insertedTagColorDefinitionCount: results.reduce(0) { $0 + $1.insertedTagColorDefinitionCount },
            updatedTagColorDefinitionCount: results.reduce(0) { $0 + $1.updatedTagColorDefinitionCount },
            insertedStatusReferenceCount: results.reduce(0) { $0 + $1.insertedStatusReferenceCount },
            updatedStatusReferenceCount: results.reduce(0) { $0 + $1.updatedStatusReferenceCount },
            insertedAnimalTagCount: results.reduce(0) { $0 + $1.insertedAnimalTagCount },
            updatedAnimalTagCount: results.reduce(0) { $0 + $1.updatedAnimalTagCount },
            insertedPastureGroupCount: results.reduce(0) { $0 + $1.insertedPastureGroupCount },
            updatedPastureGroupCount: results.reduce(0) { $0 + $1.updatedPastureGroupCount },
            insertedPastureCount: results.reduce(0) { $0 + $1.insertedPastureCount },
            updatedPastureCount: results.reduce(0) { $0 + $1.updatedPastureCount },
            insertedAnimalCount: results.reduce(0) { $0 + $1.insertedAnimalCount },
            updatedAnimalCount: results.reduce(0) { $0 + $1.updatedAnimalCount },
            insertedMovementCount: results.reduce(0) { $0 + $1.insertedMovementCount },
            updatedMovementCount: results.reduce(0) { $0 + $1.updatedMovementCount },
            insertedStatusRecordCount: results.reduce(0) { $0 + $1.insertedStatusRecordCount },
            updatedStatusRecordCount: results.reduce(0) { $0 + $1.updatedStatusRecordCount },
            insertedHealthRecordCount: results.reduce(0) { $0 + $1.insertedHealthRecordCount },
            updatedHealthRecordCount: results.reduce(0) { $0 + $1.updatedHealthRecordCount },
            insertedPregnancyCheckCount: results.reduce(0) { $0 + $1.insertedPregnancyCheckCount },
            updatedPregnancyCheckCount: results.reduce(0) { $0 + $1.updatedPregnancyCheckCount },
            insertedWorkingProtocolTemplateCount: results.reduce(0) { $0 + $1.insertedWorkingProtocolTemplateCount },
            updatedWorkingProtocolTemplateCount: results.reduce(0) { $0 + $1.updatedWorkingProtocolTemplateCount },
            insertedWorkingSessionCount: results.reduce(0) { $0 + $1.insertedWorkingSessionCount },
            updatedWorkingSessionCount: results.reduce(0) { $0 + $1.updatedWorkingSessionCount },
            insertedWorkingQueueItemCount: results.reduce(0) { $0 + $1.insertedWorkingQueueItemCount },
            updatedWorkingQueueItemCount: results.reduce(0) { $0 + $1.updatedWorkingQueueItemCount },
            insertedWorkingTreatmentRecordCount: results.reduce(0) { $0 + $1.insertedWorkingTreatmentRecordCount },
            updatedWorkingTreatmentRecordCount: results.reduce(0) { $0 + $1.updatedWorkingTreatmentRecordCount },
            insertedFieldCheckSessionCount: results.reduce(0) { $0 + $1.insertedFieldCheckSessionCount },
            updatedFieldCheckSessionCount: results.reduce(0) { $0 + $1.updatedFieldCheckSessionCount },
            insertedFieldCheckAnimalCheckCount: results.reduce(0) { $0 + $1.insertedFieldCheckAnimalCheckCount },
            updatedFieldCheckAnimalCheckCount: results.reduce(0) { $0 + $1.updatedFieldCheckAnimalCheckCount },
            insertedFieldCheckFindingCount: results.reduce(0) { $0 + $1.insertedFieldCheckFindingCount },
            updatedFieldCheckFindingCount: results.reduce(0) { $0 + $1.updatedFieldCheckFindingCount },
            deletedRecordCount: results.reduce(0) { $0 + $1.deletedRecordCount },
            conflictReport: mergedConflictReport(results.map(\.conflictReport)),
            reconciliationReport: mergedReconciliationReport(
                results.map(\.reconciliationReport)
            )
        )
        return HerdSharingSwiftDataImportApplication(
            result: result,
            completedSteps: mergedCompletedSteps(applications.flatMap(\.completedSteps))
        )
    }

    private func mergedConflictReport(
        _ reports: [HerdSharingBridgeConflictReport]
    ) -> HerdSharingBridgeConflictReport {
        HerdSharingBridgeConflictReport(
            existingLocalRecordUpdateCount: reports.reduce(0) {
                $0 + $1.existingLocalRecordUpdateCount
            },
            updatedRecordConflicts: reports.flatMap(\.updatedRecordConflicts),
            preventedDeleteConflicts: reports.flatMap(\.preventedDeleteConflicts)
        )
    }

    private func mergedReconciliationReport(
        _ reports: [HerdSharingBridgeReconciliationReport]
    ) -> HerdSharingBridgeReconciliationReport {
        let allEntities = reports.flatMap(\.entities)
        let entities = HerdSharingBridgeStep.entitySteps
            .filter { $0 != .deletions }
            .compactMap { step -> HerdSharingBridgeEntityReconciliation? in
                let matches = allEntities.filter { $0.step == step }
                guard !matches.isEmpty else { return nil }
                return HerdSharingBridgeEntityReconciliation(
                    step: step,
                    localRecordCount: matches.reduce(0) { $0 + $1.localRecordCount },
                    bridgeRecordCount: matches.reduce(0) { $0 + $1.bridgeRecordCount },
                    missingInBridge: uniqueSorted(matches.flatMap(\.missingInBridge)),
                    missingInSwiftData: uniqueSorted(matches.flatMap(\.missingInSwiftData)),
                    duplicateLocalPublicIDs: uniqueSorted(
                        matches.flatMap(\.duplicateLocalPublicIDs)
                    ),
                    duplicateBridgePublicIDs: uniqueSorted(
                        matches.flatMap(\.duplicateBridgePublicIDs)
                    )
                )
            }
        return HerdSharingBridgeReconciliationReport(
            entities: entities,
            deletionTombstoneCount: reports.reduce(0) {
                $0 + $1.deletionTombstoneCount
            }
        )
    }

    private func mergedCompletedSteps(
        _ steps: [HerdSharingBridgeStep]
    ) -> [HerdSharingBridgeStep] {
        var result: [HerdSharingBridgeStep] = []
        for step in steps where !result.contains(step) {
            result.append(step)
        }
        return result
    }

    private func uniqueSorted(_ values: [UUID]) -> [UUID] {
        Array(Set(values)).sorted { $0.uuidString < $1.uuidString }
    }
}

extension HerdSharingBridgeStoreSnapshot {
    /// Splits an already translated repair import snapshot according to the ownership in the
    /// repaired local Herd exports. A bridge-only record follows the unique Herd established by
    /// its repaired identity or translated ownership-bearing references; conflicting evidence is
    /// rejected rather than creating a cross-Herd relationship.
    func partitioningPublicIDRepairImportByLocalOwnership(
        localRepairedSnapshots: [HerdSharingBridgeStoreSnapshot]
    ) throws -> [HerdSharingBridgeStoreSnapshot] {
        var localSnapshotsByHerdID: [UUID: HerdSharingBridgeStoreSnapshot] = [:]
        for snapshot in localRepairedSnapshots {
            guard localSnapshotsByHerdID[snapshot.herdPublicID] == nil else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Public-ID repair found more than one repaired local snapshot for Herd \(snapshot.herdPublicID.uuidString)."
                )
            }
            localSnapshotsByHerdID[snapshot.herdPublicID] = snapshot
        }
        guard localSnapshotsByHerdID[herdPublicID] != nil else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair could not find the retained Herd's repaired local snapshot before shared import."
            )
        }

        var recordsByOwner: [UUID: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]]] = [:]
        for step in HerdSharingBridgeStep.entitySteps where step != .herd && step != .deletions {
            for record in records(for: step) {
                guard record.parsedPublicID != nil else {
                    throw HerdSharingActionError.bridgeConsistencyFailed(
                        "Public-ID repair found an invalid \(step.displayName) public ID while partitioning shared data."
                    )
                }
                let owner = try repairedOwner(
                    for: record,
                    step: step,
                    localSnapshots: localRepairedSnapshots
                ) ?? herdPublicID
                append(
                    record.rehomedForPublicIDRepair(to: owner),
                    step: step,
                    owner: owner,
                    into: &recordsByOwner
                )
            }
        }

        for tombstone in records(for: .deletions) {
            let owner = try repairedOwner(
                for: tombstone,
                localSnapshots: localRepairedSnapshots
            ) ?? herdPublicID
            append(
                tombstone.rehomedForPublicIDRepair(to: owner),
                step: .deletions,
                owner: owner,
                into: &recordsByOwner
            )
        }

        guard records(for: .herd).count == 1,
              let sourceRoot = records(for: .herd).first else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair expected exactly one retained Herd root in the translated shared snapshot."
            )
        }
        var sourceRecords = recordsByOwner[herdPublicID, default: [:]]
        sourceRecords[.herd] = [sourceRoot]
        recordsByOwner[herdPublicID] = sourceRecords

        for owner in recordsByOwner.keys where owner != herdPublicID {
            guard let localRootSnapshot = localSnapshotsByHerdID[owner],
                  localRootSnapshot.records(for: .herd).count == 1,
                  let root = localRootSnapshot.records(for: .herd).first,
                  root.parsedPublicID == owner else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Public-ID repair could not verify replacement Herd \(owner.uuidString) before partitioned shared import."
                )
            }
            var ownerRecords = recordsByOwner[owner, default: [:]]
            ownerRecords[.herd] = [root]
            recordsByOwner[owner] = ownerRecords
        }

        return recordsByOwner.keys.sorted { lhs, rhs in
            if lhs == herdPublicID { return true }
            if rhs == herdPublicID { return false }
            return lhs.uuidString < rhs.uuidString
        }.map { owner in
            HerdSharingBridgeStoreSnapshot(
                herdPublicID: owner,
                storeDescription: "\(storeDescription) — repaired ownership \(owner.uuidString)",
                recordsByStep: recordsByOwner[owner, default: [:]]
            )
        }
    }

    private func repairedOwner(
        for record: HerdSharingBridgeRecordSnapshot,
        step: HerdSharingBridgeStep,
        localSnapshots: [HerdSharingBridgeStoreSnapshot]
    ) throws -> UUID? {
        var owners = Set<UUID>()
        if let publicID = record.parsedPublicID,
           let directOwner = try repairedOwner(
               step: step,
               publicID: publicID,
               localSnapshots: localSnapshots
           ) {
            owners.insert(directOwner)
        }

        for (attributeName, value) in record.attributes {
            guard case .string(let rawPublicID) = value,
                  let referencedPublicID = UUID(uuidString: rawPublicID),
                  let referencedStep = publicIDRepairReferencedStep(
                      entityName: record.entityName,
                      attributeName: attributeName
                  ),
                  let referenceOwner = try repairedOwner(
                      step: referencedStep,
                      publicID: referencedPublicID,
                      localSnapshots: localSnapshots
                  ) else {
                continue
            }
            owners.insert(referenceOwner)
        }

        guard owners.count <= 1 else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair found \(step.displayName) \(record.publicID) with repaired references owned by different Herds. Shared import remains blocked rather than create a cross-Herd relationship."
            )
        }
        return owners.first
    }

    private func repairedOwner(
        step: HerdSharingBridgeStep,
        publicID: UUID,
        localSnapshots: [HerdSharingBridgeStoreSnapshot]
    ) throws -> UUID? {
        var owners = Set<UUID>()
        for snapshot in localSnapshots {
            if snapshot.records(for: step).contains(where: { $0.parsedPublicID == publicID }) {
                owners.insert(snapshot.herdPublicID)
            }
            if snapshot.records(for: .deletions).contains(where: { tombstone in
                tombstone.parsedPublicID == publicID
                    && tombstone.deletedSourceEntityNameForPublicIDRepair == step.coreDataEntityName
            }) {
                owners.insert(snapshot.herdPublicID)
            }
        }
        guard owners.count <= 1 else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair found \(step.displayName) \(publicID.uuidString) under more than one repaired Herd. Shared import remains blocked rather than choose an owner."
            )
        }
        return owners.first
    }

    private func repairedOwner(
        for tombstone: HerdSharingBridgeRecordSnapshot,
        localSnapshots: [HerdSharingBridgeStoreSnapshot]
    ) throws -> UUID? {
        guard let sourceEntityName = tombstone.deletedSourceEntityNameForPublicIDRepair,
              let sourceStep = HerdSharingBridgeStep.entitySteps.first(where: {
                  $0 != .deletions && $0.coreDataEntityName == sourceEntityName
              }),
              let publicID = tombstone.parsedPublicID else {
            return nil
        }
        return try repairedOwner(
            step: sourceStep,
            publicID: publicID,
            localSnapshots: localSnapshots
        )
    }

    private func append(
        _ record: HerdSharingBridgeRecordSnapshot,
        step: HerdSharingBridgeStep,
        owner: UUID,
        into recordsByOwner: inout [UUID: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]]]
    ) {
        var ownerRecords = recordsByOwner[owner, default: [:]]
        ownerRecords[step, default: []].append(record)
        recordsByOwner[owner] = ownerRecords
    }
}
