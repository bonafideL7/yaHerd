import Foundation
import SwiftUI

nonisolated struct WorkingSessionFeatureDependencies {
    let sessionDetailReadModel: any WorkingSessionDetailReadModel
    let sessionsRepository: any WorkingSessionsRepository
    let sessionDetailRepository: any WorkingSessionDetailRepository
    let newSessionRepository: any NewWorkingSessionRepository
    let collectAnimalsRepository: any WorkingCollectAnimalsRepository
    let queueRepository: any WorkingQueueRepository
    let queueItemEditingRepository: any WorkingQueueItemEditingRepository
    let chuteRepository: any WorkingChuteRepository
    let finishSessionRepository: any WorkingFinishSessionRepository
    let treatmentTemplatesRepository: any WorkingTreatmentTemplatesRepository
    let treatmentTemplateCreator: any WorkingTreatmentTemplateCreating
    let treatmentTemplateEditorRepository: any WorkingTreatmentTemplateEditorRepository
    let animalSummaryReader: any AnimalSummaryReading
    let pastureReferenceReader: any PastureReferenceDataReader

    nonisolated init(
        sessionDetailReadModel: any WorkingSessionDetailReadModel,
        sessionsRepository: any WorkingSessionsRepository,
        sessionDetailRepository: any WorkingSessionDetailRepository,
        newSessionRepository: any NewWorkingSessionRepository,
        collectAnimalsRepository: any WorkingCollectAnimalsRepository,
        queueRepository: any WorkingQueueRepository,
        queueItemEditingRepository: any WorkingQueueItemEditingRepository,
        chuteRepository: any WorkingChuteRepository,
        finishSessionRepository: any WorkingFinishSessionRepository,
        treatmentTemplatesRepository: any WorkingTreatmentTemplatesRepository,
        treatmentTemplateCreator: any WorkingTreatmentTemplateCreating,
        treatmentTemplateEditorRepository: any WorkingTreatmentTemplateEditorRepository,
        animalSummaryReader: any AnimalSummaryReading,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        self.sessionDetailReadModel = sessionDetailReadModel
        self.sessionsRepository = sessionsRepository
        self.sessionDetailRepository = sessionDetailRepository
        self.newSessionRepository = newSessionRepository
        self.collectAnimalsRepository = collectAnimalsRepository
        self.queueRepository = queueRepository
        self.queueItemEditingRepository = queueItemEditingRepository
        self.chuteRepository = chuteRepository
        self.finishSessionRepository = finishSessionRepository
        self.treatmentTemplatesRepository = treatmentTemplatesRepository
        self.treatmentTemplateCreator = treatmentTemplateCreator
        self.treatmentTemplateEditorRepository = treatmentTemplateEditorRepository
        self.animalSummaryReader = animalSummaryReader
        self.pastureReferenceReader = pastureReferenceReader
    }

    @MainActor
    init(
        repository: any WorkingRepository,
        sessionDetailReadModel: any WorkingSessionDetailReadModel,
        animalSummaryReader: any AnimalSummaryReading,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        let detailRepository = ReadModelBackedWorkingSessionDetailRepository(
            base: repository,
            workingSessionDetailReadModel: sessionDetailReadModel
        )
        self.init(
            sessionDetailReadModel: sessionDetailReadModel,
            sessionsRepository: repository,
            sessionDetailRepository: detailRepository,
            newSessionRepository: repository,
            collectAnimalsRepository: repository,
            queueRepository: repository,
            queueItemEditingRepository: repository,
            chuteRepository: repository,
            finishSessionRepository: repository,
            treatmentTemplatesRepository: repository,
            treatmentTemplateCreator: repository,
            treatmentTemplateEditorRepository: repository,
            animalSummaryReader: animalSummaryReader,
            pastureReferenceReader: pastureReferenceReader
        )
    }

    @MainActor
    static func preview(
        sessionDetailReadModel: (any WorkingSessionDetailReadModel)? = nil,
        sessionsRepository: (any WorkingSessionsRepository)? = nil,
        sessionDetailRepository: (any WorkingSessionDetailRepository)? = nil,
        newSessionRepository: (any NewWorkingSessionRepository)? = nil,
        collectAnimalsRepository: (any WorkingCollectAnimalsRepository)? = nil,
        queueRepository: (any WorkingQueueRepository)? = nil,
        queueItemEditingRepository: (any WorkingQueueItemEditingRepository)? = nil,
        chuteRepository: (any WorkingChuteRepository)? = nil,
        finishSessionRepository: (any WorkingFinishSessionRepository)? = nil,
        treatmentTemplatesRepository: (any WorkingTreatmentTemplatesRepository)? = nil,
        treatmentTemplateCreator: (any WorkingTreatmentTemplateCreating)? = nil,
        treatmentTemplateEditorRepository: (any WorkingTreatmentTemplateEditorRepository)? = nil,
        animalSummaryReader: (any AnimalSummaryReading)? = nil,
        pastureReferenceReader: (any PastureReferenceDataReader)? = nil
    ) -> Self {
        let missingRepository = MissingWorkingRepository()
        return Self(
            sessionDetailReadModel: sessionDetailReadModel ?? MissingWorkingSessionDetailReadModel(),
            sessionsRepository: sessionsRepository ?? missingRepository,
            sessionDetailRepository: sessionDetailRepository ?? missingRepository,
            newSessionRepository: newSessionRepository ?? missingRepository,
            collectAnimalsRepository: collectAnimalsRepository ?? missingRepository,
            queueRepository: queueRepository ?? missingRepository,
            queueItemEditingRepository: queueItemEditingRepository ?? missingRepository,
            chuteRepository: chuteRepository ?? missingRepository,
            finishSessionRepository: finishSessionRepository ?? missingRepository,
            treatmentTemplatesRepository: treatmentTemplatesRepository ?? missingRepository,
            treatmentTemplateCreator: treatmentTemplateCreator ?? missingRepository,
            treatmentTemplateEditorRepository: treatmentTemplateEditorRepository ?? missingRepository,
            animalSummaryReader: animalSummaryReader ?? MissingWorkingAnimalSummaryReader(),
            pastureReferenceReader: pastureReferenceReader ?? MissingWorkingPastureReferenceReader()
        )
    }
}

