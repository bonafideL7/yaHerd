import Foundation
import SwiftUI

nonisolated struct AnimalFeatureDependencies {
    let listReadModel: any AnimalListReadModel
    let timelineReadModel: any AnimalTimelineReadModel
    let listRepository: any AnimalListRepository
    let editorRepository: any AnimalEditorRepository
    let detailRepository: any AnimalDetailRepository
    let timelineReader: any AnimalTimelineReading
    let parentOptionReader: any AnimalParentOptionReading
    let healthRecordAdder: any AnimalHealthRecordAdding
    let pregnancyCheckAdder: any AnimalPregnancyCheckAdding
    let pastureReferenceReader: any PastureReferenceDataReader
    let sampleDataSeeder: any SampleDataSeeding

    nonisolated init(
        listReadModel: any AnimalListReadModel,
        timelineReadModel: any AnimalTimelineReadModel,
        listRepository: any AnimalListRepository,
        editorRepository: any AnimalEditorRepository,
        detailRepository: any AnimalDetailRepository,
        timelineReader: any AnimalTimelineReading,
        parentOptionReader: any AnimalParentOptionReading,
        healthRecordAdder: any AnimalHealthRecordAdding,
        pregnancyCheckAdder: any AnimalPregnancyCheckAdding,
        pastureReferenceReader: any PastureReferenceDataReader,
        sampleDataSeeder: any SampleDataSeeding
    ) {
        self.listReadModel = listReadModel
        self.timelineReadModel = timelineReadModel
        self.listRepository = listRepository
        self.editorRepository = editorRepository
        self.detailRepository = detailRepository
        self.timelineReader = timelineReader
        self.parentOptionReader = parentOptionReader
        self.healthRecordAdder = healthRecordAdder
        self.pregnancyCheckAdder = pregnancyCheckAdder
        self.pastureReferenceReader = pastureReferenceReader
        self.sampleDataSeeder = sampleDataSeeder
    }

    @MainActor
    init(
        repository: any AnimalRepository,
        listReadModel: any AnimalListReadModel,
        timelineReadModel: any AnimalTimelineReadModel,
        pastureReferenceReader: any PastureReferenceDataReader,
        sampleDataSeeder: any SampleDataSeeding
    ) {
        self.init(
            listReadModel: listReadModel,
            timelineReadModel: timelineReadModel,
            listRepository: repository,
            editorRepository: repository,
            detailRepository: repository,
            timelineReader: repository,
            parentOptionReader: repository,
            healthRecordAdder: repository,
            pregnancyCheckAdder: repository,
            pastureReferenceReader: pastureReferenceReader,
            sampleDataSeeder: sampleDataSeeder
        )
    }

    @MainActor
    static func preview(
        listReadModel: (any AnimalListReadModel)? = nil,
        timelineReadModel: (any AnimalTimelineReadModel)? = nil,
        listRepository: (any AnimalListRepository)? = nil,
        editorRepository: (any AnimalEditorRepository)? = nil,
        detailRepository: (any AnimalDetailRepository)? = nil,
        timelineReader: (any AnimalTimelineReading)? = nil,
        parentOptionReader: (any AnimalParentOptionReading)? = nil,
        healthRecordAdder: (any AnimalHealthRecordAdding)? = nil,
        pregnancyCheckAdder: (any AnimalPregnancyCheckAdding)? = nil,
        pastureReferenceReader: (any PastureReferenceDataReader)? = nil,
        sampleDataSeeder: (any SampleDataSeeding)? = nil
    ) -> Self {
        let missingRepository = MissingAnimalRepository()
        return Self(
            listReadModel: listReadModel ?? MissingAnimalListReadModel(),
            timelineReadModel: timelineReadModel ?? MissingAnimalTimelineReadModel(),
            listRepository: listRepository ?? missingRepository,
            editorRepository: editorRepository ?? missingRepository,
            detailRepository: detailRepository ?? missingRepository,
            timelineReader: timelineReader ?? missingRepository,
            parentOptionReader: parentOptionReader ?? missingRepository,
            healthRecordAdder: healthRecordAdder ?? missingRepository,
            pregnancyCheckAdder: pregnancyCheckAdder ?? missingRepository,
            pastureReferenceReader: pastureReferenceReader ?? MissingAnimalPastureReferenceReader(),
            sampleDataSeeder: sampleDataSeeder ?? MissingAnimalSampleDataSeeder()
        )
    }
}

