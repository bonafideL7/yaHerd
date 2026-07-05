//
//  CoreDataHerdSharingRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class CoreDataHerdSharingRepository: HerdSharingRepository {
    private let context: ModelContext
    private let store: HerdSharingCoreDataStore

    init(
        context: ModelContext,
        store: HerdSharingCoreDataStore? = nil
    ) {
        self.context = context
        self.store = store ?? HerdSharingCoreDataStore()
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        guard herd != nil else {
            return .shareRootMissing
        }

        switch storageMode {
        case .localOnly:
            return .iCloudSyncRequired
        case .iCloud:
            return .sharingAdapterAvailable
        }
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }

        let pastureGroups = try fetchSwiftDataPastureGroups(for: herd)
        let pastures = try fetchSwiftDataPastures(for: herd)
        let animals = try fetchSwiftDataAnimals(for: herd)
        let movements = try fetchSwiftDataMovements(for: herd)
        let statusRecords = try fetchSwiftDataStatusRecords(for: herd)
        let healthRecords = try fetchSwiftDataHealthRecords(for: herd)
        let pregnancyChecks = try fetchSwiftDataPregnancyChecks(for: herd)
        let workingProtocolTemplates = try fetchSwiftDataWorkingProtocolTemplates(for: herd)
        let workingSessions = try fetchSwiftDataWorkingSessions(for: herd)
        let workingQueueItems = try fetchSwiftDataWorkingQueueItems(for: herd)
        let workingTreatmentRecords = try fetchSwiftDataWorkingTreatmentRecords(for: herd)
        let systemShare = try await store.makeSystemShare(
            for: herd,
            pastureGroups: pastureGroups,
            pastures: pastures,
            animals: animals,
            movements: movements,
            statusRecords: statusRecords,
            healthRecords: healthRecords,
            pregnancyChecks: pregnancyChecks,
            workingProtocolTemplates: workingProtocolTemplates,
            workingSessions: workingSessions,
            workingQueueItems: workingQueueItems,
            workingTreatmentRecords: workingTreatmentRecords
        )
        return HerdSharingActionResult(
            title: "Share sheet ready",
            message: "Invite people through the system CloudKit sharing sheet. SwiftData remains the app data store; Core Data now mirrors the herd root, \(pastureGroups.count) pasture groups, \(pastures.count) pastures, \(animals.count) animal records, \(movements.count) movement records, \(statusRecords.count) status history records, \(healthRecords.count) health records, \(pregnancyChecks.count) pregnancy checks, \(workingProtocolTemplates.count) working protocol templates, \(workingSessions.count) working sessions, \(workingQueueItems.count) working queue items, and \(workingTreatmentRecords.count) working treatment records for CloudKit sharing.",
            systemShare: systemShare
        )
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }

        try await store.acceptShareInvitation(metadata: invitation.metadata)

        do {
            let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
            return HerdSharingActionResult(
                title: "Invitation accepted",
                message: "Imported \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animal records, \(importResult.importedMovementCount) movement records, \(importResult.importedStatusRecordCount) status history records, \(importResult.importedHealthRecordCount) health records, \(importResult.importedPregnancyCheckCount) pregnancy checks, \(importResult.importedWorkingProtocolTemplateCount) working protocol templates, \(importResult.importedWorkingSessionCount) working sessions, \(importResult.importedWorkingQueueItemCount) queue items, and \(importResult.importedWorkingTreatmentRecordCount) treatment records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
            )
        } catch HerdSharingActionError.bridgeImportFailed {
            return HerdSharingActionResult(
                title: "Invitation accepted",
                message: "The CloudKit share was accepted into the Core Data bridge, but shared records were not available to import into SwiftData yet. Use Import Shared Data after CloudKit finishes syncing."
            )
        }
    }

    func importSharedBridgeData(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }

        let importResult = try await store.importSharedRecordsIntoSwiftData(context: context)
        return HerdSharingActionResult(
            title: "Shared data imported",
            message: "Imported \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records, \(importResult.insertedHealthRecordCount) new/\(importResult.updatedHealthRecordCount) existing health records, \(importResult.insertedPregnancyCheckCount) new/\(importResult.updatedPregnancyCheckCount) existing pregnancy checks, \(importResult.insertedWorkingProtocolTemplateCount) new/\(importResult.updatedWorkingProtocolTemplateCount) existing working protocol templates, \(importResult.insertedWorkingSessionCount) new/\(importResult.updatedWorkingSessionCount) existing working sessions, \(importResult.insertedWorkingQueueItemCount) new/\(importResult.updatedWorkingQueueItemCount) existing queue items, and \(importResult.insertedWorkingTreatmentRecordCount) new/\(importResult.updatedWorkingTreatmentRecordCount) existing treatment records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
        )
    }

    private func fetchSwiftDataPastureGroups(for herd: HerdSummary) throws -> [PastureGroup] {
        let descriptor = FetchDescriptor<PastureGroup>()
        return try context.fetch(descriptor).filter { pastureGroup in
            pastureGroup.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataPastures(for herd: HerdSummary) throws -> [Pasture] {
        let descriptor = FetchDescriptor<Pasture>()
        return try context.fetch(descriptor).filter { pasture in
            pasture.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataAnimals(for herd: HerdSummary) throws -> [Animal] {
        let descriptor = FetchDescriptor<Animal>()
        return try context.fetch(descriptor).filter { animal in
            animal.herd?.publicID == herd.publicID
        }
    }


    private func fetchSwiftDataMovements(for herd: HerdSummary) throws -> [MovementRecord] {
        let descriptor = FetchDescriptor<MovementRecord>()
        return try context.fetch(descriptor).filter { movement in
            movement.herd?.publicID == herd.publicID || movement.animal?.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataStatusRecords(for herd: HerdSummary) throws -> [StatusRecord] {
        let descriptor = FetchDescriptor<StatusRecord>()
        return try context.fetch(descriptor).filter { statusRecord in
            statusRecord.herd?.publicID == herd.publicID || statusRecord.animal?.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataHealthRecords(for herd: HerdSummary) throws -> [HealthRecord] {
        let descriptor = FetchDescriptor<HealthRecord>()
        return try context.fetch(descriptor).filter { healthRecord in
            healthRecord.herd?.publicID == herd.publicID || healthRecord.animal?.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataPregnancyChecks(for herd: HerdSummary) throws -> [PregnancyCheck] {
        let descriptor = FetchDescriptor<PregnancyCheck>()
        return try context.fetch(descriptor).filter { pregnancyCheck in
            pregnancyCheck.herd?.publicID == herd.publicID || pregnancyCheck.animal?.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataWorkingProtocolTemplates(for herd: HerdSummary) throws -> [WorkingProtocolTemplate] {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>()
        return try context.fetch(descriptor).filter { template in
            template.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataWorkingSessions(for herd: HerdSummary) throws -> [WorkingSession] {
        let descriptor = FetchDescriptor<WorkingSession>()
        return try context.fetch(descriptor).filter { session in
            session.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataWorkingQueueItems(for herd: HerdSummary) throws -> [WorkingQueueItem] {
        let descriptor = FetchDescriptor<WorkingQueueItem>()
        return try context.fetch(descriptor).filter { queueItem in
            queueItem.herd?.publicID == herd.publicID ||
                queueItem.session?.herd?.publicID == herd.publicID ||
                queueItem.animal?.herd?.publicID == herd.publicID
        }
    }

    private func fetchSwiftDataWorkingTreatmentRecords(for herd: HerdSummary) throws -> [WorkingTreatmentRecord] {
        let descriptor = FetchDescriptor<WorkingTreatmentRecord>()
        return try context.fetch(descriptor).filter { treatmentRecord in
            treatmentRecord.herd?.publicID == herd.publicID ||
                treatmentRecord.session?.herd?.publicID == herd.publicID ||
                treatmentRecord.animal?.herd?.publicID == herd.publicID
        }
    }
}
