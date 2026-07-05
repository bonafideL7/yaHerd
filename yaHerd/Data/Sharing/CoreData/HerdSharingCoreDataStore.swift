//
//  HerdSharingCoreDataStore.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation
import SwiftData

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

    func mirrorPastureGroupsIntoPrivateStore(
        _ pastureGroups: [PastureGroup],
        herd: HerdSummary,
        herdRecord: SharedHerdRecord
    ) throws -> [SharedPastureGroupRecord] {
        guard let privateStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The private sharing bridge store was not loaded.")
        }

        let context = persistentContainer.viewContext
        let existingRecords = try fetchSharedPastureGroupRecords(herdPublicID: herd.publicID, in: privateStore)
        var recordsByPublicID: [String: SharedPastureGroupRecord] = [:]
        for record in existingRecords {
            guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
            recordsByPublicID[publicID] = record
        }
        let mirroredGroupIDs = Set(pastureGroups.map { $0.publicID.uuidString })
        var mirroredRecords: [SharedPastureGroupRecord] = []

        for pastureGroup in pastureGroups {
            let publicID = pastureGroup.publicID.uuidString
            let existingRecord = recordsByPublicID[publicID]
            let record = existingRecord ?? SharedPastureGroupRecord(context: context)

            if existingRecord == nil {
                context.assign(record, to: privateStore)
            }

            record.mirror(pastureGroup, herdPublicID: herd.publicID)
            record.herd = herdRecord
            mirroredRecords.append(record)
        }

        for staleRecord in existingRecords where !mirroredGroupIDs.contains(staleRecord.publicID ?? "") {
            context.delete(staleRecord)
        }

        if context.hasChanges {
            try context.save()
        }

        return mirroredRecords
    }

    func mirrorPasturesIntoPrivateStore(
        _ pastures: [Pasture],
        herd: HerdSummary,
        herdRecord: SharedHerdRecord,
        pastureGroupRecords: [SharedPastureGroupRecord]
    ) throws -> [SharedPastureRecord] {
        guard let privateStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The private sharing bridge store was not loaded.")
        }

        let context = persistentContainer.viewContext
        let existingRecords = try fetchSharedPastureRecords(herdPublicID: herd.publicID, in: privateStore)
        var recordsByPublicID: [String: SharedPastureRecord] = [:]
        for record in existingRecords {
            guard let publicID = record.publicID, recordsByPublicID[publicID] == nil else { continue }
            recordsByPublicID[publicID] = record
        }
        var groupsByPublicID: [String: SharedPastureGroupRecord] = [:]
        for groupRecord in pastureGroupRecords {
            guard let publicID = groupRecord.publicID else { continue }
            groupsByPublicID[publicID] = groupRecord
        }

        let mirroredPastureIDs = Set(pastures.map { $0.publicID.uuidString })
        var mirroredRecords: [SharedPastureRecord] = []

        for pasture in pastures {
            let publicID = pasture.publicID.uuidString
            let existingRecord = recordsByPublicID[publicID]
            let record = existingRecord ?? SharedPastureRecord(context: context)

            if existingRecord == nil {
                context.assign(record, to: privateStore)
            }

            record.mirror(pasture, herdPublicID: herd.publicID)
            record.herd = herdRecord
            record.group = pasture.group.flatMap { groupsByPublicID[$0.publicID.uuidString] }
            mirroredRecords.append(record)
        }

        for staleRecord in existingRecords where !mirroredPastureIDs.contains(staleRecord.publicID ?? "") {
            context.delete(staleRecord)
        }

        if context.hasChanges {
            try context.save()
        }

        return mirroredRecords
    }

    func makeSystemShare(
        for herd: HerdSummary,
        pastureGroups: [PastureGroup],
        pastures: [Pasture],
        animals: [Animal]
    ) async throws -> HerdSystemShare {
        let record = try await mirrorHerdIntoPrivateStore(herd)
        let pastureGroupRecords = try mirrorPastureGroupsIntoPrivateStore(
            pastureGroups,
            herd: herd,
            herdRecord: record
        )
        let pastureRecords = try mirrorPasturesIntoPrivateStore(
            pastures,
            herd: herd,
            herdRecord: record,
            pastureGroupRecords: pastureGroupRecords
        )
        let animalRecords = try mirrorAnimalsIntoPrivateStore(animals, herd: herd, herdRecord: record)
        let recordsToShare: [NSManagedObject] = [record as NSManagedObject] +
            pastureGroupRecords.map { $0 as NSManagedObject } +
            pastureRecords.map { $0 as NSManagedObject } +
            animalRecords.map { $0 as NSManagedObject }
        let share = try await shareRecords(recordsToShare, title: herd.name)

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

    func importSharedRecordsIntoSwiftData(context swiftDataContext: ModelContext) async throws -> HerdSharingBridgeImportResult {
        try await loadIfNeeded()

        guard let sharedStore else {
            throw HerdSharingActionError.sharingStoreUnavailable("The shared CloudKit bridge store was not loaded.")
        }

        let herdRecords = try fetchSharedHerdRecords(in: sharedStore)
        guard let herdRecord = herdRecords.sorted(by: sharedHerdRecordSort).first else {
            throw HerdSharingActionError.bridgeImportFailed("No shared herd records were found in the Core Data sharing bridge.")
        }

        guard let herdPublicID = herdRecord.parsedPublicID else {
            throw HerdSharingActionError.bridgeImportFailed("The shared herd record is missing a valid public ID.")
        }

        let herd = try upsertSwiftDataHerd(from: herdRecord, in: swiftDataContext)
        let sharedPastureGroupRecords = try fetchSharedPastureGroupRecords(herdPublicID: herdPublicID, in: sharedStore)
        let pastureGroupResult = try upsertSwiftDataPastureGroups(
            from: sharedPastureGroupRecords,
            herd: herd,
            in: swiftDataContext
        )
        let sharedPastureRecords = try fetchSharedPastureRecords(herdPublicID: herdPublicID, in: sharedStore)
        let pastureResult = try upsertSwiftDataPastures(
            from: sharedPastureRecords,
            herd: herd,
            in: swiftDataContext
        )
        let sharedAnimalRecords = try fetchSharedAnimalRecords(herdPublicID: herdPublicID, in: sharedStore)
        let animalResult = try upsertSwiftDataAnimals(
            from: sharedAnimalRecords,
            herd: herd,
            in: swiftDataContext
        )

        if swiftDataContext.hasChanges {
            try swiftDataContext.save()
        }

        return HerdSharingBridgeImportResult(
            herdName: herd.name,
            insertedPastureGroupCount: pastureGroupResult.inserted,
            updatedPastureGroupCount: pastureGroupResult.updated,
            insertedPastureCount: pastureResult.inserted,
            updatedPastureCount: pastureResult.updated,
            insertedAnimalCount: animalResult.inserted,
            updatedAnimalCount: animalResult.updated
        )
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

    private func upsertSwiftDataHerd(
        from sharedRecord: SharedHerdRecord,
        in context: ModelContext
    ) throws -> Herd {
        guard let sharedPublicID = sharedRecord.parsedPublicID else {
            throw HerdSharingActionError.bridgeImportFailed("The shared herd record is missing a valid public ID.")
        }

        if let existingHerd = try fetchSwiftDataHerd(publicID: sharedPublicID, in: context) {
            apply(sharedRecord, to: existingHerd)
            return existingHerd
        }

        let herd = try DefaultHerdBootstrapper.defaultHerd(in: context)
        herd.publicID = sharedPublicID
        apply(sharedRecord, to: herd)
        return herd
    }

    private func apply(_ sharedRecord: SharedHerdRecord, to herd: Herd) {
        herd.name = sharedRecord.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? DefaultHerdBootstrapper.defaultHerdName
        herd.createdAt = sharedRecord.createdAt ?? herd.createdAt
        herd.updatedAt = sharedRecord.updatedAt ?? Date.now
        herd.schemaVersion = sharedRecord.schemaVersion?.intValue ?? herd.schemaVersion
    }

    private func upsertSwiftDataPastureGroups(
        from sharedRecords: [SharedPastureGroupRecord],
        herd: Herd,
        in context: ModelContext
    ) throws -> (inserted: Int, updated: Int) {
        let validSharedRecords = sharedRecords.compactMap { record -> (SharedPastureGroupRecord, UUID)? in
            guard let publicID = record.parsedPublicID else { return nil }
            return (record, publicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0) }

        var groupsByPublicID: [UUID: PastureGroup] = [:]
        for group in try context.fetch(FetchDescriptor<PastureGroup>()) where groupsByPublicID[group.publicID] == nil {
            groupsByPublicID[group.publicID] = group
        }

        var inserted = 0
        var updated = 0

        for (record, publicID) in validSharedRecords {
            let group: PastureGroup
            if let existingGroup = groupsByPublicID[publicID] {
                group = existingGroup
                updated += 1
            } else {
                group = PastureGroup(
                    publicID: publicID,
                    name: record.name ?? "",
                    grazeDays: record.grazeDays?.intValue ?? 7,
                    restDays: record.restDays?.intValue ?? 21
                )
                context.insert(group)
                groupsByPublicID[publicID] = group
                inserted += 1
            }

            apply(record, to: group, herd: herd)
        }

        return (inserted, updated)
    }

    private func apply(
        _ sharedRecord: SharedPastureGroupRecord,
        to group: PastureGroup,
        herd: Herd
    ) {
        group.herd = herd
        group.name = sharedRecord.name ?? ""
        group.grazeDays = sharedRecord.grazeDays?.intValue ?? group.grazeDays
        group.restDays = sharedRecord.restDays?.intValue ?? group.restDays
    }

    private func upsertSwiftDataPastures(
        from sharedRecords: [SharedPastureRecord],
        herd: Herd,
        in context: ModelContext
    ) throws -> (inserted: Int, updated: Int) {
        let validSharedRecords = sharedRecords.compactMap { record -> (SharedPastureRecord, UUID)? in
            guard let publicID = record.parsedPublicID else { return nil }
            return (record, publicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0) }

        var pasturesByPublicID: [UUID: Pasture] = [:]
        for pasture in try context.fetch(FetchDescriptor<Pasture>()) where pasturesByPublicID[pasture.publicID] == nil {
            pasturesByPublicID[pasture.publicID] = pasture
        }

        var groupsByPublicID: [UUID: PastureGroup] = [:]
        for group in try context.fetch(FetchDescriptor<PastureGroup>()) where groupsByPublicID[group.publicID] == nil {
            groupsByPublicID[group.publicID] = group
        }

        var inserted = 0
        var updated = 0

        for (record, publicID) in validSharedRecords {
            let pasture: Pasture
            if let existingPasture = pasturesByPublicID[publicID] {
                pasture = existingPasture
                updated += 1
            } else {
                pasture = Pasture(
                    publicID: publicID,
                    name: record.name ?? "",
                    acreage: record.acreage?.doubleValue,
                    usableAcreage: record.usableAcreage?.doubleValue,
                    targetAcresPerHead: record.targetAcresPerHead?.doubleValue,
                    sortOrder: record.sortOrder?.intValue ?? 0
                )
                context.insert(pasture)
                pasturesByPublicID[publicID] = pasture
                inserted += 1
            }

            apply(record, to: pasture, herd: herd, groupsByPublicID: groupsByPublicID)
        }

        return (inserted, updated)
    }

    private func apply(
        _ sharedRecord: SharedPastureRecord,
        to pasture: Pasture,
        herd: Herd,
        groupsByPublicID: [UUID: PastureGroup]
    ) {
        pasture.herd = herd
        pasture.name = sharedRecord.name ?? ""
        pasture.sortOrder = sharedRecord.sortOrder?.intValue ?? pasture.sortOrder
        pasture.acreage = sharedRecord.acreage?.doubleValue
        pasture.usableAcreage = sharedRecord.usableAcreage?.doubleValue
        pasture.targetAcresPerHead = sharedRecord.targetAcresPerHead?.doubleValue
        pasture.lastGrazedDate = sharedRecord.lastGrazedDate
        pasture.group = sharedRecord.parsedGroupPublicID.flatMap { groupsByPublicID[$0] }
    }

    private func upsertSwiftDataAnimals(
        from sharedRecords: [SharedAnimalRecord],
        herd: Herd,
        in context: ModelContext
    ) throws -> (inserted: Int, updated: Int) {
        let validSharedRecords = sharedRecords.compactMap { record -> (SharedAnimalRecord, UUID)? in
            guard let publicID = record.parsedPublicID else { return nil }
            return (record, publicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0) }

        var animalsByPublicID: [UUID: Animal] = [:]
        for animal in try context.fetch(FetchDescriptor<Animal>()) where animalsByPublicID[animal.publicID] == nil {
            animalsByPublicID[animal.publicID] = animal
        }

        var pasturesByPublicID: [UUID: Pasture] = [:]
        for pasture in try context.fetch(FetchDescriptor<Pasture>()) where pasturesByPublicID[pasture.publicID] == nil {
            pasturesByPublicID[pasture.publicID] = pasture
        }

        var inserted = 0
        var updated = 0

        for (record, publicID) in validSharedRecords {
            let animal: Animal
            if let existingAnimal = animalsByPublicID[publicID] {
                animal = existingAnimal
                updated += 1
            } else {
                animal = Animal(
                    publicID: publicID,
                    name: record.name ?? "",
                    tagNumber: record.tagNumber ?? "",
                    tagColorID: record.parsedTagColorID,
                    birthDate: record.birthDate ?? Date.now,
                    status: record.parsedStatus,
                    saleDate: record.saleDate,
                    salePrice: record.salePrice?.doubleValue,
                    reasonSold: record.reasonSold,
                    deathDate: record.deathDate,
                    causeOfDeath: record.causeOfDeath,
                    statusReferenceID: record.parsedStatusReferenceID,
                    isSoftDeleted: record.isSoftDeleted?.boolValue ?? false,
                    softDeletedAt: record.softDeletedAt,
                    softDeleteReason: record.softDeleteReason,
                    sex: record.parsedSex,
                    distinguishingFeatures: record.parsedDistinguishingFeatures
                )
                context.insert(animal)
                animalsByPublicID[publicID] = animal
                inserted += 1
            }

            apply(record, to: animal, herd: herd, pasturesByPublicID: pasturesByPublicID)
        }

        for (record, publicID) in validSharedRecords {
            guard let animal = animalsByPublicID[publicID] else { continue }
            animal.sireAnimal = record.parsedSireAnimalPublicID.flatMap { animalsByPublicID[$0] }
            animal.damAnimal = record.parsedDamAnimalPublicID.flatMap { animalsByPublicID[$0] }
        }

        return (inserted, updated)
    }

    private func apply(
        _ sharedRecord: SharedAnimalRecord,
        to animal: Animal,
        herd: Herd,
        pasturesByPublicID: [UUID: Pasture]
    ) {
        animal.herd = herd
        animal.name = sharedRecord.name ?? ""
        animal.tagNumber = sharedRecord.tagNumber ?? ""
        animal.tagColorID = sharedRecord.parsedTagColorID
        animal.sex = sharedRecord.parsedSex
        animal.birthDate = sharedRecord.birthDate ?? animal.birthDate
        animal.status = sharedRecord.parsedStatus
        animal.saleDate = sharedRecord.saleDate
        animal.salePrice = sharedRecord.salePrice?.doubleValue
        animal.reasonSold = sharedRecord.reasonSold
        animal.deathDate = sharedRecord.deathDate
        animal.causeOfDeath = sharedRecord.causeOfDeath
        animal.statusReferenceID = sharedRecord.parsedStatusReferenceID
        animal.isSoftDeleted = sharedRecord.isSoftDeleted?.boolValue ?? false
        animal.softDeletedAt = sharedRecord.softDeletedAt
        animal.softDeleteReason = sharedRecord.softDeleteReason
        animal.location = sharedRecord.parsedLocation
        animal.pasture = sharedRecord.parsedPasturePublicID.flatMap { pasturesByPublicID[$0] }
        animal.distinguishingFeatures = sharedRecord.parsedDistinguishingFeatures
    }

    private func fetchSwiftDataHerd(
        publicID: UUID,
        in context: ModelContext
    ) throws -> Herd? {
        try context.fetch(FetchDescriptor<Herd>()).first { herd in
            herd.publicID == publicID
        }
    }

    private func sharedHerdRecordSort(_ lhs: SharedHerdRecord, _ rhs: SharedHerdRecord) -> Bool {
        let lhsDate = lhs.lastMirroredAt ?? lhs.updatedAt ?? lhs.createdAt ?? .distantPast
        let rhsDate = rhs.lastMirroredAt ?? rhs.updatedAt ?? rhs.createdAt ?? .distantPast
        return lhsDate > rhsDate
    }

    private func fetchSharedHerdRecords(in store: NSPersistentStore) throws -> [SharedHerdRecord] {
        let request = SharedHerdRecord.fetchRequest()
        request.affectedStores = [store]
        return try persistentContainer.viewContext.fetch(request)
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

    private func fetchSharedPastureGroupRecords(
        herdPublicID: UUID,
        in store: NSPersistentStore
    ) throws -> [SharedPastureGroupRecord] {
        let request = SharedPastureGroupRecord.fetchRequest()
        request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
        request.affectedStores = [store]
        return try persistentContainer.viewContext.fetch(request)
    }

    private func fetchSharedPastureRecords(
        herdPublicID: UUID,
        in store: NSPersistentStore
    ) throws -> [SharedPastureRecord] {
        let request = SharedPastureRecord.fetchRequest()
        request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID.uuidString)
        request.affectedStores = [store]
        return try persistentContainer.viewContext.fetch(request)
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
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
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
