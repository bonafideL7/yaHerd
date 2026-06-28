import Foundation
import SwiftUI

enum MissingAnimalDetailDependencyError: LocalizedError {
    case animalEditorRepository
    case animalDetailRepository
    case animalTimelineReader
    case animalParentOptionReader
    case animalHealthRecordAdder
    case animalPregnancyCheckAdder

    var errorDescription: String? {
        switch self {
        case .animalEditorRepository:
            return "Animal editor repository has not been configured."
        case .animalDetailRepository:
            return "Animal detail repository has not been configured."
        case .animalTimelineReader:
            return "Animal timeline reader has not been configured."
        case .animalParentOptionReader:
            return "Animal parent option reader has not been configured."
        case .animalHealthRecordAdder:
            return "Animal health record adder has not been configured."
        case .animalPregnancyCheckAdder:
            return "Animal pregnancy check adder has not been configured."
        }
    }
}

private struct MissingAnimalEditorRepository: AnimalEditorRepository {
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        throw MissingAnimalDetailDependencyError.animalEditorRepository
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalEditorRepository
    }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalEditorRepository
    }
}

private struct MissingAnimalDetailRepository: AnimalDetailRepository {
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func delete(ids: [UUID]) throws {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func archive(ids: [UUID]) throws {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func restore(ids: [UUID]) throws {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }

    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalDetailRepository
    }
}

private struct MissingAnimalTimelineReader: AnimalTimelineReading {
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
        throw MissingAnimalDetailDependencyError.animalTimelineReader
    }
}

private struct MissingAnimalParentOptionReader: AnimalParentOptionReading {
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
        throw MissingAnimalDetailDependencyError.animalParentOptionReader
    }
}

private struct MissingAnimalHealthRecordAdder: AnimalHealthRecordAdding {
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalHealthRecordAdder
    }
}

private struct MissingAnimalPregnancyCheckAdder: AnimalPregnancyCheckAdding {
    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot {
        throw MissingAnimalDetailDependencyError.animalPregnancyCheckAdder
    }
}

private struct AnimalEditorRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalEditorRepository = MissingAnimalEditorRepository()
}

private struct AnimalDetailRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalDetailRepository = MissingAnimalDetailRepository()
}

private struct AnimalTimelineReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalTimelineReading = MissingAnimalTimelineReader()
}

private struct AnimalParentOptionReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalParentOptionReading = MissingAnimalParentOptionReader()
}

private struct AnimalHealthRecordAdderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalHealthRecordAdding = MissingAnimalHealthRecordAdder()
}

private struct AnimalPregnancyCheckAdderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalPregnancyCheckAdding = MissingAnimalPregnancyCheckAdder()
}

extension EnvironmentValues {
    var animalEditorRepository: any AnimalEditorRepository {
        get { self[AnimalEditorRepositoryEnvironmentKey.self] }
        set { self[AnimalEditorRepositoryEnvironmentKey.self] = newValue }
    }

    var animalDetailRepository: any AnimalDetailRepository {
        get { self[AnimalDetailRepositoryEnvironmentKey.self] }
        set { self[AnimalDetailRepositoryEnvironmentKey.self] = newValue }
    }

    var animalTimelineReader: any AnimalTimelineReading {
        get { self[AnimalTimelineReaderEnvironmentKey.self] }
        set { self[AnimalTimelineReaderEnvironmentKey.self] = newValue }
    }

    var animalParentOptionReader: any AnimalParentOptionReading {
        get { self[AnimalParentOptionReaderEnvironmentKey.self] }
        set { self[AnimalParentOptionReaderEnvironmentKey.self] = newValue }
    }

    var animalHealthRecordAdder: any AnimalHealthRecordAdding {
        get { self[AnimalHealthRecordAdderEnvironmentKey.self] }
        set { self[AnimalHealthRecordAdderEnvironmentKey.self] = newValue }
    }

    var animalPregnancyCheckAdder: any AnimalPregnancyCheckAdding {
        get { self[AnimalPregnancyCheckAdderEnvironmentKey.self] }
        set { self[AnimalPregnancyCheckAdderEnvironmentKey.self] = newValue }
    }
}