private enum MissingWorkingSessionFeatureDependencyError: LocalizedError {
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .dependency(let name):
            return "\(name) has not been configured."
        }
    }
}

private struct MissingWorkingSessionDetailReadModel: WorkingSessionDetailReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchSessionDetail(id: UUID) async throws -> WorkingSessionDetailSnapshot? {
        throw MissingWorkingSessionFeatureDependencyError.dependency("Working session detail read model")
    }
}

private struct MissingWorkingRepository: WorkingRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingWorkingSessionFeatureDependencyError {
        .dependency(name)
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        throw missing("Working sessions repository")
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        throw missing("Working session detail repository")
    }

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        throw missing("Working treatment template repository")
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        throw missing("Working treatment template detail repository")
    }

    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        throw missing("Working session animal editor repository")
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
        throw missing("Working animal collector")
    }

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws {
        throw missing("Working animal repository")
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) throws {
        throw missing("Working session animal editor")
    }

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
        throw missing("Working session animal editor")
    }

    func deleteSession(id: UUID) throws {
        throw missing("Working session deleter")
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) throws {
        throw missing("Working session completion repository")
    }

    func createTemplate(name: String, items: [WorkingTreatmentPlanItem]) throws -> UUID {
        throw missing("Working treatment template creator")
    }

    func updateTemplate(id: UUID, name: String, items: [WorkingTreatmentPlanItem]) throws {
        throw missing("Working treatment template editor")
    }

    func deleteTemplates(ids: [UUID]) throws {
        throw missing("Working treatment template deleter")
    }
}

private struct MissingWorkingAnimalSummaryReader: AnimalSummaryReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchAnimals() throws -> [AnimalSummary] {
        throw MissingWorkingSessionFeatureDependencyError.dependency("Working animal summary reader")
    }
}

private struct MissingWorkingPastureReferenceReader: PastureReferenceDataReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureOptions() throws -> [PastureOption] {
        throw MissingWorkingSessionFeatureDependencyError.dependency("Working pasture reference reader")
    }
}

private struct WorkingSessionFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: WorkingSessionFeatureDependencies {
        WorkingSessionFeatureDependencies(
            sessionDetailReadModel: MissingWorkingSessionDetailReadModel(),
            sessionsRepository: MissingWorkingRepository(),
            sessionDetailRepository: MissingWorkingRepository(),
            newSessionRepository: MissingWorkingRepository(),
            collectAnimalsRepository: MissingWorkingRepository(),
            queueRepository: MissingWorkingRepository(),
            queueItemEditingRepository: MissingWorkingRepository(),
            chuteRepository: MissingWorkingRepository(),
            finishSessionRepository: MissingWorkingRepository(),
            treatmentTemplatesRepository: MissingWorkingRepository(),
            treatmentTemplateCreator: MissingWorkingRepository(),
            treatmentTemplateEditorRepository: MissingWorkingRepository(),
            animalSummaryReader: MissingWorkingAnimalSummaryReader(),
            pastureReferenceReader: MissingWorkingPastureReferenceReader()
        )
    }
}

extension EnvironmentValues {
    var workingSessionFeatureDependencies: WorkingSessionFeatureDependencies {
        get { self[WorkingSessionFeatureDependenciesKey.self] }
        set { self[WorkingSessionFeatureDependenciesKey.self] = newValue }
    }
}
