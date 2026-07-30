import Foundation

@MainActor
struct ReadModelBackedFieldCheckOverviewRepository:
    FieldCheckOverviewReading,
    FieldCheckOverviewReadModelProviding
{
    let base: any FieldCheckOverviewReading
    let fieldCheckOverviewReadModel: any HomeFieldCheckReadModel

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        try base.fetchSessions()
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        try base.fetchOpenFindings(limit: limit)
    }
}
