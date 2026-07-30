import Foundation
import SwiftUI

nonisolated struct FieldCheckFeatureDependencies {
    let overviewReader: any FieldCheckOverviewReading
    let sessionSetupRepository: any FieldCheckSessionSetupRepository
    let sessionDetailRepository: any FieldCheckSessionDetailRepository
    let animalDetailRepository: any FieldCheckAnimalDetailRepository
    let animalListRepository: any AnimalListRepository
    let animalRepository: any AnimalDetailRepository
    let pastureReferenceReader: any PastureReferenceDataReader

    nonisolated init(
        overviewReader: any FieldCheckOverviewReading,
        sessionSetupRepository: any FieldCheckSessionSetupRepository,
        sessionDetailRepository: any FieldCheckSessionDetailRepository,
        animalDetailRepository: any FieldCheckAnimalDetailRepository,
        animalListRepository: any AnimalListRepository,
        animalRepository: any AnimalDetailRepository,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        self.overviewReader = overviewReader
        self.sessionSetupRepository = sessionSetupRepository
        self.sessionDetailRepository = sessionDetailRepository
        self.animalDetailRepository = animalDetailRepository
        self.animalListRepository = animalListRepository
        self.animalRepository = animalRepository
        self.pastureReferenceReader = pastureReferenceReader
    }

    @MainActor
    init(
        repository: any FieldCheckRepository,
        overviewReadModel: any HomeFieldCheckReadModel,
        animalRepository: any AnimalRepository,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        let overviewReader = ReadModelBackedFieldCheckOverviewRepository(
            base: repository,
            fieldCheckOverviewReadModel: overviewReadModel
        )
        self.init(
            overviewReader: overviewReader,
            sessionSetupRepository: repository,
            sessionDetailRepository: repository,
            animalDetailRepository: repository,
            animalListRepository: animalRepository,
            animalRepository: animalRepository,
            pastureReferenceReader: pastureReferenceReader
        )
    }

    @MainActor
    static func preview(
        overviewReader: (any FieldCheckOverviewReading)? = nil,
        sessionSetupRepository: (any FieldCheckSessionSetupRepository)? = nil,
        sessionDetailRepository: (any FieldCheckSessionDetailRepository)? = nil,
        animalDetailRepository: (any FieldCheckAnimalDetailRepository)? = nil,
        animalListRepository: (any AnimalListRepository)? = nil,
        animalRepository: (any AnimalDetailRepository)? = nil,
        pastureReferenceReader: (any PastureReferenceDataReader)? = nil
    ) -> Self {
        let missingRepository = MissingFieldCheckRepository()
        let missingAnimalRepository = MissingFieldCheckAnimalRepository()
        return Self(
            overviewReader: overviewReader ?? missingRepository,
            sessionSetupRepository: sessionSetupRepository ?? missingRepository,
            sessionDetailRepository: sessionDetailRepository ?? missingRepository,
            animalDetailRepository: animalDetailRepository ?? missingRepository,
            animalListRepository: animalListRepository ?? missingAnimalRepository,
            animalRepository: animalRepository ?? missingAnimalRepository,
            pastureReferenceReader: pastureReferenceReader ?? MissingFieldCheckPastureReferenceReader()
        )
    }
}

private enum MissingFieldCheckFeatureDependencyError: LocalizedError {
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .dependency(let name):
            return "\(name) has not been configured."
        }
    }
}

private struct MissingFieldCheckRepository: FieldCheckRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingFieldCheckFeatureDependencyError {
        .dependency(name)
    }

    func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) throws { throw missing("Field-check pasture archive writer") }
    func fetchSessions() throws -> [FieldCheckSessionSummary] { throw missing("Field-check overview reader") }
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] { throw missing("Field-check open finding reader") }
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? { throw missing("Field-check session detail repository") }
    func createSession(input: FieldCheckSessionStartInput) throws -> UUID { throw missing("Field-check session setup repository") }
    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) throws { throw missing("Field-check quick-count writer") }
    func updateNotes(sessionID: UUID, notes: String) throws { throw missing("Field-check notes writer") }
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws { throw missing("Field-check animal count writer") }
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws { throw missing("Field-check missing-animal writer") }
    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, checkedAt: Date) throws { throw missing("Field-check tracked-animal writer") }
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws { throw missing("Field-check finding writer") }
    func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput) throws { throw missing("Field-check finding writer") }
    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus
    ) throws {
        throw missing("Field-check finding status writer")
    }
    func deleteFinding(sessionID: UUID, findingID: UUID) throws { throw missing("Field-check finding deleter") }
    func completeSession(id: UUID) throws { throw missing("Field-check completion writer") }
    func reopenSession(id: UUID) throws { throw missing("Field-check completion writer") }
}

private struct MissingFieldCheckAnimalRepository: AnimalRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingFieldCheckFeatureDependencyError {
        .dependency(name)
    }

    func fetchAnimals() throws -> [AnimalSummary] { throw missing("Field-check animal list repository") }
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? { throw missing("Field-check animal repository") }
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] { throw missing("Field-check animal timeline reader") }
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { throw missing("Field-check animal status reader") }
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] { throw missing("Field-check animal parent reader") }
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? { throw missing("Field-check animal offspring reader") }
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot { throw missing("Field-check animal creator") }
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot { throw missing("Field-check animal updater") }
    func delete(ids: [UUID]) throws { throw missing("Field-check animal deleter") }
    func archive(ids: [UUID]) throws { throw missing("Field-check animal archiver") }
    func restore(ids: [UUID]) throws { throw missing("Field-check animal restorer") }
    func move(ids: [UUID], toPastureID: UUID?) throws { throw missing("Field-check animal mover") }
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { throw missing("Field-check animal tag adder") }
    func updateTag(
        animalID: UUID,
        tagID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        throw missing("Field-check animal tag updater")
    }
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw missing("Field-check animal tag promoter") }
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw missing("Field-check animal tag retirer") }
    func addHealthRecord(
        animalID: UUID,
        input: HealthRecordInput
    ) throws -> AnimalDetailSnapshot {
        throw missing("Field-check animal health writer")
    }
    func addPregnancyCheck(
        animalID: UUID,
        input: PregnancyCheckInput
    ) throws -> AnimalDetailSnapshot {
        throw missing("Field-check animal pregnancy writer")
    }
}

private struct MissingFieldCheckPastureReferenceReader: PastureReferenceDataReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureOptions() throws -> [PastureOption] {
        throw MissingFieldCheckFeatureDependencyError.dependency("Field-check pasture reference reader")
    }
}

private struct FieldCheckFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: FieldCheckFeatureDependencies {
        FieldCheckFeatureDependencies(
            overviewReader: MissingFieldCheckRepository(),
            sessionSetupRepository: MissingFieldCheckRepository(),
            sessionDetailRepository: MissingFieldCheckRepository(),
            animalDetailRepository: MissingFieldCheckRepository(),
            animalListRepository: MissingFieldCheckAnimalRepository(),
            animalRepository: MissingFieldCheckAnimalRepository(),
            pastureReferenceReader: MissingFieldCheckPastureReferenceReader()
        )
    }
}

extension EnvironmentValues {
    var fieldCheckFeatureDependencies: FieldCheckFeatureDependencies {
        get { self[FieldCheckFeatureDependenciesKey.self] }
        set { self[FieldCheckFeatureDependenciesKey.self] = newValue }
    }
}
