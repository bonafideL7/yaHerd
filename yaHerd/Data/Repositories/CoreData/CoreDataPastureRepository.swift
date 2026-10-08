@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataPastureRepository:
    PastureListManagingRepository,
    PastureDetailReader,
    PastureResidentAnimalReader,
    PastureReferenceDataReader,
    PastureGrazingMarking,
    PastureExistenceChecking,
    PastureNameChecking,
    PastureCreating,
    PastureUpdating,
    PastureOrdering,
    PastureGroupListReader,
    PastureGroupDetailReader,
    PastureGroupExistenceChecking,
    PastureGroupNameChecking,
    PastureGroupCreating,
    PastureGroupUpdating,
    PastureGroupDeleting,
    PastureGroupAssignmentWriting
{
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let residentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        residentWriteCoordinator: CoreDataPastureResidentWriteCoordinator,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.residentWriteCoordinator = residentWriteCoordinator
        self.lookup = lookup
    }

    convenience init(selection: any CurrentHerdSelectionReading, assembly: CoreDataPersistenceAssembly) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            residentWriteCoordinator: assembly.pastureResidentWriteCoordinator,
            lookup: assembly.lookup
        )
    }

    func fetchPastures() throws -> [PastureSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            return try Self.fetchPastures(herd: herd, in: context).map(Self.summary)
        }
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else { throw HerdRepositoryError.missingHerd }
            guard let pasture = try lookup.herdOwned(CDPasture.self, id: id, herdID: herdID, in: context) else {
                return nil
            }
            return Self.detail(pasture)
        }
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else { throw HerdRepositoryError.missingHerd }
            guard let pasture = try lookup.herdOwned(CDPasture.self, id: pastureID, herdID: herdID, in: context) else {
                return []
            }
            let request = NSFetchRequest<CDAnimal>(entityName: CDAnimal.coreDataEntityName)
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND currentPasture == %@ AND isArchived == NO AND statusRawValue == %@",
                herdID as NSUUID,
                pasture,
                AnimalStatus.active.rawValue
            )
            let residents = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                residents,
                herdID: herdID
            )
            return try residents
                .map { try CoreDataAnimalProjection.summary($0) }
                .sorted {
                    $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending
                }
        }
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(
                CDPasture.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureValidationError.pastureNotFound
            }
            pasture.lastGrazedDate = date
        }
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            return try Self.fetchPastures(herd: herd, in: context)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { PastureOption(id: $0.id, name: $0.name) }
        }
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        try validatePastureIDsExistInReadScope(ids)
    }

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            return try Self.fetchPastures(herd: herd, in: context).contains {
                $0.id != id && $0.name.caseInsensitiveCompare(normalized) == .orderedSame
            }
        }
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        let input = input.normalized
        if try nameExists(input.name, excluding: nil) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            let pasture = CDPasture(context: context)
            pasture.id = try self.uniqueID(for: CDPasture.self, herdID: herd.id, in: context)
            pasture.name = input.name
            pasture.acreage = input.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = input.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = input.targetAcresPerHead.map(NSNumber.init(value:))
            pasture.sortOrder = (try Self.fetchPastures(herd: herd, in: context).map(\.sortOrder).max() ?? -1) + 1
            pasture.herd = herd
            return Self.detail(pasture)
        }
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        let input = input.normalized
        if try nameExists(input.name, excluding: id) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(CDPasture.self, id: id, herdID: herd.id, in: context) else {
                throw PastureValidationError.pastureNotFound
            }
            pasture.name = input.name
            pasture.acreage = input.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = input.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = input.targetAcresPerHead.map(NSNumber.init(value:))
            return Self.detail(pasture)
        }
    }

    func reorder(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try validatePastureIDsExistInReadScope(ids)
        let requested = Set(ids)
        try performWrite { context, herd in
            let allPastures = try Self.fetchPastures(herd: herd, in: context)
            let byID = Dictionary(uniqueKeysWithValues: allPastures.map { ($0.id, $0) })
            for (index, id) in ids.enumerated() {
                byID[id]?.sortOrder = Int64(index)
            }
            let remaining = allPastures
                .filter { !requested.contains($0.id) }
                .sorted(by: Self.pastureSort)
            for (offset, pasture) in remaining.enumerated() {
                pasture.sortOrder = Int64(ids.count + offset)
            }
        }
    }

    func fetchPastureGroups() throws -> [PastureGroupSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            return try Self.fetchGroups(herd: herd, in: context).map(Self.groupSummary)
        }
    }

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else { throw HerdRepositoryError.missingHerd }
            guard let group = try lookup.herdOwned(CDPastureGroup.self, id: id, herdID: herdID, in: context) else {
                return nil
            }
            return Self.groupDetail(group)
        }
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        try validatePastureGroupIDsExistInReadScope(ids)
    }

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            return try Self.fetchGroups(herd: herd, in: context).contains {
                $0.id != id && $0.name.caseInsensitiveCompare(normalized) == .orderedSame
            }
        }
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let input = input.normalized
        if try groupNameExists(input.name, excluding: nil) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            let group = CDPastureGroup(context: context)
            group.id = try self.uniqueID(for: CDPastureGroup.self, herdID: herd.id, in: context)
            group.name = input.name
            group.grazeDays = Int64(input.grazeDays)
            group.restDays = Int64(input.restDays)
            group.herd = herd
            return Self.groupDetail(group)
        }
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let input = input.normalized
        if try groupNameExists(input.name, excluding: id) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            guard let group = try self.lookup.herdOwned(CDPastureGroup.self, id: id, herdID: herd.id, in: context) else {
                throw PastureValidationError.pastureGroupNotFound
            }
            group.name = input.name
            group.grazeDays = Int64(input.grazeDays)
            group.restDays = Int64(input.restDays)
            return Self.groupDetail(group)
        }
    }

    func deleteGroups(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try validatePastureGroupIDsExist(ids)
        let groupIDs = Set(ids)
        try performWrite { context, herd in
            for group in try Self.fetchGroups(herd: herd, in: context) where groupIDs.contains(group.id) {
                context.delete(group)
            }
        }
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(CDPasture.self, id: pastureID, herdID: herd.id, in: context) else {
                throw PastureValidationError.pastureNotFound
            }
            if let groupID {
                guard let group = try self.lookup.herdOwned(CDPastureGroup.self, id: groupID, herdID: herd.id, in: context) else {
                    throw PastureValidationError.pastureGroupNotFound
                }
                pasture.group = group
            } else {
                pasture.group = nil
            }
        }
    }

    private func validatePastureIDsExistInReadScope(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw PastureRepositoryError.duplicatePastureIDs }
        guard !ids.isEmpty else { return }
        let (context, herdID) = try makeReadScope()
        try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            let existingIDs = Set(try Self.fetchPastures(herd: herd, in: context).map(\.id))
            let missing = ids.filter { !existingIDs.contains($0) }
            guard missing.isEmpty else { throw PastureRepositoryError.pastureIDsNotFound(missing) }
        }
    }

    private func validatePastureGroupIDsExistInReadScope(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw PastureRepositoryError.duplicatePastureGroupIDs }
        guard !ids.isEmpty else { return }
        let (context, herdID) = try makeReadScope()
        try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            let existingIDs = Set(try Self.fetchGroups(herd: herd, in: context).map(\.id))
            let missing = ids.filter { !existingIDs.contains($0) }
            guard missing.isEmpty else { throw PastureRepositoryError.pastureGroupIDsNotFound(missing) }
        }
    }

    private nonisolated func uniqueID<Object>(
        for type: Object.Type,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws -> UUID
    where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        while true {
            let id = UUID()
            if try lookup.herdOwned(type, id: id, herdID: herdID, in: context) == nil {
                return id
            }
        }
    }

    private func makeReadScope() throws -> (NSManagedObjectContext, UUID) {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        return (contextFactory.makeReadContext(), herdID)
    }

    private func performWrite<Result: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        try residentWriteCoordinator.beginPastureWrite()
        defer { residentWriteCoordinator.endPastureWrite() }
        let context = try contextFactory.makeWriteContext()
        return try context.performAndWait {
            do {
                guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
                let result = try operation(context, herd)
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        context.rollback()
                        throw CoreDataPersistenceError.saveFailed(
                            description: error.localizedDescription
                        )
                    }
                }
                return result
            } catch {
                if context.hasChanges { context.rollback() }
                throw error
            }
        }
    }

    private nonisolated static func fetchPastures(herd: CDHerd, in context: NSManagedObjectContext) throws -> [CDPasture] {
        let request = NSFetchRequest<CDPasture>(entityName: CDPasture.coreDataEntityName)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    private nonisolated static func fetchGroups(herd: CDHerd, in context: NSManagedObjectContext) throws -> [CDPastureGroup] {
        let request = NSFetchRequest<CDPastureGroup>(entityName: CDPastureGroup.coreDataEntityName)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    private nonisolated static func activeAnimalCount(_ pasture: CDPasture) -> Int {
        (pasture.animals as? Set<CDAnimal> ?? []).filter {
            !$0.isArchived && AnimalStatus(rawValue: $0.statusRawValue) == .active
        }.count
    }

    private nonisolated static func summary(_ pasture: CDPasture) -> PastureSummary {
        PastureSummary(
            id: pasture.id, name: pasture.name,
            acreage: pasture.acreage?.doubleValue, usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: activeAnimalCount(pasture), sortOrder: Int(pasture.sortOrder),
            lastGrazedDate: pasture.lastGrazedDate, groupID: pasture.group?.id,
            groupName: pasture.group?.name, restDays: pasture.group.map { Int($0.restDays) }
        )
    }

    private nonisolated static func detail(_ pasture: CDPasture) -> PastureDetailSnapshot {
        PastureDetailSnapshot(
            id: pasture.id, name: pasture.name,
            acreage: pasture.acreage?.doubleValue, usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: activeAnimalCount(pasture), lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.id, groupName: pasture.group?.name
        )
    }

    private nonisolated static func groupSummary(_ group: CDPastureGroup) -> PastureGroupSummary {
        PastureGroupSummary(id: group.id, name: group.name, grazeDays: Int(group.grazeDays), restDays: Int(group.restDays), pastureCount: group.pastures?.count ?? 0)
    }

    private nonisolated static func groupDetail(_ group: CDPastureGroup) -> PastureGroupDetailSnapshot {
        let pastures = (group.pastures as? Set<CDPasture> ?? []).map(summary).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return PastureGroupDetailSnapshot(id: group.id, name: group.name, grazeDays: Int(group.grazeDays), restDays: Int(group.restDays), pastures: pastures)
    }

    private nonisolated static func pastureSort(_ lhs: CDPasture, _ rhs: CDPasture) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
