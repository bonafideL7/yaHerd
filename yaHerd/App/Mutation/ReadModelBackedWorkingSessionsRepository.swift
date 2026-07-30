import Foundation

@MainActor
struct ReadModelBackedWorkingSessionsRepository:
    WorkingSessionsRepository,
    WorkingSessionListReadModelProviding
{
    let base: any WorkingSessionsRepository
    let workingSessionListReadModel: any WorkingSessionListReadModel

    func fetchSessions() throws -> [WorkingSessionSummary] {
        try base.fetchSessions()
    }

    func deleteSession(id: UUID) throws {
        try base.deleteSession(id: id)
    }
}
