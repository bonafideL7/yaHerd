import Foundation
import SwiftData

struct SwiftDataDashboardRepository: DashboardRepository {
    let context: ModelContext

    func fetchDashboardRecords() throws -> DashboardRecords {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardRecords") {
            let animalDescriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    !animal.isSoftDeleted
                }
            )
            let pastureDescriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
            let workingDescriptor = FetchDescriptor<WorkingSession>(
                predicate: #Predicate<WorkingSession> { session in
                    session.status == WorkingSessionStatus.active
                },
                sortBy: [SortDescriptor(\WorkingSession.date, order: .reverse)]
            )

            let animalModels = try context.fetch(animalDescriptor)
            let pastureActiveAnimalCounts = activeAnimalCountsByPastureID(from: animalModels)
            let animals = animalModels.map(DashboardMapper.makeAnimalRecord)
            let pastures = try context.fetch(pastureDescriptor).map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: pastureActiveAnimalCounts[pasture.publicID, default: 0]
                )
            }
            let sessions = try context.fetch(workingDescriptor).map(DashboardMapper.makeWorkingSessionRecord)

            return DashboardRecords(
                animals: animals,
                pastures: pastures,
                workingSessions: sessions
            )
        }
    }

    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) throws -> [DashboardAnimalRecord] {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardAnimalRecords.\(kind.rawValue)") {
            let descriptor: FetchDescriptor<Animal>
            switch kind {
            case .active:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        animal.status == AnimalStatus.active && !animal.isSoftDeleted
                    }
                )
            case .workingPen:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        animal.status == AnimalStatus.active
                            && !animal.isSoftDeleted
                            && animal.locationRaw == AnimalLocation.workingPen
                    }
                )
            case .unassigned:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        animal.status == AnimalStatus.active
                            && !animal.isSoftDeleted
                            && animal.locationRaw == AnimalLocation.pasture
                            && animal.pasture == nil
                    }
                )
            }

            return try context.fetch(descriptor).map(DashboardMapper.makeAnimalRecord)
        }
    }

    func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord] {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardPastureRecords") {
            let activeAnimalDescriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    animal.status == AnimalStatus.active && !animal.isSoftDeleted
                }
            )
            let pastureActiveAnimalCounts = activeAnimalCountsByPastureID(
                from: try context.fetch(activeAnimalDescriptor)
            )
            let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
            return try context.fetch(descriptor).map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: pastureActiveAnimalCounts[pasture.publicID, default: 0]
                )
            }
        }
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        try PerformanceLog.measure("SwiftDataDashboardRepository.markPastureGrazedToday") {
            var descriptor = FetchDescriptor<Pasture>(
                predicate: #Predicate<Pasture> { pasture in
                    pasture.publicID == id
                }
            )
            descriptor.fetchLimit = 1

            guard let pasture = try context.fetch(descriptor).first else { return }
            pasture.lastGrazedDate = date
            try context.save()
        }
    }
    private func activeAnimalCountsByPastureID(from animals: [Animal]) -> [UUID: Int] {
        animals.reduce(into: [UUID: Int]()) { counts, animal in
            guard animal.isActiveInHerd, let pastureID = animal.pasture?.publicID else { return }
            counts[pastureID, default: 0] += 1
        }
    }

}
