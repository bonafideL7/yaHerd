import SwiftData

struct SwiftDataWorkingSessionCleanupWriter {
    let context: ModelContext

    func deleteLinkedRecords(session: WorkingSession) throws {
        let sid = session.persistentModelID
        for record in try context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) where record.session?.persistentModelID == sid {
            context.delete(record)
        }
        for check in try context.fetch(FetchDescriptor<PregnancyCheck>()) where check.workingSession?.persistentModelID == sid {
            context.delete(check)
        }
        for record in try context.fetch(FetchDescriptor<HealthRecord>()) where record.workingSession?.persistentModelID == sid {
            context.delete(record)
        }
    }
}
