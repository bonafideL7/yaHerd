import Foundation

enum FieldCheckRepositoryError: LocalizedError {
    case sessionNotFound
    case animalCheckNotFound
    case findingNotFound
    case pastureNotFound

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
    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws
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
    FieldCheckFindingWriting,
    FieldCheckSessionCompletionWriting
{}

protocol FieldCheckAnimalDetailRepository:
    FieldCheckSessionDetailReading,
    FieldCheckAnimalCheckWriting,
    FieldCheckFindingWriting
{}

protocol FieldCheckRepository:
    FieldCheckPastureCleanupWriter,
    FieldCheckOverviewReading,
    FieldCheckSessionSetupRepository,
    FieldCheckSessionDetailRepository,
    FieldCheckAnimalDetailRepository
{}
