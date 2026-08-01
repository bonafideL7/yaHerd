import Foundation

@MainActor
struct BackgroundQueryingAnimalListRepository: AnimalListRepository {
    let base: any AnimalListRepository
    nonisolated let queryReader: any AnimalListQueryReading

    func fetchAnimals() throws -> [AnimalSummary] {
        try base.fetchAnimals()
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        try base.fetchAnimalDetail(id: id)
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        try base.create(input: input)
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        try base.update(id: id, input: input)
    }

    func delete(ids: [UUID]) throws {
        try base.delete(ids: ids)
    }

    func archive(ids: [UUID]) throws {
        try base.archive(ids: ids)
    }

    func restore(ids: [UUID]) throws {
        try base.restore(ids: ids)
    }

    func move(ids: [UUID], toPastureID pastureID: UUID?) throws {
        try base.move(ids: ids, toPastureID: pastureID)
    }
}

extension BackgroundQueryingAnimalListRepository: AnimalListQueryReading {
    nonisolated func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        try await queryReader.fetchAnimalSummaryPage(request)
    }

    nonisolated func fetchAnimalPastureOptions(limit: Int) async throws -> [PastureOption] {
        try await queryReader.fetchAnimalPastureOptions(limit: limit)
    }
}
