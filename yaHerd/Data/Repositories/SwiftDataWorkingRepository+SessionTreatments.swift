import Foundation
import SwiftData

@MainActor
extension SwiftDataWorkingRepository {
    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) throws {
        try WorkingTreatmentPlanRules.validate(plannedTreatments)

        let sessionID = id
        let descriptor = FetchDescriptor<WorkingSession>(
            predicate: #Predicate { $0.publicID == sessionID }
        )
        guard let session = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.sessionNotFound
        }
        guard session.status == .active else {
            throw WorkingRepositoryError.sessionAlreadyFinished
        }

        session.protocolItems = plannedTreatments
        try PersistenceLog.save(
            context,
            operation: "SwiftDataWorkingRepository.updateSessionTreatments"
        )
    }
}
