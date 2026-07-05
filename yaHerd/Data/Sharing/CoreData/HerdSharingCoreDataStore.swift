//
//  HerdSharingCoreDataStore.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation

@MainActor
final class HerdSharingCoreDataStore {
    static let containerName = "yaHerdSharingBridge"
    static let storeDirectoryName = "HerdSharingBridge"
    static let privateStoreFileName = "HerdSharingPrivate.sqlite"
    static let sharedStoreFileName = "HerdSharingShared.sqlite"

    let persistentContainer: NSPersistentCloudKitContainer
    let cloudKitContainer: CKContainer

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private var isLoaded = false

    init(
        containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
        storeDirectoryURL: URL? = nil
    ) {
        let model = HerdSharingCoreDataModelFactory.makeModel()
        persistentContainer = NSPersistentCloudKitContainer(
            name: Self.containerName,
            managedObjectModel: model
        )
        cloudKitContainer = CKContainer(identifier: containerIdentifier)

        let directoryURL = storeDirectoryURL ?? Self.defaultStoreDirectoryURL()
        persistentContainer.persistentStoreDescriptions = [
            Self.makeStoreDescription(
                url: directoryURL.appendingPathComponent(Self.privateStoreFileName),
                containerIdentifier: containerIdentifier,
                databaseScope: .private
            ),
            Self.makeStoreDescription(
                url: directoryURL.appendingPathComponent(Self.sharedStoreFileName),
                containerIdentifier: containerIdentifier,
                databaseScope: .shared
            )
        ]
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func loadIfNeeded() async throws {
        guard !isLoaded else { return }

        let directoryURL = persistentContainer.persistentStoreDescriptions
            .compactMap(\.url)
            .first?
            .deletingLastPathComponent()
        if let directoryURL {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let container = persistentContainer
        let expectedStoreCount = container.persistentStoreDescriptions.count

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var firstError: Error?
            var completedStoreCount = 0

            container.loadPersistentStores { _, error in
                if let error, firstError == nil {
                    firstError = error
                }

                completedStoreCount += 1
                guard completedStoreCount == expectedStoreCount else { return }

                if let firstError {
                    continuation.resume(throwing: firstError)
                } else {
                    continuation.resume()
                }
            }
        }

        privateStore = store(named: Self.privateStoreFileName)
        sharedStore = store(named: Self.sharedStoreFileName)
        isLoaded = true
    }

    func mirrorHerdIntoPrivateStore(_ herd: HerdSummary) async throws -> SharedHerdRecord {
        try await loadIfNeeded()

        guard let privateStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The private sharing bridge store was not loaded.")
        }

        let context = persistentContainer.viewContext
        let existingRecord = try fetchSharedHerdRecord(publicID: herd.publicID, in: privateStore)
        let record = existingRecord ?? SharedHerdRecord(context: context)

        if existingRecord == nil {
            context.assign(record, to: privateStore)
        }

        record.mirror(herd)

        if context.hasChanges {
            try context.save()
        }

        return record
    }

    func mirrorAnimalsIntoPrivateStore(
        _ animals: [Animal],
        herd: HerdSummary,
        herdRecord: SharedHerdRecord
    ) throws -> [SharedAnimalRecord] {
        guard let privateStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The private sharing bridge store was not loaded.")
        }

        let context = persistentContainer.viewContext
        let existingRecords = try fetchSharedAnimalRecords(herdPublicID: herd.publicID, in: privateStore)
        var recordsByPublicID: [String: SharedAnimalRecord] = [:]
        for record in existingRecords {
            guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
            recordsByPublicID[publicID] = record
        }
        let mirroredAnimalIDs = Set(animals.map { $0.publicID.uuidString })
        var mirroredRecords: [SharedAnimalRecord] = []

