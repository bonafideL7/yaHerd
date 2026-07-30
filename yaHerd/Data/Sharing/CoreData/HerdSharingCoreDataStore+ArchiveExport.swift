import CloudKit
import CoreData
import Foundation

extension HerdSharingCoreDataStore {
    func syncBridgeArchive(
        _ archive: HerdSharingBridgeArchive
    ) async throws -> HerdSharingBridgeExportResult {
        try await loadIfNeeded()
        let operation = try operationCoordinator.begin(
            herdPublicID: archive.herd.publicID,
            direction: .exportToBridge,
            bridgeLocation: "owner private store"
        )

        do {
            let applyResult = try await operationCoordinator.execute(
                .persistentStoreCommit,
                operationID: operation.id
            ) {
                try await applyBridgeArchiveToPrivateStore(archive)
            }
            let records = try resolveArchiveRecords(applyResult.recordObjectIDURIs)
            guard let herdRecord = records.first(where: {
                $0.entity.name == SharedHerdRecord.entityName
            }) else {
                throw HerdSharingActionError.shareRootMissing
            }

            let existingShare = try existingShare(for: herdRecord)
            let updatedShare = try await operationCoordinator.execute(
                .cloudKitShareUpdate,
                operationID: operation.id
            ) {
                guard existingShare != nil else { return nil }
                return try await shareRecords(records, title: archive.herd.name)
            }
            if let updatedShare {
                await persistUpdatedShare(updatedShare)
            }

            let localPublicIDs = makeArchivePublicIDs(archive)
            let reconciliationReport = try operationCoordinator.execute(
                .reconciliation,
                operationID: operation.id
            ) {
                HerdSharingBridgeReconciler.makeReport(
                    localPublicIDs: localPublicIDs,
                    bridgePublicIDs: applyResult.bridgePublicIDs.filter {
                        $0.key != .deletions
                    },
                    deletionTombstoneCount: applyResult.deletionTombstoneCount
                )
            }

            let result = makeArchiveExportResult(
                archive: archive,
                didUpdateExistingCloudKitShare: updatedShare != nil,
                deletionTombstoneCount: applyResult.deletionTombstoneCount,
                reconciliationReport: reconciliationReport
            )
            try operationCoordinator.complete(
                operationID: operation.id,
                recordCounts: [
                    "exportedRecords": result.exportedRecordCount,
                    "deletionTombstones": result.exportedDeletedRecordCount,
                ],
                reconciliationSummary: reconciliationReport.summary
            )
            return result
        } catch {
            operationCoordinator.fail(operationID: operation.id, error: error)
            throw error
        }
    }

    func makeSystemShare(
        from archive: HerdSharingBridgeArchive
    ) async throws -> CKShare {
        let applyResult = try await applyBridgeArchiveToPrivateStore(archive)
        let records = try resolveArchiveRecords(applyResult.recordObjectIDURIs)
        return try await shareRecords(records, title: archive.herd.name)
    }

    private func resolveArchiveRecords(_ objectIDURIs: [URL]) throws -> [NSManagedObject] {
        let coordinator = persistentContainer.persistentStoreCoordinator
        let objectIDs = objectIDURIs.compactMap {
            coordinator.managedObjectID(forURIRepresentation: $0)
        }
        return try objectIDs.map {
            try persistentContainer.viewContext.existingObject(with: $0)
        }
    }

