import Foundation

struct EmptyFieldCheckRepository: FieldCheckRepository {
    func fetchSessions() throws -> [FieldCheckSessionSummary] { [] }
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? { nil }
    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] { [] }
    func createSession(input: FieldCheckSessionStartInput) async throws -> UUID { UUID() }
    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) async throws {}
    func updateNotes(sessionID: UUID, notes: String) async throws {}
    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) async throws {}
    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) async throws {}
    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, checkedAt: Date) async throws {}
    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) async throws {}
    func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput) async throws {}
    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) async throws {}
    func deleteFinding(sessionID: UUID, findingID: UUID) async throws {}
    func completeSession(id: UUID) async throws {}
    func reopenSession(id: UUID) async throws {}
    func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) async throws {}
}
