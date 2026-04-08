import Foundation

struct MarkPastureGrazedTodayUseCase {
    let repository: any DashboardRepository

    func execute(pastureID: UUID, now: Date = .now) throws {
        try repository.markPastureGrazedToday(id: pastureID, on: now)
    }
}
