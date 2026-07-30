import Foundation
import SwiftData

@ModelActor
actor SwiftDataReadModelActor: DashboardReadModel, HomeFieldCheckReadModel, HomeWorkingReadModel, AnimalListReadModel {
    func fetchDashboardRecords(pageSize: Int) async throws -> DashboardRecords {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchDashboardRecords") {
            try makeDashboardRecords(pageSize: pageSize)
        }
    }

    func fetchDashboardSnapshot(
        configuration: DashboardConfiguration,
        now: Date,
        pageSize: Int
    ) async throws -> DashboardSnapshot {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchDashboardSnapshot") {
            DashboardService().makeSnapshot(
                records: try makeDashboardRecords(pageSize: pageSize),
                configuration: configuration,
                now: now
            )
        }
    }

    func fetchRecentSessions(limit: Int) async throws -> [FieldCheckSessionSummary] {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchRecentFieldCheckSessions") {
            var descriptor = FetchDescriptor<FieldCheckSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(limit, 1)
            return try modelContext.fetch(descriptor).map(FieldCheckMapper.makeSessionSummary)
        }
    }

    func fetchOpenFindings(limit: Int) async throws -> [FieldCheckFindingSnapshot] {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchOpenFindings") {
            let resolvedStatus = FieldCheckFindingStatus.resolved.rawValue
            var descriptor = FetchDescriptor<FieldCheckFinding>(
                predicate: #Predicate<FieldCheckFinding> { finding in
                    finding.statusRawValue != resolvedStatus
                },
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(limit, 1)
            return try modelContext.fetch(descriptor).map(FieldCheckMapper.makeFindingSnapshot)
        }
    }

    func fetchTreatmentTemplates(limit: Int) async throws -> [WorkingTreatmentTemplateSummary] {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchTreatmentTemplates") {
            var descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                sortBy: [SortDescriptor(\.name)]
            )
            descriptor.fetchLimit = max(limit, 1)
            return try modelContext.fetch(descriptor).map(WorkingMapper.makeTemplateSummary)
        }
    }

    func fetchAnimalListSnapshot(pageSize: Int) async throws -> AnimalListSnapshot {
        try PerformanceLog.measure("SwiftDataReadModelActor.fetchAnimalListSnapshot") {
            let animals = try fetchAll(
                FetchDescriptor<Animal>(
                    sortBy: [SortDescriptor(\.tagNumber), SortDescriptor(\.birthDate, order: .reverse)]
                ),
                pageSize: pageSize
            )
            let pastures = try modelContext.fetch(
                FetchDescriptor<Pasture>(
                    sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
                )
            )

            return AnimalListSnapshot(
                animals: animals.map(AnimalMapper.makeSummary),
                pastureOptions: pastures.map { PastureOption(id: $0.publicID, name: $0.name) }
            )
        }
    }

    private func makeDashboardRecords(pageSize: Int) throws -> DashboardRecords {
        let animals = try fetchAll(
            FetchDescriptor<Animal>(
                sortBy: [SortDescriptor(\.tagNumber), SortDescriptor(\.birthDate, order: .reverse)]
            ),
            pageSize: pageSize
        )
        let pastures = try modelContext.fetch(
            FetchDescriptor<Pasture>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
            )
        )
        let activeStatus = WorkingSessionStatus.active.rawValue
        var activeSessionDescriptor = FetchDescriptor<WorkingSession>(
            predicate: #Predicate<WorkingSession> { session in
                session.statusRawValue == activeStatus
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        activeSessionDescriptor.fetchLimit = 10
        let activeSessions = try modelContext.fetch(activeSessionDescriptor)

        let activeAnimalCounts = Dictionary(grouping: animals.filter(\.isActiveInHerd)) {
            $0.pasture?.publicID
        }

        return DashboardRecords(
            animals: animals.map(DashboardMapper.makeAnimalRecord),
            pastures: pastures.map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: activeAnimalCounts[pasture.publicID]?.count ?? 0
                )
            },
            workingSessions: activeSessions.map(DashboardMapper.makeWorkingSessionRecord)
        )
    }

    private func fetchAll<Model: PersistentModel>(
        _ baseDescriptor: FetchDescriptor<Model>,
        pageSize: Int
    ) throws -> [Model] {
        let resolvedPageSize = max(pageSize, 1)
        var offset = 0
        var results: [Model] = []

        while true {
            var descriptor = baseDescriptor
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = resolvedPageSize
            let page = try modelContext.fetch(descriptor)
            results.append(contentsOf: page)

            guard page.count == resolvedPageSize else { break }
            offset += page.count
        }

        return results
    }
}
