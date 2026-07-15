//
//  SyncDataResetService.swift
//  yaHerd
//

import CloudKit
import Foundation

struct SyncDataResetSummary: Equatable, Sendable {
    let deletedCloudKitRecordCount: Int
    let deletedCloudKitZoneCount: Int
    let deletedCloudSettingsCount: Int
}

@MainActor
protocol SyncDataResetting {
    func deleteICloudSyncData() async throws -> SyncDataResetSummary
}

@MainActor
final class SyncDataResetService: SyncDataResetting {
    private let preferences: AppPreferencesProviding
    private let settingsSynchronizer: AppSettingsSyncing
    private let cloudKitContainerIdentifier: String

    convenience init() {
        self.init(preferences: AppPreferences())
    }

    convenience init(preferences: AppPreferencesProviding) {
        self.init(
            preferences: preferences,
            settingsSynchronizer: AppSettingsSynchronizer.shared,
            cloudKitContainerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier
        )
    }

    init(
        preferences: AppPreferencesProviding,
        settingsSynchronizer: AppSettingsSyncing,
        cloudKitContainerIdentifier: String
    ) {
        self.preferences = preferences
        self.settingsSynchronizer = settingsSynchronizer
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
    }

    func deleteICloudSyncData() async throws -> SyncDataResetSummary {
        let cloudKitSummary = try await deletePrivateCloudKitData()

        preferences.syncMode = .localOnly
        let deletedCloudSettingsCount = settingsSynchronizer.deleteCloudSettings()

        return SyncDataResetSummary(
            deletedCloudKitRecordCount: cloudKitSummary.deletedRecordCount,
            deletedCloudKitZoneCount: cloudKitSummary.deletedZoneCount,
            deletedCloudSettingsCount: deletedCloudSettingsCount
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
        try await database.allRecordZones()
    }

    private func deleteRecordZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        _ = try await database.deleteRecordZone(withID: zoneID)
    }
}

private struct CloudKitDeleteSummary: Equatable, Sendable {
    let deletedRecordCount: Int
    let deletedZoneCount: Int
}
