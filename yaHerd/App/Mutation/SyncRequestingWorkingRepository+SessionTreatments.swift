import Foundation

@MainActor
extension SyncRequestingWorkingRepository {
    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) throws {
        try writePolicy.validateCanWrite(reason: .working)
        try base.updateSessionTreatments(
            id: id,
            plannedTreatments: plannedTreatments
        )
        mutationRecorder.recordSuccessfulMutation(reason: .working)
    }
}