private enum MissingAnimalFeatureDependencyError: LocalizedError {
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .dependency(let name):
            return "\(name) has not been configured."
        }
    }
}

private struct MissingAnimalListReadModel: AnimalListReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchAnimalListSnapshot(pageSize: Int) async throws -> AnimalListSnapshot {
        throw MissingAnimalFeatureDependencyError.dependency("Animal list read model")
    }
}

private struct MissingAnimalTimelineReadModel: AnimalTimelineReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchTimeline(id: UUID) async throws -> [AnimalTimelineEvent] {
        throw MissingAnimalFeatureDependencyError.dependency("Animal timeline read model")
    }
}

private struct MissingAnimalRepository: AnimalRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingAnimalFeatureDependencyError {
        .dependency(name)
    }

    func fetchAnimals() throws -> [AnimalSummary] { throw missing("Animal list repository") }
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? { throw missing("Animal detail repository") }
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] { throw missing("Animal timeline reader") }
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { throw missing("Animal status reference reader") }
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] { throw missing("Animal parent option reader") }
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? { throw missing("Animal offspring draft reader") }
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot { throw missing("Animal creator") }
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot { throw missing("Animal updater") }
    func delete(ids: [UUID]) throws { throw missing("Animal deleter") }
    func archive(ids: [UUID]) throws { throw missing("Animal archiver") }
    func restore(ids: [UUID]) throws { throw missing("Animal restorer") }
    func move(ids: [UUID], toPastureID: UUID?) throws { throw missing("Animal pasture mover") }
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { throw missing("Animal tag adder") }
    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { throw missing("Animal tag updater") }
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw missing("Animal tag promoter") }
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw missing("Animal tag retirer") }
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot { throw missing("Animal health record writer") }
    func addPregnancyCheck(
        animalID: UUID,
        input: PregnancyCheckInput
    ) throws -> AnimalDetailSnapshot {
        throw missing("Animal pregnancy check writer")
    }
}

private struct MissingAnimalPastureReferenceReader: PastureReferenceDataReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureOptions() throws -> [PastureOption] {
        throw MissingAnimalFeatureDependencyError.dependency("Animal pasture reference reader")
    }
}

private struct MissingAnimalSampleDataSeeder: SampleDataSeeding {
    nonisolated init(environmentFallback _: Void = ()) {}

    func seedSampleDataIfNeeded() {
        assertionFailure(MissingAnimalFeatureDependencyError.dependency("Sample data seeder").localizedDescription)
    }

    func seedLargeSampleDataIfNeeded() {
        assertionFailure(MissingAnimalFeatureDependencyError.dependency("Sample data seeder").localizedDescription)
    }
}

private struct AnimalFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: AnimalFeatureDependencies {
        AnimalFeatureDependencies(
            listReadModel: MissingAnimalListReadModel(),
            timelineReadModel: MissingAnimalTimelineReadModel(),
            listRepository: MissingAnimalRepository(),
            editorRepository: MissingAnimalRepository(),
            detailRepository: MissingAnimalRepository(),
            timelineReader: MissingAnimalRepository(),
            parentOptionReader: MissingAnimalRepository(),
            healthRecordAdder: MissingAnimalRepository(),
            pregnancyCheckAdder: MissingAnimalRepository(),
            pastureReferenceReader: MissingAnimalPastureReferenceReader(),
            sampleDataSeeder: MissingAnimalSampleDataSeeder()
        )
    }
}

extension EnvironmentValues {
    var animalFeatureDependencies: AnimalFeatureDependencies {
        get { self[AnimalFeatureDependenciesKey.self] }
        set { self[AnimalFeatureDependenciesKey.self] = newValue }
    }
}
