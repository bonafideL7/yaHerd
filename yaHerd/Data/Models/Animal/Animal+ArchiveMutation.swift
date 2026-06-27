import Foundation

extension Animal {
    func archive(reason: String? = nil, at date: Date = .now) {
        applyArchiveState(AnimalArchiveService.archived(reason: reason, at: date))
    }

    func restoreArchivedRecord() {
        applyArchiveState(AnimalArchiveService.restored())
    }

    func softDelete(reason: String? = nil, at date: Date = .now) {
        archive(reason: reason, at: date)
    }

    func restoreSoftDeletedRecord() {
        restoreArchivedRecord()
    }

    private func applyArchiveState(_ state: AnimalArchiveState) {
        isSoftDeleted = state.isArchived
        softDeletedAt = state.archivedAt
        softDeleteReason = state.reason
    }
}
