import Foundation

protocol DashboardRecordReading {
    func fetchDashboardRecords() throws -> DashboardRecords
}

protocol PastureGrazingMarking {
    func markPastureGrazedToday(id: UUID, on date: Date) throws
}

protocol DashboardReadWriting: DashboardRecordReading, PastureGrazingMarking {}

protocol DashboardRepository: DashboardReadWriting {}
