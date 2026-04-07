import Foundation
import SwiftData

struct SwiftDataPastureRepository: PastureRepository {
    let context: ModelContext

    func fetchPastures() throws -> [PastureSummary] {
        let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        return try context.fetch(descriptor).map { pasture in
            makeSummary(from: pasture)
        }
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        if let pasture = try fetchModel(id: id) {
            return makeDetail(from: pasture)
        }
        return nil
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
        return makeDetail(from: pasture)
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

        return makeDetail(from: pasture)
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let identifierSet = Set(ids)
        let descriptor = FetchDescriptor<Pasture>()
        for pasture in try context.fetch(descriptor) where identifierSet.contains(pasture.publicID) {
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

    private func makeSummary(from pasture: Pasture) -> PastureSummary {
        PastureSummary(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter(\.isActiveInHerd).count
        )
    }

    private func makeDetail(from pasture: Pasture) -> PastureDetailSnapshot {
        PastureDetailSnapshot(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter(\.isActiveInHerd).count,
            lastGrazedDate: pasture.lastGrazedDate
        )
    }
}
