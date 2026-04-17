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

protocol FieldCheckRepository {
    func fetchPastureOptions() throws -> [PastureOption]
    func fetchSessions() throws -> [FieldCheckSessionSummary]
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot?
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot]
    @discardableResult
    func createSession(input: FieldCheckSessionStartInput) throws -> UUID
    func updateQuickCounts(sessionID: UUID, quickTaggedCount: Int, quickUntaggedCount: Int) throws
    func updateNotes(sessionID: UUID, notes: String) throws
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws
    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws
    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws
    func deleteFinding(sessionID: UUID, findingID: UUID) throws
    func completeSession(id: UUID) throws
    func reopenSession(id: UUID) throws
}
