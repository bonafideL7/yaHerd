import Foundation
import SwiftData

extension SwiftDataPastureRepository {
    func fetchAssignedAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try PerformanceLog.measure("SwiftDataPastureRepository.fetchAssignedAnimals") {
            let descriptor = FetchDescriptor<Animal>()
            return try context.fetch(descriptor)
                .filter { animal in
                    animal.pasture?.publicID == pastureID
                }
                .map(AnimalMapper.makeSummary)
                .sorted { lhs, rhs in
                    lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
                }
        }
    }
}
