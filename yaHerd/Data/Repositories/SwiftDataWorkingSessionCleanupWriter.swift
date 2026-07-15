import Foundation
import SwiftData

@MainActor
struct SwiftDataWorkingSessionCleanupWriter {
    let context: ModelContext

    func deleteLinkedRecords(session: WorkingSession) throws {
        let sessionID = session.publicID

        let treatmentDescriptor = FetchDescriptor<WorkingTreatmentRecord>(
            predicate: #Predicate<WorkingTreatmentRecord> { record in
                record.session?.publicID == sessionID
            }
        )
        for record in try context.fetch(treatmentDescriptor) {
            context.delete(record)
        }

        let pregnancyDescriptor = FetchDescriptor<PregnancyCheck>(
            predicate: #Predicate<PregnancyCheck> { check in
                check.workingSession?.publicID == sessionID
            }
        )
        for check in try context.fetch(pregnancyDescriptor) {
            context.delete(check)
        }

        let healthDescriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate<HealthRecord> { record in
                record.workingSession?.publicID == sessionID
            }
        )
        for record in try context.fetch(healthDescriptor) {
            context.delete(record)
        }
    }
}
