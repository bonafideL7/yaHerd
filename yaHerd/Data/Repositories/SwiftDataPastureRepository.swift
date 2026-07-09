import Foundation
import SwiftData

struct SwiftDataPastureRepository: PastureRepository {
    let context: ModelContext

    func fetchPastures() throws -> [PastureSummary] {
        try PerformanceLog.measure("SwiftDataPastureRepository.fetchPastures") {
            let descriptor = FetchDescriptor<Pasture>(
                sortBy: [
                    SortDescriptor(\Pasture.sortOrder),
                    SortDescriptor(\Pasture.name)
                ]
            )
            return try context.fetch(descriptor).map(PastureMapper.makeSummary)
        }
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        guard let pasture = try fetchModel(id: id) else { return nil }
        return PastureMapper.makeDetail(from: pasture)
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try PerformanceLog.measure("SwiftDataPastureRepository.fetchResidentAnimals") {
            let descriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    animal.pasture?.publicID == pastureID
                        && animal.status == AnimalStatus.active
                        && !animal.isSoftDeleted
                }
            )
            return try context.fetch(descriptor)
                .map(AnimalMapper.makeSummary)
                .sorted { lhs, rhs in
                    lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
                }
        }
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        return try context.fetch(descriptor).map { pasture in
            PastureOption(id: pasture.publicID, name: pasture.name)
        }
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        _ = try fetchModels(ids: ids)
    }

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fetchPasturesForNameLookup().contains { pasture in
            if let id, pasture.publicID == id {
                return false
            }
            return pasture.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        let normalizedInput = input.normalized
        if try nameExists(normalizedInput.name, excluding: nil) {
            throw PastureValidationError.duplicateName(normalizedInput.name)
        }

        let pasture = Pasture(
            name: normalizedInput.name,
            acreage: normalizedInput.acreage,
            usableAcreage: normalizedInput.usableAcreage,
            targetAcresPerHead: normalizedInput.targetAcresPerHead,
            sortOrder: try nextSortOrder()
        )
        try ensureUniquePasturePublicID(pasture)
        try context.insertIntoDefaultHerd(pasture)
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
        return PastureMapper.makeDetail(from: pasture)
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        guard let pasture = try fetchModel(id: id) else {
            throw PastureValidationError.pastureNotFound
        }

        let normalizedInput = input.normalized
        if try nameExists(normalizedInput.name, excluding: id) {
            throw PastureValidationError.duplicateName(normalizedInput.name)
        }

        pasture.name = normalizedInput.name
        pasture.acreage = normalizedInput.acreage
        pasture.usableAcreage = normalizedInput.usableAcreage
        pasture.targetAcresPerHead = normalizedInput.targetAcresPerHead
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")

        return PastureMapper.makeDetail(from: pasture)
    }

    func reorder(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let pasturesToReorder = try fetchModels(ids: ids)
        let requestedIDs = Set(ids)

        for (index, pasture) in pasturesToReorder.enumerated() {
            pasture.sortOrder = index
        }

        let remainingPastures = try fetchPastures(excluding: requestedIDs)
            .sorted(by: pastureSortComparison)

        for (offset, pasture) in remainingPastures.enumerated() {
            pasture.sortOrder = ids.count + offset
        }

        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let pasturesToDelete = try fetchModels(ids: ids)
        for pasture in pasturesToDelete {
            context.delete(pasture)
        }

        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
    }

    func fetchPastureGroups() throws -> [PastureGroupSummary] {
        let descriptor = FetchDescriptor<PastureGroup>(sortBy: [SortDescriptor(\PastureGroup.name)])
        return try context.fetch(descriptor).map(PastureMapper.makeGroupSummary)
    }

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        guard let group = try fetchGroupModel(id: id) else { return nil }
        return PastureMapper.makeGroupDetail(from: group)
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        _ = try fetchGroupModels(ids: ids)
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        let normalizedInput = input.normalized
        if try groupNameExists(normalizedInput.name, excluding: nil) {
            throw PastureValidationError.duplicateName(normalizedInput.name)
        }

        let group = PastureGroup(
            name: normalizedInput.name,
            grazeDays: normalizedInput.grazeDays,
            restDays: normalizedInput.restDays
        )
        try ensureUniquePastureGroupPublicID(group)
        try context.insertIntoDefaultHerd(group)
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
        return PastureMapper.makeGroupDetail(from: group)
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        guard let group = try fetchGroupModel(id: id) else {
            throw PastureValidationError.pastureGroupNotFound
        }

        let normalizedInput = input.normalized
        if try groupNameExists(normalizedInput.name, excluding: id) {
            throw PastureValidationError.duplicateName(normalizedInput.name)
        }

        group.name = normalizedInput.name
        group.grazeDays = normalizedInput.grazeDays
        group.restDays = normalizedInput.restDays
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
        return PastureMapper.makeGroupDetail(from: group)
    }

    func deleteGroups(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let groupsToDelete = try fetchGroupModels(ids: ids)
        for group in groupsToDelete {
            context.delete(group)
        }
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        guard let pasture = try fetchModel(id: pastureID) else {
            throw PastureValidationError.pastureNotFound
        }

        let group: PastureGroup?
        if let groupID {
            guard let foundGroup = try fetchGroupModel(id: groupID) else {
                throw PastureValidationError.pastureGroupNotFound
            }
            group = foundGroup
        } else {
            group = nil
        }

        pasture.group = group
        try PersistenceLog.save(context, operation: "SwiftDataPastureRepository")
    }

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fetchPastureGroupsForNameLookup().contains { group in
            if let id, group.publicID == id {
                return false
            }
            return group.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private func fetchModel(id: UUID) throws -> Pasture? {
        var descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchModels(ids: [UUID]) throws -> [Pasture] {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }
        guard !ids.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                ids.contains(pasture.publicID)
            }
        )
        let fetchedPastures = try context.fetch(descriptor)
        var pasturesByID: [UUID: Pasture] = [:]
        for pasture in fetchedPastures {
            pasturesByID[pasture.publicID] = pasture
        }

        let missingIDs = ids.filter { pasturesByID[$0] == nil }
        guard missingIDs.isEmpty else {
            throw PastureRepositoryError.pastureIDsNotFound(missingIDs)
        }

        return ids.compactMap { pasturesByID[$0] }
    }

    private func fetchGroupModel(id: UUID) throws -> PastureGroup? {
        var descriptor = FetchDescriptor<PastureGroup>(
            predicate: #Predicate<PastureGroup> { group in
                group.publicID == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchGroupModels(ids: [UUID]) throws -> [PastureGroup] {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureGroupIDs
        }
        guard !ids.isEmpty else { return [] }

        let descriptor = FetchDescriptor<PastureGroup>(
            predicate: #Predicate<PastureGroup> { group in
                ids.contains(group.publicID)
            }
        )
        let fetchedGroups = try context.fetch(descriptor)
        var groupsByID: [UUID: PastureGroup] = [:]
        for group in fetchedGroups {
            groupsByID[group.publicID] = group
        }

        let missingIDs = ids.filter { groupsByID[$0] == nil }
        guard missingIDs.isEmpty else {
            throw PastureRepositoryError.pastureGroupIDsNotFound(missingIDs)
        }

        return ids.compactMap { groupsByID[$0] }
    }

    private func fetchPastures(excluding ids: Set<UUID>) throws -> [Pasture] {
        guard !ids.isEmpty else {
            let descriptor = FetchDescriptor<Pasture>(
                sortBy: [
                    SortDescriptor(\Pasture.sortOrder),
                    SortDescriptor(\Pasture.name)
                ]
            )
            return try context.fetch(descriptor)
        }

        let idsToExclude = Array(ids)
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                !idsToExclude.contains(pasture.publicID)
            },
            sortBy: [
                SortDescriptor(\Pasture.sortOrder),
                SortDescriptor(\Pasture.name)
            ]
        )
        return try context.fetch(descriptor)
    }

    private func fetchPasturesForNameLookup() throws -> [Pasture] {
        let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        return try context.fetch(descriptor)
    }

    private func fetchPastureGroupsForNameLookup() throws -> [PastureGroup] {
        let descriptor = FetchDescriptor<PastureGroup>(sortBy: [SortDescriptor(\PastureGroup.name)])
        return try context.fetch(descriptor)
    }

    private func ensureUniquePasturePublicID(_ pasture: Pasture) throws {
        while try fetchModel(id: pasture.publicID) != nil {
            pasture.publicID = UUID()
        }
    }

    private func ensureUniquePastureGroupPublicID(_ group: PastureGroup) throws {
        while try fetchGroupModel(id: group.publicID) != nil {
            group.publicID = UUID()
        }
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<Pasture>(
            sortBy: [SortDescriptor(\Pasture.sortOrder, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }

    private func pastureSortComparison(_ lhs: Pasture, _ rhs: Pasture) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
