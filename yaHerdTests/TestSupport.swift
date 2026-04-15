import Foundation
import SwiftData
@testable import yaHerd

enum TestSupport {
    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Animal.self,
            AnimalTag.self,
            AnimalStatusReference.self,
            Pasture.self,
            PastureGroup.self,
            HealthRecord.self,
            PregnancyCheck.self,
            MovementRecord.self,
            StatusRecord.self,
            WorkingSession.self,
            WorkingQueueItem.self,
            WorkingTreatmentRecord.self,
            WorkingProtocolTemplate.self,
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
