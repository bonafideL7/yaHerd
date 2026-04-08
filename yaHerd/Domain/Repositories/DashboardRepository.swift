import Foundation

protocol DashboardRepository {
    func fetchDashboardRecords() throws -> DashboardRecords
    func markPastureGrazedToday(id: UUID, on date: Date) throws
}
