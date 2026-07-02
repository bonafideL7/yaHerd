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
            return "This check is completed. Reopen it before making changes."
        }
    }
}

protocol FieldCheckPastureCleanupWriter {
    func deleteSessions(forPastureIDs ids: [UUID]) throws
}

protocol FieldCheckSessionListReader {
    func fetchSessions() throws -> [FieldCheckSessionSummary]
}

protocol FieldCheckOpenFindingReading {
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot]
}

protocol FieldCheckOverviewReading: FieldCheckSessionListReader, FieldCheckOpenFindingReading {}

protocol FieldCheckSessionDetailReading {
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot?
}

protocol FieldCheckSessionCreating {
    @discardableResult
    func createSession(input: FieldCheckSessionStartInput) throws -> UUID
}

protocol FieldCheckQuickCountUpdating {
    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) throws
}

protocol FieldCheckNotesUpdating {
    func updateNotes(sessionID: UUID, notes: String) throws
}

protocol FieldCheckAnimalCheckWriting {
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws
}

protocol FieldCheckTrackedAnimalAdding {
    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, checkedAt: Date) throws
}

protocol FieldCheckFindingWriting {
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws
    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws
    func deleteFinding(sessionID: UUID, findingID: UUID) throws
}

protocol FieldCheckSessionCompletionWriting {
    func completeSession(id: UUID) throws
    func reopenSession(id: UUID) throws
}

protocol FieldCheckSessionSetupRepository: FieldCheckSessionCreating {}

protocol FieldCheckSessionDetailRepository:
    FieldCheckSessionDetailReading,
    FieldCheckQuickCountUpdating,
    FieldCheckNotesUpdating,
    FieldCheckAnimalCheckWriting,
    FieldCheckTrackedAnimalAdding,
    FieldCheckFindingWriting,
    FieldCheckSessionCompletionWriting
{}

protocol FieldCheckAnimalDetailRepository:
    FieldCheckSessionDetailReading,
    FieldCheckAnimalCheckWriting,
    FieldCheckTrackedAnimalAdding,
    FieldCheckFindingWriting
{}

protocol FieldCheckRepository:
    FieldCheckPastureCleanupWriter,
    FieldCheckOverviewReading,
    FieldCheckSessionSetupRepository,
    FieldCheckSessionDetailRepository,
    FieldCheckAnimalDetailRepository
{}
