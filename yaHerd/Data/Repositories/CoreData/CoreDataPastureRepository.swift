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
            let pastures = try Self.fetchPastures(herd: herd, in: context)
            if pastures.contains(where: { $0.group != nil }) {
                _ = try Self.fetchGroups(herd: herd, in: context)
            }
            return try pastures.map {
                try Self.summary($0, herdID: herdID)
            }
        }
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            try CoreDataAnimalMutation.validateUnownedImportedPastures(herd: herd, in: context)
            try CoreDataAnimalMutation.validateUnownedImportedAnimals(herd: herd, in: context)
            guard let pasture = try lookup.herdOwned(CDPasture.self, id: id, herdID: herdID, in: context) else {
                return nil
            }
            if pasture.group != nil {
                _ = try Self.fetchGroups(herd: herd, in: context)
            }
            return try Self.detail(pasture, herdID: herdID)
        }
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            try CoreDataAnimalMutation.validateUnownedImportedPastures(herd: herd, in: context)
            try CoreDataAnimalMutation.validateUnownedImportedAnimals(herd: herd, in: context)
            guard let pasture = try lookup.herdOwned(CDPasture.self, id: pastureID, herdID: herdID, in: context) else {
                return []
            }
            try CoreDataAnimalMutation.validateLinkedClinicalHistory(herd: herd, in: context)
            let request = NSFetchRequest<CDAnimal>(entityName: CDAnimal.coreDataEntityName)
            try CoreDataLookup().scope(request, toHerd: herd, in: context)
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND currentPasture == %@",
                herdID as NSUUID,
                pasture
            )
            let candidates = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                candidates,
                herdID: herdID
            )
            let residents = try candidates.filter { animal in
                _ = try CoreDataAnimalProjection.birthDate(animal)
                let status = try CoreDataAnimalProjection.status(animal)
                return !animal.isArchived && status == .active
            }
            return try residents
                .map { animal in
                    try CoreDataAnimalReadGraphValidator.validateAnimalReadRelationships(
                        animal,
                        herdID: herdID
                    )
                    return try CoreDataAnimalProjection.summary(animal)
                }
                .sorted { left, right in
                    let tagOrder = left.displayTagNumber.localizedStandardCompare(right.displayTagNumber)
                    if tagOrder != .orderedSame { return tagOrder == .orderedAscending }
                    return left.id.uuidString < right.id.uuidString
                }
        }
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(
                CDPasture.self,
                id: id,
                herdID: (try herd.requiredID()),
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
                .sorted { left, right in
                    let nameOrder = (left.name ?? "").localizedStandardCompare(right.name ?? "")
                    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                    return (try left.requiredID()).uuidString < (try right.requiredID()).uuidString
                }
                .map { PastureOption(id: try $0.requiredID(), name: try $0.validatedName()) }
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
                $0.id != id && $0.name?.caseInsensitiveCompare(normalized) == .orderedSame
            }
        }
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        let input = input.normalized
        if try nameExists(input.name, excluding: nil) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            let nextSortOrder = (try Self.fetchPastures(herd: herd, in: context).map(\.sortOrder).max() ?? -1) + 1
            let pasture = CDPasture(context: context)
            pasture.id = try self.uniqueID(for: CDPasture.self, herdID: (try herd.requiredID()), in: context)
            pasture.name = input.name
            pasture.acreage = input.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = input.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = input.targetAcresPerHead.map(NSNumber.init(value:))
            pasture.sortOrder = nextSortOrder
            pasture.herd = herd
            return try Self.detail(pasture, herdID: (try herd.requiredID()))
        }
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        let input = input.normalized
        if try nameExists(input.name, excluding: id) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(CDPasture.self, id: id, herdID: (try herd.requiredID()), in: context) else {
                throw PastureValidationError.pastureNotFound
            }
            if pasture.group != nil {
                _ = try Self.fetchGroups(herd: herd, in: context)
            }
            pasture.name = input.name
            pasture.acreage = input.acreage.map(NSNumber.init(value:))
            pasture.usableAcreage = input.usableAcreage.map(NSNumber.init(value:))
            pasture.targetAcresPerHead = input.targetAcresPerHead.map(NSNumber.init(value:))
            return try Self.detail(pasture, herdID: (try herd.requiredID()))
        }
    }

    func reorder(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try validatePastureIDsExistInReadScope(ids)
        let requested = Set(ids)
        try performWrite { context, herd in
            let allPastures = try Self.fetchPastures(herd: herd, in: context)
            let byID = Dictionary(uniqueKeysWithValues: try allPastures.map { (try $0.requiredID(), $0) })
            for (index, id) in ids.enumerated() {
                byID[id]?.sortOrder = Int64(index)
            }
            let remaining = try allPastures
                .filter { try !requested.contains($0.requiredID()) }
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
            let groups = try Self.fetchGroups(herd: herd, in: context)
            if groups.contains(where: { ($0.pastures?.count ?? 0) > 0 }) {
                _ = try Self.fetchPastures(herd: herd, in: context)
            }
            return try groups.map {
                try Self.groupSummary($0, herdID: herdID)
            }
        }
    }

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        guard let herdID = selection.currentHerdID else { throw HerdRepositoryError.missingHerd }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else { throw HerdRepositoryError.missingHerd }
            _ = try Self.fetchGroups(herd: herd, in: context)
            guard let group = try lookup.herdOwned(CDPastureGroup.self, id: id, herdID: herdID, in: context) else {
                return nil
            }
            if (group.pastures?.count ?? 0) > 0 {
                _ = try Self.fetchPastures(herd: herd, in: context)
            }
            return try Self.groupDetail(group, herdID: herdID)
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
                $0.id != id && $0.name?.caseInsensitiveCompare(normalized) == .orderedSame
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
            group.id = try self.uniqueID(for: CDPastureGroup.self, herdID: (try herd.requiredID()), in: context)
            group.name = input.name
            group.grazeDays = Int64(input.grazeDays)
            group.restDays = Int64(input.restDays)
            group.herd = herd
            return try Self.groupDetail(group, herdID: (try herd.requiredID()))
        }
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let input = input.normalized
        if try groupNameExists(input.name, excluding: id) {
            throw PastureValidationError.duplicateName(input.name)
        }
        return try performWrite { context, herd in
            guard let group = try self.lookup.herdOwned(CDPastureGroup.self, id: id, herdID: (try herd.requiredID()), in: context) else {
                throw PastureValidationError.pastureGroupNotFound
            }
            if (group.pastures?.count ?? 0) > 0 {
                _ = try Self.fetchPastures(herd: herd, in: context)
            }
            group.name = input.name
            group.grazeDays = Int64(input.grazeDays)
            group.restDays = Int64(input.restDays)
            return try Self.groupDetail(group, herdID: (try herd.requiredID()))
        }
    }

    func deleteGroups(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try validatePastureGroupIDsExist(ids)
        let groupIDs = Set(ids)
        try performWrite { context, herd in
            for group in try Self.fetchGroups(herd: herd, in: context) where groupIDs.contains(try group.requiredID()) {
                context.delete(group)
            }
        }
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        try performWrite { context, herd in
            guard let pasture = try self.lookup.herdOwned(CDPasture.self, id: pastureID, herdID: (try herd.requiredID()), in: context) else {
                throw PastureValidationError.pastureNotFound
            }
            if let groupID {
                guard let group = try self.lookup.herdOwned(CDPastureGroup.self, id: groupID, herdID: (try herd.requiredID()), in: context) else {
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
            let existingIDs = Set(try Self.fetchPastures(herd: herd, in: context).map { try $0.requiredID() })
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
            let existingIDs = Set(try Self.fetchGroups(herd: herd, in: context).map { try $0.requiredID() })
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
                try Self.validateLinkedGroupOwnership(herd: herd, in: context)
                let result = try operation(context, herd)
                if context.hasChanges {
                    try lookup.prepareForSave(herdID: herdID, in: context)
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
        try CoreDataLookup().scope(request, toHerd: herd, in: context)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        try validateLinkedGroupOwnership(herd: herd, in: context)
        let pastures = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(pastures, herdID: (try herd.requiredID()))
        for pasture in pastures {
            _ = try pasture.validatedName()
        }
        return pastures
    }

    private nonisolated static func fetchGroups(herd: CDHerd, in context: NSManagedObjectContext) throws -> [CDPastureGroup] {
        let request = NSFetchRequest<CDPastureGroup>(entityName: CDPastureGroup.coreDataEntityName)
        try CoreDataLookup().scope(request, toHerd: herd, in: context)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        try validateLinkedGroupOwnership(herd: herd, in: context)
        let groups = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(groups, herdID: (try herd.requiredID()))
        for group in groups {
            _ = try validatedGroupName(group)
        }
        return groups
    }

    // A partially imported Group can be linked to this Herd's Pasture before
    // its own Herd relationship arrives. Herd-scoped Group queries omit it.
    private nonisolated static func validateLinkedGroupOwnership(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        try CoreDataAnimalMutation.validateUnownedImportedPastures(herd: herd, in: context)
        try CoreDataAnimalMutation.validateUnownedImportedAnimals(herd: herd, in: context)
        let request = NSFetchRequest<CDPasture>(entityName: CDPasture.coreDataEntityName)
        try CoreDataLookup().scope(request, toHerd: herd, in: context)
        request.predicate = NSPredicate(
            format: "herd == %@ AND group != nil AND group.herd == nil",
            herd
        )
        request.fetchLimit = 1
        if let pasture = try context.fetch(request).first,
           let group = pasture.group {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDPastureGroup.coreDataEntityName,
                id: (try group.requiredID()),
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: nil
            )
        }
    }

    // Count and membership projections must not expose foreign-Herd relationships.
    private nonisolated static func validateHerdOwnership(
        entity: String,
        id: UUID,
        actualHerdID: UUID?,
        selectedHerdID: UUID
    ) throws {
        guard actualHerdID == selectedHerdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: entity,
                id: id,
                expectedHerdID: selectedHerdID,
                actualHerdID: actualHerdID
            )
        }
    }

    private nonisolated static func validatePastureReadGraph(
        _ pasture: CDPasture,
        herdID: UUID
    ) throws {
        _ = try pasture.validatedName()
        try validateHerdOwnership(
            entity: CDPasture.coreDataEntityName,
            id: (try pasture.requiredID()),
            actualHerdID: pasture.herd?.id,
            selectedHerdID: herdID
        )
        if let group = pasture.group {
            _ = try validatedGroupName(group)
            try validateHerdOwnership(
                entity: CDPastureGroup.coreDataEntityName,
                id: (try group.requiredID()),
                actualHerdID: group.herd?.id,
                selectedHerdID: herdID
            )
        }
        for resident in pasture.animals as? Set<CDAnimal> ?? [] {
            try validateHerdOwnership(
                entity: CDAnimal.coreDataEntityName,
                id: (try resident.requiredID()),
                actualHerdID: resident.herd?.id,
                selectedHerdID: herdID
            )
        }
    }

    private nonisolated static func validatedGroupName(_ group: CDPastureGroup) throws -> String {
        guard let name = group.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PastureValidationError.emptyName
        }
        return name
    }

    private nonisolated static func validateGroupReadGraph(
        _ group: CDPastureGroup,
        herdID: UUID
    ) throws {
        _ = try validatedGroupName(group)
        try validateHerdOwnership(
            entity: CDPastureGroup.coreDataEntityName,
            id: (try group.requiredID()),
            actualHerdID: group.herd?.id,
            selectedHerdID: herdID
        )
        for pasture in group.pastures as? Set<CDPasture> ?? [] {
            _ = try pasture.validatedName()
            try validateHerdOwnership(
                entity: CDPasture.coreDataEntityName,
                id: (try pasture.requiredID()),
                actualHerdID: pasture.herd?.id,
                selectedHerdID: herdID
            )
        }
    }

    private nonisolated static func activeAnimalCount(_ pasture: CDPasture) throws -> Int {
        try (pasture.animals as? Set<CDAnimal> ?? []).filter { animal in
            _ = try CoreDataAnimalProjection.birthDate(animal)
            let status = try CoreDataAnimalProjection.status(animal)
            return !animal.isArchived && status == .active
        }.count
    }

    private nonisolated static func summary(_ pasture: CDPasture, herdID: UUID) throws -> PastureSummary {
        try validatePastureReadGraph(pasture, herdID: herdID)
        return PastureSummary(
            id: (try pasture.requiredID()), name: try pasture.validatedName(),
            acreage: pasture.acreage?.doubleValue, usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: try activeAnimalCount(pasture), sortOrder: Int(pasture.sortOrder),
            lastGrazedDate: pasture.lastGrazedDate, groupID: pasture.group?.id,
            groupName: try pasture.group.map { try validatedGroupName($0) }, restDays: pasture.group.map { Int($0.restDays) }
        )
    }

    private nonisolated static func detail(_ pasture: CDPasture, herdID: UUID) throws -> PastureDetailSnapshot {
        try validatePastureReadGraph(pasture, herdID: herdID)
        return PastureDetailSnapshot(
            id: (try pasture.requiredID()), name: try pasture.validatedName(),
            acreage: pasture.acreage?.doubleValue, usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: try activeAnimalCount(pasture), lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.id, groupName: try pasture.group.map { try validatedGroupName($0) }
        )
    }

    private nonisolated static func groupSummary(_ group: CDPastureGroup, herdID: UUID) throws -> PastureGroupSummary {
        try validateGroupReadGraph(group, herdID: herdID)
        return PastureGroupSummary(id: (try group.requiredID()), name: try validatedGroupName(group), grazeDays: Int(group.grazeDays), restDays: Int(group.restDays), pastureCount: group.pastures?.count ?? 0)
    }

    private nonisolated static func groupDetail(_ group: CDPastureGroup, herdID: UUID) throws -> PastureGroupDetailSnapshot {
        try validateGroupReadGraph(group, herdID: herdID)
        let pastures = try (group.pastures as? Set<CDPasture> ?? []).map {
            try summary($0, herdID: herdID)
        }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        return PastureGroupDetailSnapshot(id: (try group.requiredID()), name: try validatedGroupName(group), grazeDays: Int(group.grazeDays), restDays: Int(group.restDays), pastures: pastures)
    }

    private nonisolated static func pastureSort(_ lhs: CDPasture, _ rhs: CDPasture) throws -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        let nameOrder = (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "")
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return (try lhs.requiredID()).uuidString < (try rhs.requiredID()).uuidString
    }
}
