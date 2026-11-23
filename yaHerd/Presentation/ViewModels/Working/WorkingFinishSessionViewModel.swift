import Foundation

enum WorkingFinishSessionLoadState: Equatable {
    case loading
    case ready
    case missing
    case failed
}

@MainActor
final class WorkingFinishSessionViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var hasLoadedPastureOptions = false
    @Published private(set) var sessionLoadState: WorkingFinishSessionLoadState = .loading
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var workingRepository: any WorkingSessionDetailReader
    private var pastureRepository: any PastureReferenceDataReader

    init(sessionID: UUID, workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.sessionID = sessionID
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    /// A queued finish must not write against a different selected Herd.
    /// The repository owns the in-flight transaction; only the originating
    /// Herd may acknowledge its result to presentation.
    @discardableResult
    func finishSession(
        assignments: [WorkingQueueDestinationAssignment],
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64,
        currentHerdSelection: AppCurrentHerdSelection,
        repository: any WorkingFinishSessionRepository
    ) async throws -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              currentHerdSelection.selectionRevision == originatingSelectionRevision else {
            return false
        }

        try await CompleteWorkingSessionUseCase(repository: repository).execute(
            sessionID: sessionID,
            assignments: assignments
        )

        return !Task.isCancelled
            && currentHerdSelection.currentHerdID == originatingHerdID
            && currentHerdSelection.selectionRevision == originatingSelectionRevision
    }

    var needsPastureOptionsRetry: Bool {
        session != nil && !hasLoadedPastureOptions
    }

    func configure(workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func load() {
        // A failed or missing re-read cannot authorize completion using
        // previously loaded session details or destination options.
        sessionLoadState = .loading
        session = nil
        pastures = []
        hasLoadedPastureOptions = false

        do {
            guard let loadedSession = try workingRepository.fetchSessionDetail(id: sessionID) else {
                sessionLoadState = .missing
                errorMessage = nil
                return
            }
            session = loadedSession
            sessionLoadState = .ready
        } catch {
            sessionLoadState = .failed
            errorMessage = UserVisibleErrorMessage.make(error)
            return
        }

        loadPastureOptions()
    }

    func retrySession() {
        load()
    }

    func retryPastureOptions() {
        guard session != nil else {
            load()
            return
        }

        loadPastureOptions()
    }

    private func loadPastureOptions() {
        do {
            pastures = try pastureRepository.fetchPastureOptions()
            hasLoadedPastureOptions = true
            errorMessage = nil
        } catch {
            pastures = []
            hasLoadedPastureOptions = false
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
