import Foundation

enum FieldCheckRepositoryError: LocalizedError {
    case sessionNotFound
    case animalCheckNotFound
    case findingNotFound
    case pastureNotFound
    case animalNotFound
    case animalNotActive
    case sessionCompleted

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "The check session could not be found."
        case .animalCheckNotFound:
            return "The roster entry could not be found."
        case .findingNotFound:
            return "The finding could not be found."
        case .pastureNotFound:
            return "The pasture could not be found."
        case .animalNotFound:
            return "The animal could not be found."
        case .animalNotActive:
            return "Only active herd animals can be added to a pasture check."
        case .sessionCompleted:
            return "This check is completed. Reopen it before editing counts, roster, notes, or adding/removing findings."
        }
    }
}

@MainActor
protocol FieldCheckPastureArchiveWriter {
    func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) async throws
}

@MainActor
protocol FieldCheckSessionListReader {
    func fetchSessions() throws -> [FieldCheckSessionSummary]
}

@MainActor
protocol FieldCheckOpenFindingReading {
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot]
}

@MainActor
protocol FieldCheckOverviewReading: FieldCheckSessionListReader, FieldCheckOpenFindingReading {}

@MainActor
protocol FieldCheckSessionDetailReading {
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot?
}

@MainActor
protocol FieldCheckSessionCreating {
    @discardableResult
    func createSession(input: FieldCheckSessionStartInput) async throws -> UUID
}

@MainActor
protocol FieldCheckQuickCountUpdating {
    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) async throws
}

@MainActor
protocol FieldCheckNotesUpdating {
    func updateNotes(sessionID: UUID, notes: String) async throws
}

@MainActor
protocol FieldCheckAnimalCheckWriting {
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) async throws
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) async throws
}

@MainActor
protocol FieldCheckTrackedAnimalAdding {
    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, checkedAt: Date) async throws
}

@MainActor
protocol FieldCheckFindingWriting {
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) async throws
    func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput) async throws
    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) async throws
    func deleteFinding(sessionID: UUID, findingID: UUID) async throws
}

@MainActor
protocol FieldCheckSessionCompletionWriting {
    func completeSession(id: UUID) async throws
    func reopenSession(id: UUID) async throws
}

@MainActor
protocol FieldCheckSessionSetupRepository: FieldCheckSessionCreating {}

@MainActor
protocol FieldCheckSessionDetailRepository:
    FieldCheckSessionDetailReading,
    FieldCheckQuickCountUpdating,
    FieldCheckNotesUpdating,
    FieldCheckAnimalCheckWriting,
    FieldCheckTrackedAnimalAdding,
    FieldCheckFindingWriting,
    FieldCheckSessionCompletionWriting
{}

@MainActor
protocol FieldCheckAnimalDetailRepository:
    FieldCheckSessionDetailReading,
    FieldCheckAnimalCheckWriting,
    FieldCheckTrackedAnimalAdding,
    FieldCheckFindingWriting
{}

@MainActor
protocol FieldCheckRepository:
    FieldCheckPastureArchiveWriter,
    FieldCheckOverviewReading,
    FieldCheckSessionSetupRepository,
    FieldCheckSessionDetailRepository,
    FieldCheckAnimalDetailRepository
{}
