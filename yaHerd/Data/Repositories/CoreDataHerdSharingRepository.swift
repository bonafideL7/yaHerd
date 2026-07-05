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
        let systemShare = try await store.makeSystemShare(
            for: herd,
            pastureGroups: pastureGroups,
            pastures: pastures,
            animals: animals,
            movements: movements,
            statusRecords: statusRecords
        )
        return HerdSharingActionResult(
            title: "Share sheet ready",
            message: "Invite people through the system CloudKit sharing sheet. SwiftData remains the app data store; Core Data now mirrors the herd root, \(pastureGroups.count) pasture groups, \(pastures.count) pastures, \(animals.count) animal records, \(movements.count) movement records, and \(statusRecords.count) status history records for CloudKit sharing.",
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
                message: "Imported \(importResult.importedPastureGroupCount) pasture groups, \(importResult.importedPastureCount) pastures, \(importResult.importedAnimalCount) animal records, \(importResult.importedMovementCount) movement records, and \(importResult.importedStatusRecordCount) status history records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
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
            message: "Imported \(importResult.insertedPastureGroupCount) new/\(importResult.updatedPastureGroupCount) existing pasture groups, \(importResult.insertedPastureCount) new/\(importResult.updatedPastureCount) existing pastures, \(importResult.insertedAnimalCount) new/\(importResult.updatedAnimalCount) existing animals, \(importResult.insertedMovementCount) new/\(importResult.updatedMovementCount) existing movement records, and \(importResult.insertedStatusRecordCount) new/\(importResult.updatedStatusRecordCount) existing status history records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
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
}
