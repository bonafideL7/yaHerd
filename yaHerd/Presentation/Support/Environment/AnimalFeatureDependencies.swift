import Foundation
import SwiftUI

nonisolated struct AnimalFeatureDependencies {
    let listRepository: any AnimalListRepository
    let listQueryReader: any AnimalListQueryReading
    let editorRepository: any AnimalEditorRepository
    let detailRepository: any AnimalDetailRepository
    let timelineReader: any AnimalTimelineReading
    let parentOptionReader: any AnimalParentOptionReading
    let healthRecordAdder: any AnimalHealthRecordAdding
    let pregnancyCheckAdder: any AnimalPregnancyCheckAdding
    let pastureReferenceReader: any PastureReferenceDataReader
    let sampleDataSeeder: any SampleDataSeeding
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        listRepository: any AnimalListRepository,
        listQueryReader: any AnimalListQueryReading,
        editorRepository: any AnimalEditorRepository,
        detailRepository: any AnimalDetailRepository,
        timelineReader: any AnimalTimelineReading,
        parentOptionReader: any AnimalParentOptionReading,
        healthRecordAdder: any AnimalHealthRecordAdding,
        pregnancyCheckAdder: any AnimalPregnancyCheckAdding,
        pastureReferenceReader: any PastureReferenceDataReader,
        sampleDataSeeder: any SampleDataSeeding,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.listRepository = listRepository
        self.listQueryReader = listQueryReader
        self.editorRepository = editorRepository
        self.detailRepository = detailRepository
        self.timelineReader = timelineReader
        self.parentOptionReader = parentOptionReader
        self.healthRecordAdder = healthRecordAdder
        self.pregnancyCheckAdder = pregnancyCheckAdder
        self.pastureReferenceReader = pastureReferenceReader
        self.sampleDataSeeder = sampleDataSeeder
        self.mutationStream = mutationStream
    }

    @MainActor
    init(
        repository: any AnimalRepository,
        listQueryReader: any AnimalListQueryReading,
        pastureReferenceReader: any PastureReferenceDataReader,
        sampleDataSeeder: any SampleDataSeeding,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.init(
            listRepository: repository,
            listQueryReader: listQueryReader,
            editorRepository: repository,
            detailRepository: repository,
            timelineReader: repository,
            parentOptionReader: repository,
            healthRecordAdder: repository,
            pregnancyCheckAdder: repository,
            pastureReferenceReader: pastureReferenceReader,
            sampleDataSeeder: sampleDataSeeder,
            mutationStream: mutationStream
        )
    }

    @MainActor
    static func preview(
        listRepository: (any AnimalListRepository)? = nil,
        listQueryReader: (any AnimalListQueryReading)? = nil,
        editorRepository: (any AnimalEditorRepository)? = nil,
        detailRepository: (any AnimalDetailRepository)? = nil,
        timelineReader: (any AnimalTimelineReading)? = nil,
        parentOptionReader: (any AnimalParentOptionReading)? = nil,
        healthRecordAdder: (any AnimalHealthRecordAdding)? = nil,
        pregnancyCheckAdder: (any AnimalPregnancyCheckAdding)? = nil,
        pastureReferenceReader: (any PastureReferenceDataReader)? = nil,
        sampleDataSeeder: (any SampleDataSeeding)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        let missingRepository = MissingAnimalRepository()
        return Self(
            listRepository: listRepository ?? missingRepository,
            listQueryReader: listQueryReader ?? MissingAnimalListQueryReader(),
            editorRepository: editorRepository ?? missingRepository,
            detailRepository: detailRepository ?? missingRepository,
            timelineReader: timelineReader ?? missingRepository,
            parentOptionReader: parentOptionReader ?? missingRepository,
            healthRecordAdder: healthRecordAdder ?? missingRepository,
            pregnancyCheckAdder: pregnancyCheckAdder ?? missingRepository,
            pastureReferenceReader: pastureReferenceReader ?? MissingAnimalPastureReferenceReader(),
            sampleDataSeeder: sampleDataSeeder ?? MissingAnimalSampleDataSeeder(),
            mutationStream: mutationStream ?? InactiveApplicationMutationStream()
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

private struct MissingAnimalListQueryReader: AnimalListQueryReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        throw MissingAnimalFeatureDependencyError.dependency("Animal list query reader")
    }

    func fetchAnimalPastureOptions(limit: Int) async throws -> [PastureOption] {
        throw MissingAnimalFeatureDependencyError.dependency("Animal list query reader")
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
            listRepository: MissingAnimalRepository(),
            listQueryReader: MissingAnimalListQueryReader(),
            editorRepository: MissingAnimalRepository(),
            detailRepository: MissingAnimalRepository(),
            timelineReader: MissingAnimalRepository(),
            parentOptionReader: MissingAnimalRepository(),
            healthRecordAdder: MissingAnimalRepository(),
            pregnancyCheckAdder: MissingAnimalRepository(),
            pastureReferenceReader: MissingAnimalPastureReferenceReader(),
            sampleDataSeeder: MissingAnimalSampleDataSeeder(),
            mutationStream: InactiveApplicationMutationStream()
        )
    }
}

extension EnvironmentValues {
    var animalFeatureDependencies: AnimalFeatureDependencies {
        get { self[AnimalFeatureDependenciesKey.self] }
        set { self[AnimalFeatureDependenciesKey.self] = newValue }
    }
}