        for animal in animals {
            let publicID = animal.publicID.uuidString
            let existingRecord = recordsByPublicID[publicID]
            let record = existingRecord ?? SharedAnimalRecord(context: context)

            if existingRecord == nil {
                context.assign(record, to: privateStore)
            }

            record.mirror(animal, herdPublicID: herd.publicID)
            record.herd = herdRecord
            mirroredRecords.append(record)
        }

        for staleRecord in existingRecords where !mirroredAnimalIDs.contains(staleRecord.publicID ?? "") {
            context.delete(staleRecord)
        }

        if context.hasChanges {
            try context.save()
        }

        return mirroredRecords
    }

    func makeSystemShare(
        for herd: HerdSummary,
        animals: [Animal]
    ) async throws -> HerdSystemShare {
        let record = try await mirrorHerdIntoPrivateStore(herd)
        let animalRecords = try mirrorAnimalsIntoPrivateStore(animals, herd: herd, herdRecord: record)
        let share = try await shareRecords([record] + animalRecords, title: herd.name)

        return HerdSystemShare(
            title: herd.name,
            share: share,
            container: cloudKitContainer,
            persistUpdatedShareHandler: { [weak self] share in
                await self?.persistUpdatedShare(share)
            },
            stopSharingHandler: { [weak self] share in
                await self?.purgeStoppedShare(share)
            }
        )
    }

    func acceptShareInvitation(metadata: CKShare.Metadata) async throws {
        try await loadIfNeeded()

        guard let sharedStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The shared CloudKit bridge store was not loaded.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistentContainer.acceptShareInvitations(
                from: [metadata],
                into: sharedStore
            ) { _, error in
                if let error {
                    continuation.resume(throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func shareRecords(
        _ records: [NSManagedObject],
        title: String
    ) async throws -> CKShare {
        let existingShare = try records
            .compactMap { try existingShare(for: $0) }
            .first

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
            persistentContainer.share(records, to: existingShare) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: HerdSharingActionError.cloudKitSharingFailed(error.localizedDescription))
                    return
                }

                guard let share else {
                    continuation.resume(throwing: HerdSharingActionError.cloudKitSharingFailed("Core Data did not return a CKShare."))
                    return
                }

                share[CKShare.SystemFieldKey.title] = title as NSString
                continuation.resume(returning: share)
            }
        }
    }

    private func existingShare(for record: NSManagedObject) throws -> CKShare? {
        let shares = try persistentContainer.fetchShares(matching: [record.objectID])
        return shares[record.objectID]
    }

    private func persistUpdatedShare(_ share: CKShare) async {
        guard let privateStore else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            persistentContainer.persistUpdatedShare(
                share,
                in: privateStore
            ) { _, _ in
                continuation.resume()
            }
        }
    }

    private func purgeStoppedShare(_ share: CKShare) async {
        guard let privateStore else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            persistentContainer.purgeObjectsAndRecordsInZone(
                with: share.recordID.zoneID,
                in: privateStore
            ) { _, _ in
                continuation.resume()
            }
        }
    }

    private func fetchSharedHerdRecord(
        publicID: UUID,
        in store: NSPersistentStore
    ) throws -> SharedHerdRecord? {
        let request = SharedHerdRecord.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "publicID == %@", publicID.uuidString)
        request.affectedStores = [store]
        return try persistentContainer.viewContext.fetch(request).first
    }

    private func fetchSharedAnimalRecords(
        herdPublicID: UUID,
        in store: NSPersistentStore
    ) throws -> [SharedAnimalRecord] {
        let request = SharedAnimalRecord.fetchRequest()
        request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
        request.affectedStores = [store]
        return try persistentContainer.viewContext.fetch(request)
    }

    private func store(named fileName: String) -> NSPersistentStore? {
        persistentContainer.persistentStoreCoordinator.persistentStores.first { store in
            store.url?.lastPathComponent == fileName
        }
    }

    private static func makeStoreDescription(
        url: URL,
        containerIdentifier: String,
        databaseScope: CKDatabase.Scope
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        options.databaseScope = databaseScope
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    private static func defaultStoreDirectoryURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupportURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
    }
}
