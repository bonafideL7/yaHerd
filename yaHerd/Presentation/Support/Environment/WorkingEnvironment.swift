import Foundation
import SwiftUI

enum MissingWorkingDependencyError: LocalizedError {
    case repository(String)
    case animalSummaryReader

    var errorDescription: String? {
        switch self {
        case .repository(let name):
            return "\(name) has not been configured."
        case .animalSummaryReader:
            return "Working animal summary reader has not been configured."
        }
    }
}

private struct MissingWorkingRepository: WorkingRepository {
    private func missing(_ name: String) -> MissingWorkingDependencyError {
        .repository(name)
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        throw missing("Working sessions repository")
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        throw missing("Working session detail repository")
    }

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        throw missing("Working protocol template repository")
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
        throw missing("Working protocol template detail repository")
    }

    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        throw missing("Working queue item editor repository")
    }

    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID {
        throw missing("New working session repository")
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
        throw missing("Working collect animals repository")
    }

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws {
        throw missing("Working chute repository")
    }

    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws {
        throw missing("Working queue item editing repository")
    }

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
        throw missing("Working queue item editing repository")
    }

    func deleteSession(id: UUID) throws {
        throw missing("Working session delete repository")
    }

    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        throw missing("Working finish session repository")
    }

    func finishSession(id: UUID) throws {
        throw missing("Working finish session repository")
    }

    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID {
        throw missing("Working protocol template creator")
    }

    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {
        throw missing("Working protocol template editor repository")
    }

    func deleteTemplates(ids: [UUID]) throws {
        throw missing("Working protocol template repository")
    }
}

private struct MissingWorkingAnimalSummaryReader: AnimalSummaryReading {
    func fetchAnimals() throws -> [AnimalSummary] {
        throw MissingWorkingDependencyError.animalSummaryReader
    }
}

private struct WorkingSessionsRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingSessionsRepository = MissingWorkingRepository()
}

private struct WorkingSessionDetailRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingSessionDetailRepository = MissingWorkingRepository()
}

private struct NewWorkingSessionRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any NewWorkingSessionRepository = MissingWorkingRepository()
}

private struct WorkingCollectAnimalsRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingCollectAnimalsRepository = MissingWorkingRepository()
}

private struct WorkingQueueRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingQueueRepository = MissingWorkingRepository()
}

private struct WorkingQueueItemEditingRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingQueueItemEditingRepository = MissingWorkingRepository()
}

private struct WorkingChuteRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingChuteRepository = MissingWorkingRepository()
}

private struct WorkingFinishSessionRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingFinishSessionRepository = MissingWorkingRepository()
}

private struct WorkingProtocolTemplatesRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingProtocolTemplatesRepository = MissingWorkingRepository()
}

private struct WorkingProtocolTemplateCreatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingProtocolTemplateCreating = MissingWorkingRepository()
}

private struct WorkingProtocolTemplateEditorRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingProtocolTemplateEditorRepository = MissingWorkingRepository()
}

private struct WorkingAnimalSummaryReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalSummaryReading = MissingWorkingAnimalSummaryReader()
}

extension EnvironmentValues {
    var workingSessionsRepository: any WorkingSessionsRepository {
        get { self[WorkingSessionsRepositoryEnvironmentKey.self] }
        set { self[WorkingSessionsRepositoryEnvironmentKey.self] = newValue }
    }

    var workingSessionDetailRepository: any WorkingSessionDetailRepository {
        get { self[WorkingSessionDetailRepositoryEnvironmentKey.self] }
        set { self[WorkingSessionDetailRepositoryEnvironmentKey.self] = newValue }
    }

    var newWorkingSessionRepository: any NewWorkingSessionRepository {
        get { self[NewWorkingSessionRepositoryEnvironmentKey.self] }
        set { self[NewWorkingSessionRepositoryEnvironmentKey.self] = newValue }
    }

    var workingCollectAnimalsRepository: any WorkingCollectAnimalsRepository {
        get { self[WorkingCollectAnimalsRepositoryEnvironmentKey.self] }
        set { self[WorkingCollectAnimalsRepositoryEnvironmentKey.self] = newValue }
    }

    var workingQueueRepository: any WorkingQueueRepository {
        get { self[WorkingQueueRepositoryEnvironmentKey.self] }
        set { self[WorkingQueueRepositoryEnvironmentKey.self] = newValue }
    }

    var workingQueueItemEditingRepository: any WorkingQueueItemEditingRepository {
        get { self[WorkingQueueItemEditingRepositoryEnvironmentKey.self] }
        set { self[WorkingQueueItemEditingRepositoryEnvironmentKey.self] = newValue }
    }

    var workingChuteRepository: any WorkingChuteRepository {
        get { self[WorkingChuteRepositoryEnvironmentKey.self] }
        set { self[WorkingChuteRepositoryEnvironmentKey.self] = newValue }
    }

    var workingFinishSessionRepository: any WorkingFinishSessionRepository {
        get { self[WorkingFinishSessionRepositoryEnvironmentKey.self] }
        set { self[WorkingFinishSessionRepositoryEnvironmentKey.self] = newValue }
    }

    var workingProtocolTemplatesRepository: any WorkingProtocolTemplatesRepository {
        get { self[WorkingProtocolTemplatesRepositoryEnvironmentKey.self] }
        set { self[WorkingProtocolTemplatesRepositoryEnvironmentKey.self] = newValue }
    }

    var workingProtocolTemplateCreator: any WorkingProtocolTemplateCreating {
        get { self[WorkingProtocolTemplateCreatorEnvironmentKey.self] }
        set { self[WorkingProtocolTemplateCreatorEnvironmentKey.self] = newValue }
    }

    var workingProtocolTemplateEditorRepository: any WorkingProtocolTemplateEditorRepository {
        get { self[WorkingProtocolTemplateEditorRepositoryEnvironmentKey.self] }
        set { self[WorkingProtocolTemplateEditorRepositoryEnvironmentKey.self] = newValue }
    }

    var workingAnimalSummaryReader: any AnimalSummaryReading {
        get { self[WorkingAnimalSummaryReaderEnvironmentKey.self] }
        set { self[WorkingAnimalSummaryReaderEnvironmentKey.self] = newValue }
    }
}
