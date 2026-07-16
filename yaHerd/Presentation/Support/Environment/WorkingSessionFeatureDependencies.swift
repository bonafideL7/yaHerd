import Foundation
import SwiftUI

nonisolated struct WorkingSessionFeatureDependencies {
    let sessionsRepository: any WorkingSessionsRepository
    let sessionDetailRepository: any WorkingSessionDetailRepository
    let newSessionRepository: any NewWorkingSessionRepository
    let collectAnimalsRepository: any WorkingCollectAnimalsRepository
    let queueRepository: any WorkingQueueRepository
    let queueItemEditingRepository: any WorkingQueueItemEditingRepository
    let chuteRepository: any WorkingChuteRepository
    let finishSessionRepository: any WorkingFinishSessionRepository
    let protocolTemplatesRepository: any WorkingProtocolTemplatesRepository
    let protocolTemplateCreator: any WorkingProtocolTemplateCreating
    let protocolTemplateEditorRepository: any WorkingProtocolTemplateEditorRepository
    let animalSummaryReader: any AnimalSummaryReading
    let pastureReferenceReader: any PastureReferenceDataReader

    nonisolated init(
        sessionsRepository: any WorkingSessionsRepository,
        sessionDetailRepository: any WorkingSessionDetailRepository,
        newSessionRepository: any NewWorkingSessionRepository,
        collectAnimalsRepository: any WorkingCollectAnimalsRepository,
        queueRepository: any WorkingQueueRepository,
        queueItemEditingRepository: any WorkingQueueItemEditingRepository,
        chuteRepository: any WorkingChuteRepository,
        finishSessionRepository: any WorkingFinishSessionRepository,
        protocolTemplatesRepository: any WorkingProtocolTemplatesRepository,
        protocolTemplateCreator: any WorkingProtocolTemplateCreating,
        protocolTemplateEditorRepository: any WorkingProtocolTemplateEditorRepository,
        animalSummaryReader: any AnimalSummaryReading,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        self.sessionsRepository = sessionsRepository
        self.sessionDetailRepository = sessionDetailRepository
        self.newSessionRepository = newSessionRepository
        self.collectAnimalsRepository = collectAnimalsRepository
        self.queueRepository = queueRepository
        self.queueItemEditingRepository = queueItemEditingRepository
        self.chuteRepository = chuteRepository
        self.finishSessionRepository = finishSessionRepository
        self.protocolTemplatesRepository = protocolTemplatesRepository
        self.protocolTemplateCreator = protocolTemplateCreator
        self.protocolTemplateEditorRepository = protocolTemplateEditorRepository
        self.animalSummaryReader = animalSummaryReader
        self.pastureReferenceReader = pastureReferenceReader
    }

    @MainActor
    init(
        repository: any WorkingRepository,
        animalSummaryReader: any AnimalSummaryReading,
        pastureReferenceReader: any PastureReferenceDataReader
    ) {
        self.init(
            sessionsRepository: repository,
            sessionDetailRepository: repository,
            newSessionRepository: repository,
            collectAnimalsRepository: repository,
            queueRepository: repository,
            queueItemEditingRepository: repository,
            chuteRepository: repository,
            finishSessionRepository: repository,
            protocolTemplatesRepository: repository,
            protocolTemplateCreator: repository,
            protocolTemplateEditorRepository: repository,
            animalSummaryReader: animalSummaryReader,
            pastureReferenceReader: pastureReferenceReader
        )
    }

    @MainActor
    static func preview(
        sessionsRepository: (any WorkingSessionsRepository)? = nil,
        sessionDetailRepository: (any WorkingSessionDetailRepository)? = nil,
        newSessionRepository: (any NewWorkingSessionRepository)? = nil,
        collectAnimalsRepository: (any WorkingCollectAnimalsRepository)? = nil,
        queueRepository: (any WorkingQueueRepository)? = nil,
        queueItemEditingRepository: (any WorkingQueueItemEditingRepository)? = nil,
        chuteRepository: (any WorkingChuteRepository)? = nil,
        finishSessionRepository: (any WorkingFinishSessionRepository)? = nil,
        protocolTemplatesRepository: (any WorkingProtocolTemplatesRepository)? = nil,
        protocolTemplateCreator: (any WorkingProtocolTemplateCreating)? = nil,
        protocolTemplateEditorRepository: (any WorkingProtocolTemplateEditorRepository)? = nil,
        animalSummaryReader: (any AnimalSummaryReading)? = nil,
        pastureReferenceReader: (any PastureReferenceDataReader)? = nil
    ) -> Self {
        let missingRepository = MissingWorkingRepository()
        return Self(
            sessionsRepository: sessionsRepository ?? missingRepository,
            sessionDetailRepository: sessionDetailRepository ?? missingRepository,
            newSessionRepository: newSessionRepository ?? missingRepository,
            collectAnimalsRepository: collectAnimalsRepository ?? missingRepository,
            queueRepository: queueRepository ?? missingRepository,
            queueItemEditingRepository: queueItemEditingRepository ?? missingRepository,
            chuteRepository: chuteRepository ?? missingRepository,
            finishSessionRepository: finishSessionRepository ?? missingRepository,
            protocolTemplatesRepository: protocolTemplatesRepository ?? missingRepository,
            protocolTemplateCreator: protocolTemplateCreator ?? missingRepository,
            protocolTemplateEditorRepository: protocolTemplateEditorRepository ?? missingRepository,
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

private struct MissingWorkingRepository: WorkingRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingWorkingSessionFeatureDependencyError {
        .dependency(name)
    }

    func fetchSessions() throws -> [WorkingSessionSummary] { throw missing("Working sessions repository") }
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? { throw missing("Working session detail repository") }
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] { throw missing("Working protocol template repository") }
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
        throw missing("Working protocol template detail repository")
    }
    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        throw missing("Working queue item editor repository")
    }
    func createSession(
        date: Date,
        sourcePastureID: UUID?,
        protocolName: String,
        protocolItems: [WorkingProtocolItem]
    ) throws -> UUID {
        throw missing("Working session creator")
    }
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws { throw missing("Working animal collector") }
    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws { throw missing("Working chute repository") }
    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) throws {
        throw missing("Working queue item editor")
    }
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws { throw missing("Working queue item editor") }
    func deleteSession(id: UUID) throws { throw missing("Working session deleter") }
    func completeSession(id: UUID, assignments: [WorkingQueueDestinationAssignment]) throws { throw missing("Working session completion repository") }
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID { throw missing("Working protocol template creator") }
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws { throw missing("Working protocol template editor") }
    func deleteTemplates(ids: [UUID]) throws { throw missing("Working protocol template deleter") }
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
            sessionsRepository: MissingWorkingRepository(),
            sessionDetailRepository: MissingWorkingRepository(),
            newSessionRepository: MissingWorkingRepository(),
            collectAnimalsRepository: MissingWorkingRepository(),
            queueRepository: MissingWorkingRepository(),
            queueItemEditingRepository: MissingWorkingRepository(),
            chuteRepository: MissingWorkingRepository(),
            finishSessionRepository: MissingWorkingRepository(),
            protocolTemplatesRepository: MissingWorkingRepository(),
            protocolTemplateCreator: MissingWorkingRepository(),
            protocolTemplateEditorRepository: MissingWorkingRepository(),
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
