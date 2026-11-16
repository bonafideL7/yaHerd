import Foundation

@MainActor
final class WorkingFinishSessionViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var hasLoadedPastureOptions = false
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
        currentHerdSelection: any CurrentHerdSelectionReading,
        repository: any WorkingFinishSessionRepository
    ) async throws -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID else {
            return false
        }

        try await CompleteWorkingSessionUseCase(repository: repository).execute(
            sessionID: sessionID,
            assignments: assignments
        )

        return !Task.isCancelled
            && currentHerdSelection.currentHerdID == originatingHerdID
    }

    var needsPastureOptionsRetry: Bool {
        session != nil && !hasLoadedPastureOptions
    }

    func configure(workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func load() {
        do {
            session = try workingRepository.fetchSessionDetail(id: sessionID)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return
        }

        loadPastureOptions()
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
            hasLoadedPastureOptions = false
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
