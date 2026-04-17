import Foundation

struct EmptyFieldCheckRepository: FieldCheckRepository {
    func fetchPastureOptions() throws -> [PastureOption] { [] }
    func fetchSessions() throws -> [FieldCheckSessionSummary] { [] }
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? { nil }
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] { [] }
    func createSession(input: FieldCheckSessionStartInput) throws -> UUID { UUID() }
    func updateQuickCounts(sessionID: UUID, quickTaggedCount: Int, quickUntaggedCount: Int) throws {}
    func updateNotes(sessionID: UUID, notes: String) throws {}
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {}
    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws {}
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {}
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {}
    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {}
    func deleteFinding(sessionID: UUID, findingID: UUID) throws {}
    func addNewborn(sessionID: UUID, input: FieldCheckNewbornInput) throws {}
    func deleteNewborn(sessionID: UUID, newbornID: UUID) throws {}
    func convertNewbornToAnimal(sessionID: UUID, newbornID: UUID) throws -> UUID { UUID() }
    func completeSession(id: UUID) throws {}
    func reopenSession(id: UUID) throws {}
}
