import Foundation
import SwiftData

struct SwiftDataPastureRepository: PastureRepository {
    let context: ModelContext

    func fetchPastures() throws -> [PastureSummary] {
        let descriptor = FetchDescriptor<Pasture>(
            sortBy: [
                SortDescriptor(\Pasture.sortOrder),
                SortDescriptor(\Pasture.name)
            ]
        )
        return try context.fetch(descriptor).map(PastureMapper.makeSummary)
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        guard let pasture = try fetchModel(id: id) else { return nil }
        return PastureMapper.makeDetail(from: pasture)
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        guard let pasture = try fetchModel(id: pastureID) else { return [] }
        return pasture.animals
            .filter(\.isActiveInHerd)
            .map(PastureMapper.makeResidentAnimalSummary)
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
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
        context.insert(pasture)
        try context.save()
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
        try context.save()

        return PastureMapper.makeDetail(from: pasture)
    }

    func reorder(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let pasturesToReorder = try fetchModels(ids: ids)
        let requestedIDs = Set(ids)

        for (index, pasture) in pasturesToReorder.enumerated() {
            pasture.sortOrder = index
        }

        let remainingPastures = try fetchAllPastures()
            .filter { !requestedIDs.contains($0.publicID) }
            .sorted(by: pastureSortComparison)

        for (offset, pasture) in remainingPastures.enumerated() {
            pasture.sortOrder = ids.count + offset
        }

        try context.save()
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let pasturesToDelete = try fetchModels(ids: ids)
        for pasture in pasturesToDelete {
            context.delete(pasture)
        }

        try context.save()
    }

    func createGroup(input: PastureGroupInput) throws {
        let normalizedInput = input.normalized
        if try groupNameExists(normalizedInput.name) {
            throw PastureValidationError.duplicateName(normalizedInput.name)
        }

        let group = PastureGroup(
            name: normalizedInput.name,
            grazeDays: normalizedInput.grazeDays,
            restDays: normalizedInput.restDays
        )
        context.insert(group)
        try context.save()
    }

    func groupNameExists(_ name: String) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fetchPastureGroupsForNameLookup().contains { group in
            group.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private func fetchModel(id: UUID) throws -> Pasture? {
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchModels(ids: [UUID]) throws -> [Pasture] {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }

        var models: [Pasture] = []
        var missingIDs: [UUID] = []

        for id in ids {
            if let pasture = try fetchModel(id: id) {
                models.append(pasture)
            } else {
                missingIDs.append(id)
            }
        }

        guard missingIDs.isEmpty else {
            throw PastureRepositoryError.pastureIDsNotFound(missingIDs)
        }

        return models
    }

    private func fetchAllPastures() throws -> [Pasture] {
        let descriptor = FetchDescriptor<Pasture>(
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
