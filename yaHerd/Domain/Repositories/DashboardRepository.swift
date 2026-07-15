import Foundation

@MainActor
protocol DashboardRecordReading {
    func fetchDashboardRecords() throws -> DashboardRecords
    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) throws -> [DashboardAnimalRecord]
    func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord]
}

extension DashboardRecordReading {
    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) throws -> [DashboardAnimalRecord] {
        let records = try fetchDashboardRecords()
        switch kind {
        case .active:
            return records.animals.filter(\.isActiveInHerd)
        case .workingPen:
            return records.animals.filter { $0.isActiveInHerd && $0.location == .workingPen }
        case .unassigned:
            return records.animals.filter { $0.isActiveInHerd && $0.location == .pasture && $0.pastureID == nil }
        }
    }

    func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord] {
        try fetchDashboardRecords().pastures
    }
}

@MainActor
protocol PastureGrazingMarking {
    func markPastureGrazedToday(id: UUID, on date: Date) throws
}

@MainActor
protocol DashboardReadWriting: DashboardRecordReading, PastureGrazingMarking {}

@MainActor
protocol DashboardRepository: DashboardReadWriting {}
