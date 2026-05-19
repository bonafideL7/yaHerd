//
//  SyncDataResetService.swift
//  yaHerd
//

import CloudKit
import Foundation
import SwiftData

struct SyncDataResetSummary: Equatable {
    let deletedLocalObjectCount: Int
    let deletedCloudKitRecordCount: Int
    let deletedCloudKitZoneCount: Int
}

protocol SyncDataResetting {
    @MainActor
    func deleteAllSyncData() async throws -> SyncDataResetSummary
}

final class SyncDataResetService: SyncDataResetting {
    private let modelContext: ModelContext
    private let preferences: AppPreferencesProviding
    private let cloudKitContainerIdentifier: String

    @MainActor
    init(
        modelContext: ModelContext,
        preferences: AppPreferencesProviding = AppPreferences(),
        cloudKitContainerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier
    ) {
        self.modelContext = modelContext
        self.preferences = preferences
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
    }

    @MainActor
    func deleteAllSyncData() async throws -> SyncDataResetSummary {
        let deletedLocalObjectCount = try deleteLocalSwiftDataObjects()
        let cloudKitSummary = try await deletePrivateCloudKitData()

        preferences.syncMode = .localOnly

        return SyncDataResetSummary(
            deletedLocalObjectCount: deletedLocalObjectCount,
            deletedCloudKitRecordCount: cloudKitSummary.deletedRecordCount,
            deletedCloudKitZoneCount: cloudKitSummary.deletedZoneCount
        )
    }

    @MainActor
    private func deleteLocalSwiftDataObjects() throws -> Int {
        var deletedCount = 0

        deletedCount += try deleteAll(FieldCheckFinding.self)
        deletedCount += try deleteAll(FieldCheckAnimalCheck.self)
        deletedCount += try deleteAll(FieldCheckSession.self)
        deletedCount += try deleteAll(WorkingTreatmentRecord.self)
        deletedCount += try deleteAll(WorkingQueueItem.self)
        deletedCount += try deleteAll(WorkingSession.self)
        deletedCount += try deleteAll(WorkingProtocolTemplate.self)
        deletedCount += try deleteAll(StatusRecord.self)
        deletedCount += try deleteAll(MovementRecord.self)
        deletedCount += try deleteAll(PregnancyCheck.self)
        deletedCount += try deleteAll(HealthRecord.self)
        deletedCount += try deleteAll(AnimalTag.self)
        deletedCount += try deleteAll(TagColorDefinition.self)
        deletedCount += try deleteAll(AnimalStatusReference.self)
        deletedCount += try deleteAll(Animal.self)
        deletedCount += try deleteAll(Pasture.self)
        deletedCount += try deleteAll(PastureGroup.self)

        try modelContext.save()
        return deletedCount
    }

    @MainActor
    private func deleteAll<T: PersistentModel>(_ modelType: T.Type) throws -> Int {
        let objects = try modelContext.fetch(FetchDescriptor<T>())
        for object in objects {
            modelContext.delete(object)
        }
        return objects.count
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        var chunks: [[Element]] = []
        chunks.reserveCapacity((count / size) + 1)

        var startIndex = 0
        while startIndex < count {
            let endIndex = Swift.min(startIndex + size, count)
            chunks.append(Array(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }
}
