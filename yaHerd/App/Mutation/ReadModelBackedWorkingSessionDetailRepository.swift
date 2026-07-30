import Foundation

@MainActor
struct ReadModelBackedWorkingSessionDetailRepository:
    WorkingSessionDetailRepository,
    WorkingSessionDetailReadModelProviding
{
    let base: any WorkingSessionDetailRepository
    let workingSessionDetailReadModel: any WorkingSessionDetailReadModel

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        try base.fetchSessionDetail(id: id)
    }

    func deleteSession(id: UUID) throws {
        try base.deleteSession(id: id)
    }

    func reopenSession(id: UUID) throws {
        try base.reopenSession(id: id)
    }

    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) throws {
        try base.updateSessionTreatments(
            id: id,
            plannedTreatments: plannedTreatments
        )
    }
}
