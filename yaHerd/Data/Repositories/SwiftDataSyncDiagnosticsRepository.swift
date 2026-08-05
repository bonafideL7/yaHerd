//
//  SwiftDataSyncDiagnosticsRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataSyncDiagnosticsRepository: SyncDiagnosticsRepository {
    let publicIDRepairService: any PublicIDRepairService

    private let context: ModelContext

    init(
        context: ModelContext,
        publicIDRepairService: any PublicIDRepairService
    ) {
        self.context = context
        self.publicIDRepairService = publicIDRepairService
    }

    func fetchCounts() throws -> SyncDiagnosticsCounts {
        SyncDiagnosticsCounts(
            herds: try count(Herd.self),
            animals: try count(Animal.self),
            pastures: try count(Pasture.self),
            pastureGroups: try count(PastureGroup.self),
            healthRecords: try count(HealthRecord.self),
            pregnancyChecks: try count(PregnancyCheck.self),
            movementRecords: try count(MovementRecord.self),
            statusRecords: try count(StatusRecord.self),
            workingSessions: try count(WorkingSession.self),
            workingQueueItems: try count(WorkingQueueItem.self),
            workingTreatmentRecords: try count(WorkingTreatmentRecord.self),
            fieldCheckSessions: try count(FieldCheckSession.self),
            fieldCheckAnimalChecks: try count(FieldCheckAnimalCheck.self),
            fieldCheckFindings: try count(FieldCheckFinding.self)
        )
    }

    private func count<T: PersistentModel>(_ modelType: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}
