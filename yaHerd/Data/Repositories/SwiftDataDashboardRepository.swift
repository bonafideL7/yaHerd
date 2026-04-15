import Foundation
import SwiftData

struct SwiftDataDashboardRepository: DashboardRepository {
    let context: ModelContext

    func fetchDashboardRecords() throws -> DashboardRecords {
        let animalDescriptor = FetchDescriptor<Animal>()
        let pastureDescriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        let workingDescriptor = FetchDescriptor<WorkingSession>(sortBy: [SortDescriptor(\WorkingSession.date, order: .reverse)])

        let animals = try context.fetch(animalDescriptor).map(DashboardMapper.makeAnimalRecord)
        let pastures = try context.fetch(pastureDescriptor).map(DashboardMapper.makePastureRecord)
        let sessions = try context.fetch(workingDescriptor).map(DashboardMapper.makeWorkingSessionRecord)

        return DashboardRecords(
            animals: animals,
            pastures: pastures,
            workingSessions: sessions
        )
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )

        guard let pasture = try context.fetch(descriptor).first else { return }
        pasture.lastGrazedDate = date
        try context.save()
    }
}
