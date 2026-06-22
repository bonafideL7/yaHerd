//
//  SyncDataResetService.swift
//  yaHerd
//

import CloudKit
import Foundation

struct SyncDataResetSummary: Equatable {
    let deletedCloudKitRecordCount: Int
    let deletedCloudKitZoneCount: Int
}

protocol SyncDataResetting {
    func deleteICloudSyncData() async throws -> SyncDataResetSummary
}

final class SyncDataResetService: SyncDataResetting {
    private let preferences: AppPreferencesProviding
    private let settingsSynchronizer: AppSettingsSyncing
    private let cloudKitContainerIdentifier: String

    init(
        preferences: AppPreferencesProviding = AppPreferences(),
        settingsSynchronizer: AppSettingsSyncing = AppSettingsSynchronizer.shared,
        cloudKitContainerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier
    ) {
        self.preferences = preferences
        self.settingsSynchronizer = settingsSynchronizer
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
    }

    func deleteICloudSyncData() async throws -> SyncDataResetSummary {
        let cloudKitSummary = try await deletePrivateCloudKitData()

        await MainActor.run {
            preferences.syncMode = .localOnly
            settingsSynchronizer.stop()
        }

        return SyncDataResetSummary(
            deletedCloudKitRecordCount: cloudKitSummary.deletedRecordCount,
            deletedCloudKitZoneCount: cloudKitSummary.deletedZoneCount
        )
    }

    private func deletePrivateCloudKitData() async throws -> CloudKitDeleteSummary {
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        let database = container.privateCloudDatabase
        let zones = try await fetchAllRecordZones(in: database)
        let defaultZoneID = CKRecordZone.default().zoneID

        var deletedZoneCount = 0

        // SwiftData/Core Data CloudKit mirroring stores app records in private custom zones.
        // The default zone cannot be deleted, and deleting the custom zones is the cleanest
        // supported reset path for development/TestFlight cleanup.
        for zone in zones where zone.zoneID != defaultZoneID {
            try await deleteRecordZone(zone.zoneID, in: database)
            deletedZoneCount += 1
        }

        return CloudKitDeleteSummary(
            deletedRecordCount: 0,
            deletedZoneCount: deletedZoneCount
        )
    }

    private func fetchAllRecordZones(in database: CKDatabase) async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecordZone], Error>) in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: zones ?? [])
                }
            }
        }
    }

    private func deleteRecordZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordZoneID: zoneID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private struct CloudKitDeleteSummary: Equatable {
    let deletedRecordCount: Int
    let deletedZoneCount: Int
}
