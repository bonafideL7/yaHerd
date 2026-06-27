import Foundation

struct AnimalArchiveState: Hashable {
    let isArchived: Bool
    let archivedAt: Date?
    let reason: String?
}

enum AnimalArchiveService {
    static func archived(reason: String?, at date: Date = .now) -> AnimalArchiveState {
        AnimalArchiveState(
            isArchived: true,
            archivedAt: date,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func restored() -> AnimalArchiveState {
        AnimalArchiveState(isArchived: false, archivedAt: nil, reason: nil)
    }
}
