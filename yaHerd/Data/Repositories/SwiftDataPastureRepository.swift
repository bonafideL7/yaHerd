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
        let pasture = Pasture(
            name: input.name,
            acreage: input.acreage,
            usableAcreage: input.usableAcreage,
            targetAcresPerHead: input.targetAcresPerHead
        )
        context.insert(pasture)
        try context.save()
        return PastureMapper.makeDetail(from: pasture)
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        guard let pasture = try fetchModel(id: id) else {
            throw PastureValidationError.pastureNotFound
        }

        pasture.name = input.name
        pasture.acreage = input.acreage
        pasture.usableAcreage = input.usableAcreage
        pasture.targetAcresPerHead = input.targetAcresPerHead
        try context.save()

        return PastureMapper.makeDetail(from: pasture)
    }

    func createGroup(input: PastureGroupInput) throws {
        let group = PastureGroup(name: input.name, grazeDays: input.grazeDays, restDays: input.restDays)
        context.insert(group)
        try context.save()
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        
        let identifierSet = Set(ids)
        
        let pastureDescriptor = FetchDescriptor<Pasture>()
        let pasturesToDelete = try context.fetch(pastureDescriptor)
            .filter { identifierSet.contains($0.publicID) }
        
        let sessionDescriptor = FetchDescriptor<FieldCheckSession>()
        let sessionsToDelete = try context.fetch(sessionDescriptor)
            .filter { session in
                guard let pastureID = session.pastureID else { return false }
                return identifierSet.contains(pastureID)
            }
        
        for session in sessionsToDelete {
            context.delete(session)
        }
        
        for pasture in pasturesToDelete {
            context.delete(pasture)
        }
        
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
}
