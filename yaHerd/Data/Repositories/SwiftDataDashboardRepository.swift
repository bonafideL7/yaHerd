import Foundation
import SwiftData

struct SwiftDataDashboardRepository: DashboardRepository {
    let context: ModelContext

    func fetchDashboardRecords() throws -> DashboardRecords {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardRecords") {
            // Keep these fetches intentionally simple. SwiftData can compile some enum predicates,
            // but they can still fail at runtime with SwiftDataError error 1 on existing stores.
            // Filter enum-backed values in Swift until these model fields are stored as raw strings.
            let animalDescriptor = FetchDescriptor<Animal>()
            let pastureDescriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
            let workingDescriptor = FetchDescriptor<WorkingSession>(
                sortBy: [SortDescriptor(\WorkingSession.date, order: .reverse)]
            )

            let animalModels = try context.fetch(animalDescriptor)
            let visibleAnimalModels = animalModels.filter { !$0.isSoftDeleted }
            let pastureActiveAnimalCounts = activeAnimalCountsByPastureID(from: visibleAnimalModels)
            let animals = visibleAnimalModels.map(DashboardMapper.makeAnimalRecord)
            let pastures = try context.fetch(pastureDescriptor).map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: pastureActiveAnimalCounts[pasture.publicID, default: 0]
                )
            }
            let sessions = try context.fetch(workingDescriptor)
                .filter { $0.status == .active }
                .map(DashboardMapper.makeWorkingSessionRecord)

            return DashboardRecords(
                animals: animals,
                pastures: pastures,
                workingSessions: sessions
            )
        }
    }

    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) throws -> [DashboardAnimalRecord] {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardAnimalRecords.\(kind.rawValue)") {
            let descriptor = FetchDescriptor<Animal>()
            let animals = try context.fetch(descriptor).filter { animal in
                switch kind {
                case .active:
                    return animal.isActiveInHerd
                case .workingPen:
                    return animal.isActiveInHerd && animal.location == .workingPen
                case .unassigned:
                    return animal.isActiveInHerd && animal.location == .pasture && animal.pasture == nil
                }
            }
            return animals.map(DashboardMapper.makeAnimalRecord)
        }
    }

    func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord] {
        try PerformanceLog.measure("SwiftDataDashboardRepository.fetchDashboardPastureRecords") {
            let animalDescriptor = FetchDescriptor<Animal>()
            let pastureActiveAnimalCounts = activeAnimalCountsByPastureID(
                from: try context.fetch(animalDescriptor).filter { !$0.isSoftDeleted }
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
            try PersistenceLog.save(context, operation: "SwiftDataDashboardRepository")
        }
    }
    private func activeAnimalCountsByPastureID(from animals: [Animal]) -> [UUID: Int] {
        animals.reduce(into: [UUID: Int]()) { counts, animal in
            guard animal.isActiveInHerd, let pastureID = animal.pasture?.publicID else { return }
            counts[pastureID, default: 0] += 1
        }
    }

}
