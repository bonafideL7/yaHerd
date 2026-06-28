import Foundation

struct MarkPastureGrazedTodayUseCase {
    let repository: any PastureGrazingMarking

    func execute(pastureID: UUID, now: Date = .now) throws {
        try repository.markPastureGrazedToday(id: pastureID, on: now)
    }
}
