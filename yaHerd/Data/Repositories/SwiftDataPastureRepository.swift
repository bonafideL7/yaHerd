import Foundation
import SwiftData

struct SwiftDataPastureRepository: PastureRepository {
    let context: ModelContext

    func fetchPastures() throws -> [PastureSummary] {
        let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        return try context.fetch(descriptor).map(PastureMapper.makeSummary)
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        if let pasture = try fetchModel(id: id) {
            return PastureMapper.makeDetail(from: pasture)
        }
        return nil
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

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<Pasture>()
        return try context.fetch(descriptor).contains { pasture in
            if let id, pasture.publicID == id {
                return false
            }
            return pasture.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try nameExists(normalizedName, excluding: nil) {
            throw PastureValidationError.duplicateName(normalizedName)
        }

        let pasture = Pasture(
            name: normalizedName,
            acreage: input.acreage,
            usableAcreage: input.usableAcreage,
            targetAcresPerHead: input.targetAcresPerHead
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

        let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try nameExists(normalizedName, excluding: id) {
            throw PastureValidationError.duplicateName(normalizedName)
        }

        pasture.name = normalizedName
        pasture.acreage = input.acreage
        pasture.usableAcreage = input.usableAcreage
        pasture.targetAcresPerHead = input.targetAcresPerHead
        try context.save()

        return PastureMapper.makeDetail(from: pasture)
    }

    func createGroup(input: PastureGroupInput) throws {
        let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try groupNameExists(normalizedName) {
            throw PastureValidationError.duplicateName(normalizedName)
        }

        let group = PastureGroup(name: normalizedName, grazeDays: input.grazeDays, restDays: input.restDays)
        context.insert(group)
        try context.save()
    }

    private func fetchModel(id: UUID) throws -> Pasture? {
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func ensureUniquePasturePublicID(_ pasture: Pasture) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<Pasture>()).map(\.publicID))
        while existingIDs.contains(pasture.publicID) {
            pasture.publicID = UUID()
        }
    }

    private func groupNameExists(_ name: String) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<PastureGroup>()
        return try context.fetch(descriptor).contains { group in
            group.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }
}
