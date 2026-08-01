import Foundation
import SwiftData

@ModelActor
actor SwiftDataReadModelActor:
    DashboardQueryReading,
    HomeFieldCheckQueryReading,
    HomeWorkingQueryReading,
    AnimalListQueryReading
{
    func fetchDashboardRecords() throws -> DashboardRecords {
        try PerformanceLog.measure("ReadModel.dashboard.records") {
            let animalDescriptor = FetchDescriptor<Animal>(
                sortBy: [
                    SortDescriptor(\Animal.tagNumber),
                    SortDescriptor(\Animal.name)
                ]
            )
            let activeAnimalDescriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    !animal.isSoftDeleted && animal.statusRawValue == "active"
                }
            )
            let pastureDescriptor = FetchDescriptor<Pasture>(
                sortBy: [SortDescriptor(\Pasture.name)]
            )
            var workingDescriptor = FetchDescriptor<WorkingSession>(
                predicate: #Predicate<WorkingSession> { session in
                    session.statusRawValue == "active"
                },
                sortBy: [SortDescriptor(\WorkingSession.date, order: .reverse)]
            )
            workingDescriptor.fetchLimit = 25

            let animalModels = try modelContext.fetch(animalDescriptor)
            let activeAnimalCounts = activeAnimalCountsByPastureID(
                from: try modelContext.fetch(activeAnimalDescriptor)
            )
            let animals = animalModels.map(DashboardMapper.makeAnimalRecord)
            let pastures = try modelContext.fetch(pastureDescriptor).map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: activeAnimalCounts[pasture.publicID, default: 0]
                )
            }
            let sessions = try modelContext.fetch(workingDescriptor)
                .map(DashboardMapper.makeWorkingSessionRecord)

            return DashboardRecords(
                animals: animals,
                pastures: pastures,
                workingSessions: sessions
            )
        }
    }

    func fetchDashboardAnimalRecords(
        kind: DashboardAnimalListKind
    ) throws -> [DashboardAnimalRecord] {
        try PerformanceLog.measure("ReadModel.dashboard.animals.\(kind.rawValue)") {
            let descriptor: FetchDescriptor<Animal>

            switch kind {
            case .active:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        !animal.isSoftDeleted && animal.statusRawValue == "active"
                    },
                    sortBy: [SortDescriptor(\Animal.tagNumber)]
                )
            case .workingPen:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        !animal.isSoftDeleted
                            && animal.statusRawValue == "active"
                            && animal.locationRawValue == "workingPen"
                    },
                    sortBy: [SortDescriptor(\Animal.tagNumber)]
                )
            case .unassigned:
                descriptor = FetchDescriptor<Animal>(
                    predicate: #Predicate<Animal> { animal in
                        !animal.isSoftDeleted
                            && animal.statusRawValue == "active"
                            && animal.locationRawValue == "pasture"
                            && animal.pasture == nil
                    },
                    sortBy: [SortDescriptor(\Animal.tagNumber)]
                )
            }

            return try modelContext.fetch(descriptor)
                .map(DashboardMapper.makeAnimalRecord)
        }
    }

    func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord] {
        try PerformanceLog.measure("ReadModel.dashboard.pastures") {
            let activeAnimalDescriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    !animal.isSoftDeleted && animal.statusRawValue == "active"
                }
            )
            let counts = activeAnimalCountsByPastureID(
                from: try modelContext.fetch(activeAnimalDescriptor)
            )
            let descriptor = FetchDescriptor<Pasture>(
                sortBy: [SortDescriptor(\Pasture.name)]
            )

            return try modelContext.fetch(descriptor).map { pasture in
                DashboardMapper.makePastureRecord(
                    from: pasture,
                    activeAnimalCount: counts[pasture.publicID, default: 0]
                )
            }
        }
    }

    func fetchHomeFieldCheckRecords() throws -> HomeFieldCheckRecords {
        try PerformanceLog.measure("ReadModel.home.fieldChecks") {
            let unfinishedSessionDescriptor = FetchDescriptor<FieldCheckSession>(
                predicate: #Predicate<FieldCheckSession> { session in
                    session.completedAt == nil
                },
                sortBy: [SortDescriptor(\FieldCheckSession.startedAt, order: .reverse)]
            )
            let missingCheckDescriptor = FetchDescriptor<FieldCheckAnimalCheck>(
                predicate: #Predicate<FieldCheckAnimalCheck> { check in
                    check.missingConfirmedAt != nil
                }
            )
            let openFindingDescriptor = FetchDescriptor<FieldCheckFinding>(
                predicate: #Predicate<FieldCheckFinding> { finding in
                    finding.statusRawValue != "resolved"
                },
                sortBy: [SortDescriptor(\FieldCheckFinding.recordedAt, order: .reverse)]
            )

            let unfinishedSessions = try modelContext.fetch(unfinishedSessionDescriptor)
            let missingChecks = try modelContext.fetch(missingCheckDescriptor)
            let openFindingModels = try modelContext.fetch(openFindingDescriptor)

            var warningSessionsByID: [UUID: FieldCheckSession] = [:]
            warningSessionsByID.reserveCapacity(
                unfinishedSessions.count + missingChecks.count + openFindingModels.count
            )

            for session in unfinishedSessions {
                warningSessionsByID[session.publicID] = session
            }
            for check in missingChecks {
                guard let session = check.session else { continue }
                warningSessionsByID[session.publicID] = session
            }
            for finding in openFindingModels {
                guard let session = finding.session else { continue }
                warningSessionsByID[session.publicID] = session
            }

            let warningSessions = warningSessionsByID.values
                .map(FieldCheckMapper.makeSessionSummary)
                .sorted { $0.startedAt > $1.startedAt }
            let singleOpenFinding = openFindingModels.count == 1
                ? openFindingModels.first.map(FieldCheckMapper.makeFindingSnapshot)
                : nil
            let hasHistory = try modelContext.fetchCount(
                FetchDescriptor<FieldCheckSession>()
            ) > 0

            return HomeFieldCheckRecords(
                sessions: warningSessions,
                openFindings: singleOpenFinding.map { [$0] } ?? [],
                openFindingCount: openFindingModels.count,
                hasHistory: hasHistory
            )
        }
    }

    func fetchHomeTreatmentTemplates(
        limit: Int
    ) throws -> [WorkingTreatmentTemplateSummary] {
        try PerformanceLog.measure("ReadModel.home.treatmentTemplates") {
            var descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                sortBy: [SortDescriptor(\WorkingProtocolTemplate.name)]
            )
            descriptor.fetchLimit = normalizedLimit(limit)
            return try modelContext.fetch(descriptor)
                .map(WorkingMapper.makeTemplateSummary)
        }
    }

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) throws -> AnimalSummaryPage {
        try PerformanceLog.measure(
            "ReadModel.animals.page.offset\(request.offset).limit\(request.limit)"
        ) {
            var descriptor = FetchDescriptor<Animal>(
                sortBy: [
                    SortDescriptor(\Animal.tagNumber),
                    SortDescriptor(\Animal.name),
                    SortDescriptor(\Animal.publicID)
                ]
            )
            descriptor.fetchOffset = request.offset
            descriptor.fetchLimit = request.limit + 1

            let models = try modelContext.fetch(descriptor)
            let hasMore = models.count > request.limit
            return AnimalSummaryPage(
                animals: models.prefix(request.limit).map(AnimalMapper.makeSummary),
                hasMore: hasMore
            )
        }
    }

    func fetchAnimalPastureOptions(limit: Int) throws -> [PastureOption] {
        try PerformanceLog.measure("ReadModel.animals.pastureOptions") {
            let pageSize = normalizedLimit(limit)
            var offset = 0
            var options: [PastureOption] = []

            while true {
                try Task.checkCancellation()

                var descriptor = FetchDescriptor<Pasture>(
                    sortBy: [
                        SortDescriptor(\Pasture.name),
                        SortDescriptor(\Pasture.sortOrder),
                        SortDescriptor(\Pasture.publicID)
                    ]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = pageSize

                let models = try modelContext.fetch(descriptor)
                options.append(contentsOf: models.map {
                    PastureOption(id: $0.publicID, name: $0.name)
                })

                guard models.count == pageSize else { return options }
                offset += models.count
            }
        }
    }

    private func activeAnimalCountsByPastureID(from animals: [Animal]) -> [UUID: Int] {
        animals.reduce(into: [UUID: Int]()) { counts, animal in
            guard let pastureID = animal.pasture?.publicID else { return }
            counts[pastureID, default: 0] += 1
        }
    }

    private func normalizedLimit(_ requestedLimit: Int) -> Int {
        min(max(requestedLimit, 1), ReadPageRequest.maximumLimit)
    }
}
