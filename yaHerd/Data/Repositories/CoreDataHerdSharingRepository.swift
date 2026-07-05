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
        store: HerdSharingCoreDataStore = HerdSharingCoreDataStore()
    ) {
        self.context = context
        self.store = store
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

        let animals = try fetchSwiftDataAnimals(for: herd)
        let systemShare = try await store.makeSystemShare(for: herd, animals: animals)
        return HerdSharingActionResult(
            title: "Share sheet ready",
            message: "Invite people through the system CloudKit sharing sheet. SwiftData remains the app data store; Core Data now mirrors the herd root and \(animals.count) animal records for CloudKit sharing.",
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
                message: "Imported \(importResult.importedAnimalCount) animal records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
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
            message: "Imported \(importResult.insertedAnimalCount) new and \(importResult.updatedAnimalCount) existing animal records from the Core Data sharing bridge into SwiftData for \(importResult.herdName)."
        )
    }

    private func fetchSwiftDataAnimals(for herd: HerdSummary) throws -> [Animal] {
        let descriptor = FetchDescriptor<Animal>()
        return try context.fetch(descriptor).filter { animal in
            animal.herd?.publicID == herd.publicID
        }
    }
}
