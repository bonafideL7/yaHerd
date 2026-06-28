import Foundation
import SwiftUI

enum MissingAnimalListDependencyError: LocalizedError {
    case animalListRepository
    case pastureReferenceDataReader
    case sampleDataSeeder

    var errorDescription: String? {
        switch self {
        case .animalListRepository:
            return "Animal list repository has not been configured."
        case .pastureReferenceDataReader:
            return "Pasture reference data reader has not been configured."
        case .sampleDataSeeder:
            return "Sample data seeder has not been configured."
        }
    }
}

private struct MissingAnimalListRepository: AnimalListRepository {
    func fetchAnimals() throws -> [AnimalSummary] {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func delete(ids: [UUID]) throws {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func archive(ids: [UUID]) throws {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func restore(ids: [UUID]) throws {
        throw MissingAnimalListDependencyError.animalListRepository
    }

    func move(ids: [UUID], toPastureID: UUID?) throws {
        throw MissingAnimalListDependencyError.animalListRepository
    }
}

private struct MissingPastureReferenceDataReader: PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption] {
        throw MissingAnimalListDependencyError.pastureReferenceDataReader
    }
}

private struct MissingSampleDataSeeder: SampleDataSeeding {
    func seedSampleDataIfNeeded() {
        assertionFailure(MissingAnimalListDependencyError.sampleDataSeeder.localizedDescription)
    }

    func seedLargeSampleDataIfNeeded() {
        assertionFailure(MissingAnimalListDependencyError.sampleDataSeeder.localizedDescription)
    }
}

private struct AnimalListRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalListRepository = MissingAnimalListRepository()
}

private struct PastureReferenceDataReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureReferenceDataReader = MissingPastureReferenceDataReader()
}

private struct SampleDataSeederEnvironmentKey: EnvironmentKey {
    static let defaultValue: any SampleDataSeeding = MissingSampleDataSeeder()
}

extension EnvironmentValues {
    var animalListRepository: any AnimalListRepository {
        get { self[AnimalListRepositoryEnvironmentKey.self] }
        set { self[AnimalListRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureReferenceDataReader: any PastureReferenceDataReader {
        get { self[PastureReferenceDataReaderEnvironmentKey.self] }
        set { self[PastureReferenceDataReaderEnvironmentKey.self] = newValue }
    }

    var sampleDataSeeder: any SampleDataSeeding {
        get { self[SampleDataSeederEnvironmentKey.self] }
        set { self[SampleDataSeederEnvironmentKey.self] = newValue }
    }
}
