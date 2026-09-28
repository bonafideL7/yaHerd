@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataPastureRepository: PastureRepository {
    private let repositoryContext: CoreDataSynchronousRepositoryContext
    nonisolated private let lookup: CoreDataLookup

    init(
        repositoryContext: CoreDataSynchronousRepositoryContext,
        lookup: CoreDataLookup
    ) {
        self.repositoryContext = repositoryContext
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            repositoryContext: CoreDataSynchronousRepositoryContext(
                selection: selection,
                assembly: assembly
            ),
            lookup: assembly.lookup
        )
    }

    func fetchPastures() throws -> [PastureSummary] {
        try read { context, herd in
            try self.fetchPastures(in: context, herd: herd).map(PastureMapper.makeSummary)
        }
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        try read { context, herd in
            try self.lookup.herdOwned(CDPasture.self, id: id, herdID: herd.id, in: context)
                .map(PastureMapper.makeDetail)
        }
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try read { context, herd in
            guard let pasture = try self.lookup.herdOwned(
                CDPasture.self,
                id: pastureID,
                herdID: herd.id,
                in: context
            ) else {
                return []
            }

            return self.animals(in: pasture)
                .filter(self.isActiveInHerd)
                .map(self.makeAnimalSummary)
                .sorted {
                    $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending
                }
        }
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        try read { context, herd in
            try self.fetchPastures(in: context, herd: herd)
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .map { PastureOption(id: $0.id, name: $0.name) }
        }
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        _ = try read { context, herd in
            try self.fetchPastures(ids: ids, in: context, herd: herd)
        }
    }

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try read { context, herd in
            try self.fetchPastures(in: context, herd: herd).contains { pasture in
                if let id, pasture.id == id { return false }
                return pasture.name.caseInsensitiveCompare(normalizedName) == .orderedSame
            }
        }
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        let normalizedInput = input.normalized
        return try write { context, herd in
            if try self.pastureNameExists(
                normalizedInput.name,
                excluding: nil,
                in: context,
                herd: herd
            ) {
                throw PastureValidationError.duplicateName(normalizedInput.name)
            }

            let pasture = CDPasture(context: context)
            pasture.id = try self.uniqueID(for: CDPasture.self, in: context, herdID: herd.id)
            pasture.name = normalizedInput.name
            pasture.acreage = normalizedInput.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = normalizedInput.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = normalizedInput.targetAcresPerHead.map(NSNumber.init(value:))
            pasture.sortOrder = Int64(try self.nextSortOrder(in: context, herd: herd))
            pasture.herd = herd

            return PastureMapper.makeDetail(from: pasture)
        }
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        let normalizedInput = input.normalized
        return try write { context, herd in
            guard let pasture = try self.lookup.herdOwned(
                CDPasture.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureValidationError.pastureNotFound
            }

            if try self.pastureNameExists(
                normalizedInput.name,
                excluding: id,
                in: context,
                herd: herd
            ) {
                throw PastureValidationError.duplicateName(normalizedInput.name)
            }

            pasture.name = normalizedInput.name
            pasture.acreage = normalizedInput.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = normalizedInput.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = normalizedInput.targetAcresPerHead.map(NSNumber.init(value:))

            return PastureMapper.makeDetail(from: pasture)
        }
    }

    func reorder(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        try write { context, herd in
            let requested = try self.fetchPastures(ids: ids, in: context, herd: herd)
            let requestedIDs = Set(ids)

            for (index, pasture) in requested.enumerated() {
                pasture.sortOrder = Int64(index)
            }

            let remaining = try self.fetchPastures(in: context, herd: herd)
                .filter { !requestedIDs.contains($0.id) }
                .sorted(by: self.pastureSortComparison)

            for (offset, pasture) in remaining.enumerated() {
                pasture.sortOrder = Int64(ids.count + offset)
            }
        }
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        try write { context, herd in
            for pasture in try self.fetchPastures(ids: ids, in: context, herd: herd) {
                context.delete(pasture)
            }
        }
    }

    func fetchPastureGroups() throws -> [PastureGroupSummary] {
        try read { context, herd in
            try self.fetchGroups(in: context, herd: herd)
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .map(PastureMapper.makeGroupSummary)
        }
    }

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        try read { context, herd in
            try self.lookup.herdOwned(CDPastureGroup.self, id: id, herdID: herd.id, in: context)
                .map(PastureMapper.makeGroupDetail)
        }
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        _ = try read { context, herd in
            try self.fetchGroups(ids: ids, in: context, herd: herd)
        }
    }

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try read { context, herd in
            try self.fetchGroups(in: context, herd: herd).contains { group in
                if let id, group.id == id { return false }
                return group.name.caseInsensitiveCompare(normalizedName) == .orderedSame
            }
        }
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let normalizedInput = input.normalized
        return try write { context, herd in
            if try self.groupNameExists(
                normalizedInput.name,
                excluding: nil,
                in: context,
                herd: herd
            ) {
                throw PastureValidationError.duplicateName(normalizedInput.name)
            }

            let group = CDPastureGroup(context: context)
            group.id = try self.uniqueID(for: CDPastureGroup.self, in: context, herdID: herd.id)
            group.name = normalizedInput.name
            group.grazeDays = Int64(normalizedInput.grazeDays)
            group.restDays = Int64(normalizedInput.restDays)
            group.herd = herd

            return PastureMapper.makeGroupDetail(from: group)
        }
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let normalizedInput = input.normalized
        return try write { context, herd in
            guard let group = try self.lookup.herdOwned(
                CDPastureGroup.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureValidationError.pastureGroupNotFound
            }

            if try self.groupNameExists(
                normalizedInput.name,
                excluding: id,
                in: context,
                herd: herd
            ) {
                throw PastureValidationError.duplicateName(normalizedInput.name)
            }

            group.name = normalizedInput.name
            group.grazeDays = Int64(normalizedInput.grazeDays)
            group.restDays = Int64(normalizedInput.restDays)

            return PastureMapper.makeGroupDetail(from: group)
        }
    }

    func deleteGroups(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        try write { context, herd in
            for group in try self.fetchGroups(ids: ids, in: context, herd: herd) {
                context.delete(group)
            }
        }
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        try write { context, herd in
            guard let pasture = try self.lookup.herdOwned(
                CDPasture.self,
                id: pastureID,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureValidationError.pastureNotFound
            }

            if let groupID {
                guard let group = try self.lookup.herdOwned(
                    CDPastureGroup.self,
                    id: groupID,
                    herdID: herd.id,
                    in: context
                ) else {
                    throw PastureValidationError.pastureGroupNotFound
                }
                pasture.group = group
            } else {
                pasture.group = nil
            }
        }
    }

    private func read<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        try repositoryContext.read(operation)
    }

    private func write<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        try repositoryContext.write(operation)
    }

    private nonisolated func fetchPastures(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDPasture] {
        let request = NSFetchRequest<CDPasture>(entityName: CDPasture.coreDataEntityName)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request).sorted(by: pastureSortComparison)
    }

    private nonisolated func fetchPastures(
        ids: [UUID],
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDPasture] {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }
        guard !ids.isEmpty else { return [] }

        var byID: [UUID: CDPasture] = [:]
        for id in ids {
            if let pasture = try lookup.herdOwned(CDPasture.self, id: id, herdID: herd.id, in: context) {
                byID[id] = pasture
            }
        }

        let missingIDs = ids.filter { byID[$0] == nil }
        guard missingIDs.isEmpty else {
            throw PastureRepositoryError.pastureIDsNotFound(missingIDs)
        }
        return ids.compactMap { byID[$0] }
    }

    private nonisolated func fetchGroups(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDPastureGroup] {
        let request = NSFetchRequest<CDPastureGroup>(entityName: CDPastureGroup.coreDataEntityName)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request)
    }

    private nonisolated func fetchGroups(
        ids: [UUID],
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDPastureGroup] {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureGroupIDs
        }
        guard !ids.isEmpty else { return [] }

        var byID: [UUID: CDPastureGroup] = [:]
        for id in ids {
            if let group = try lookup.herdOwned(CDPastureGroup.self, id: id, herdID: herd.id, in: context) {
                byID[id] = group
            }
        }

        let missingIDs = ids.filter { byID[$0] == nil }
        guard missingIDs.isEmpty else {
            throw PastureRepositoryError.pastureGroupIDsNotFound(missingIDs)
        }
        return ids.compactMap { byID[$0] }
    }

    private nonisolated func pastureNameExists(
        _ name: String,
        excluding id: UUID?,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Bool {
        try fetchPastures(in: context, herd: herd).contains { pasture in
            if let id, pasture.id == id { return false }
            return pasture.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private nonisolated func groupNameExists(
        _ name: String,
        excluding id: UUID?,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Bool {
        try fetchGroups(in: context, herd: herd).contains { group in
            if let id, group.id == id { return false }
            return group.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private nonisolated func nextSortOrder(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Int {
        (try fetchPastures(in: context, herd: herd).map { Int($0.sortOrder) }.max() ?? -1) + 1
    }

    private nonisolated func uniqueID<Object>(
        for type: Object.Type,
        in context: NSManagedObjectContext,
        herdID: UUID
    ) throws -> UUID where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        var id = UUID()
        while try lookup.herdOwned(type, id: id, herdID: herdID, in: context) != nil {
            id = UUID()
        }
        return id
    }

    private nonisolated func pastureSortComparison(_ lhs: CDPasture, _ rhs: CDPasture) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private nonisolated func animals(in pasture: CDPasture) -> [CDAnimal] {
        pasture.animals?.allObjects.compactMap { $0 as? CDAnimal } ?? []
    }

    private nonisolated func isActiveInHerd(_ animal: CDAnimal) -> Bool {
        AnimalStatus(rawValue: animal.statusRawValue) == .active && !animal.isArchived
    }

    private nonisolated func makeAnimalSummary(_ animal: CDAnimal) -> AnimalSummary {
        let tags = animal.tags?.allObjects.compactMap { $0 as? CDAnimalTag } ?? []
        let primary = tags.first { $0.isPrimary && $0.isActive }
        let damTags = animal.dam?.tags?.allObjects.compactMap { $0 as? CDAnimalTag } ?? []
        let damPrimary = damTags.first { $0.isPrimary && $0.isActive }
        let health = animal.healthRecords?.allObjects.compactMap { $0 as? CDHealthRecord } ?? []
        let hasCastrationRecord = health.contains {
            AnimalTypeClassifier.isCastrationOrBandingTreatment($0.treatment)
        }
        let hasMaternalOffspring = (animal.damOffspring?.count ?? 0) > 0
        let sex = Sex(rawValue: animal.sexRawValue) ?? .unknown
        let status = AnimalStatus(rawValue: animal.statusRawValue) ?? .active
        let animalType = AnimalTypeClassifier.classify(
            sex: sex,
            birthDate: animal.birthDate,
            hasMaternalOffspring: hasMaternalOffspring,
            hasCastrationOrBandingRecord: hasCastrationRecord
        )
        let features = (try? JSONDecoder().decode(
            [DistinguishingFeature].self,
            from: animal.distinguishingFeaturesData
        )) ?? []

        return AnimalSummary(
            id: animal.id,
            name: animal.name,
            displayTagNumber: primary?.number ?? "",
            displayTagColorID: primary?.color?.id,
            damDisplayTagNumber: damPrimary?.number,
            damDisplayTagColorID: damPrimary?.color?.id,
            sex: sex,
            animalType: animalType,
            firstDistinguishingFeature: features.firstOrderedDistinguishingFeatureDescription,
            birthDate: animal.birthDate,
            status: status,
            isArchived: animal.isArchived,
            pastureID: animal.currentPasture?.id,
            pastureName: animal.currentPasture?.name,
            location: animal.activeWorkingSession == nil ? .pasture : .workingPen
        )
    }
}