    private func makeArchivePublicIDs(
        _ archive: HerdSharingBridgeArchive
    ) -> [HerdSharingBridgeStep: [UUID]] {
        [
            .herd: archive.publicIDs(named: SharedHerdRecord.entityName),
            .tagColorDefinitions: archive.publicIDs(named: SharedTagColorDefinitionRecord.entityName),
            .statusReferences: archive.publicIDs(named: SharedAnimalStatusReferenceRecord.entityName),
            .pastureGroups: archive.publicIDs(named: SharedPastureGroupRecord.entityName),
            .pastures: archive.publicIDs(named: SharedPastureRecord.entityName),
            .animals: archive.publicIDs(named: SharedAnimalRecord.entityName),
            .animalTags: archive.publicIDs(named: SharedAnimalTagRecord.entityName),
            .movements: archive.publicIDs(named: SharedMovementRecord.entityName),
            .statusRecords: archive.publicIDs(named: SharedStatusRecord.entityName),
            .workingProtocolTemplates: archive.publicIDs(named: SharedWorkingProtocolTemplateRecord.entityName),
            .workingSessions: archive.publicIDs(named: SharedWorkingSessionRecord.entityName),
            .workingQueueItems: archive.publicIDs(named: SharedWorkingQueueItemRecord.entityName),
            .workingTreatmentRecords: archive.publicIDs(named: SharedWorkingTreatmentRecord.entityName),
            .healthRecords: archive.publicIDs(named: SharedHealthRecord.entityName),
            .pregnancyChecks: archive.publicIDs(named: SharedPregnancyCheckRecord.entityName),
            .fieldCheckSessions: archive.publicIDs(named: SharedFieldCheckSessionRecord.entityName),
            .fieldCheckAnimalChecks: archive.publicIDs(named: SharedFieldCheckAnimalCheckRecord.entityName),
            .fieldCheckFindings: archive.publicIDs(named: SharedFieldCheckFindingRecord.entityName),
        ]
    }

    private func makeArchiveExportResult(
        archive: HerdSharingBridgeArchive,
        didUpdateExistingCloudKitShare: Bool,
        deletionTombstoneCount: Int,
        reconciliationReport: HerdSharingBridgeReconciliationReport
    ) -> HerdSharingBridgeExportResult {
        HerdSharingBridgeExportResult(
            herdName: archive.herd.name,
            writeTargetDescription: "owner private store",
            didUpdateExistingCloudKitShare: didUpdateExistingCloudKitShare,
            exportedTagColorDefinitionCount: archive.records(named: SharedTagColorDefinitionRecord.entityName).count,
            exportedStatusReferenceCount: archive.records(named: SharedAnimalStatusReferenceRecord.entityName).count,
            exportedAnimalTagCount: archive.records(named: SharedAnimalTagRecord.entityName).count,
            exportedPastureGroupCount: archive.records(named: SharedPastureGroupRecord.entityName).count,
            exportedPastureCount: archive.records(named: SharedPastureRecord.entityName).count,
            exportedAnimalCount: archive.records(named: SharedAnimalRecord.entityName).count,
            exportedMovementCount: archive.records(named: SharedMovementRecord.entityName).count,
            exportedStatusRecordCount: archive.records(named: SharedStatusRecord.entityName).count,
            exportedHealthRecordCount: archive.records(named: SharedHealthRecord.entityName).count,
            exportedPregnancyCheckCount: archive.records(named: SharedPregnancyCheckRecord.entityName).count,
            exportedWorkingProtocolTemplateCount: archive.records(named: SharedWorkingProtocolTemplateRecord.entityName).count,
            exportedWorkingSessionCount: archive.records(named: SharedWorkingSessionRecord.entityName).count,
            exportedWorkingQueueItemCount: archive.records(named: SharedWorkingQueueItemRecord.entityName).count,
            exportedWorkingTreatmentRecordCount: archive.records(named: SharedWorkingTreatmentRecord.entityName).count,
            exportedFieldCheckSessionCount: archive.records(named: SharedFieldCheckSessionRecord.entityName).count,
            exportedFieldCheckAnimalCheckCount: archive.records(named: SharedFieldCheckAnimalCheckRecord.entityName).count,
            exportedFieldCheckFindingCount: archive.records(named: SharedFieldCheckFindingRecord.entityName).count,
            exportedDeletedRecordCount: deletionTombstoneCount,
            reconciliationReport: reconciliationReport
        )
    }
}
