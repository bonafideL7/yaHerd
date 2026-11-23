import Foundation
import Observation

@MainActor
@Observable
final class FieldChecksViewModel {
    private(set) var sessions: [FieldCheckSessionSummary] = []
    private(set) var openFindings: [FieldCheckFindingSnapshot] = []
    var errorMessage: String?
    var hasLoaded = false
    private var isLoading = false
    private var lastLoadedRevision: UInt64 = 0

    @ObservationIgnored private var selection: AppCurrentHerdSelection?
    @ObservationIgnored private var selectedHerdID: UUID?
    @ObservationIgnored private var selectedRevision: UInt64?

    var activeSessions: [FieldCheckSessionSummary] {
        sessions.filter { !$0.isCompleted && !$0.isPastureArchived }
    }

    var archivedPastureSessions: [FieldCheckSessionSummary] {
        sessions
            .filter(\.isPastureArchived)
            .sorted { $0.startedAt > $1.startedAt }
    }

    var recentSessions: [FieldCheckSessionSummary] {
        Array(
            sessions
                .filter(\.isCompleted)
                .prefix(12)
        )
    }

    /// A list retained by SwiftUI cannot carry the previous Herd's records
    /// or mutation revision into the next selection incarnation.
    func configure(selection: AppCurrentHerdSelection) {
        let changed = self.selection !== selection
            || selectedHerdID != selection.currentHerdID
            || selectedRevision != selection.selectionRevision
        self.selection = selection
        selectedHerdID = selection.currentHerdID
        selectedRevision = selection.selectionRevision

        if changed {
            sessions = []
            openFindings = []
            errorMessage = nil
            hasLoaded = false
            lastLoadedRevision = 0
        }
    }

    func observe(
        using repository: any FieldCheckOverviewReading,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        let originatingHerdID = selectedHerdID
        let originatingRevision = selectedRevision
        guard !Task.isCancelled,
              isCurrentSelection(herdID: originatingHerdID, revision: originatingRevision) else {
            return
        }

        let startingRevision = mutationStream.fieldCheckRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if load(using: repository) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .fieldChecks,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled,
                  isCurrentSelection(herdID: originatingHerdID, revision: originatingRevision) else {
                return
            }
            if load(using: repository) {
                lastLoadedRevision = revision
            }
        }
    }

    func loadIfNeeded(using repository: any FieldCheckOverviewReading) {
        guard !hasLoaded else { return }
        _ = load(using: repository)
    }

    @discardableResult
    func load(using repository: any FieldCheckOverviewReading) -> Bool {
        guard !Task.isCancelled,
              isCurrentSelection(herdID: selectedHerdID, revision: selectedRevision),
              !isLoading else { return false }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let refreshedSessions = try repository.fetchSessions()
            let refreshedOpenFindings = try repository.fetchOpenFindings(limit: 0)
            // Both reads must succeed before replacing the last coherent
            // overview; partially imported related records can fail either.
            sessions = refreshedSessions
            openFindings = refreshedOpenFindings
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    private func isCurrentSelection(herdID: UUID?, revision: UInt64?) -> Bool {
        guard let selection else {
            return herdID == nil && revision == nil
        }
        return selectedHerdID == herdID
            && selectedRevision == revision
            && selection.currentHerdID == herdID
            && selection.selectionRevision == revision
    }
}
