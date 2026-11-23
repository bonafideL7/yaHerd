import Foundation

@MainActor
final class WorkingQueueItemEditorViewModel: ObservableObject {
    @Published private(set) var snapshot: WorkingQueueItemEditorSnapshot?
    @Published var errorMessage: String?

    private let sessionID: UUID
    private let queueItemID: UUID
    private var repository: any WorkingQueueItemEditingRepository
    private var herdSelection: AppCurrentHerdSelection?
    private var originatingHerdIdentity: WorkingQueueEditorHerdIdentity?

    private var isOriginatingHerdActive: Bool {
        guard let herdSelection, let originatingHerdIdentity else { return false }
        return originatingHerdIdentity.isCurrent(in: herdSelection)
    }

    init(
        sessionID: UUID,
        queueItemID: UUID,
        repository: any WorkingQueueItemEditingRepository
    ) {
        self.sessionID = sessionID
        self.queueItemID = queueItemID
        self.repository = repository
    }

    func configure(
        repository: any WorkingQueueItemEditingRepository,
        herdSelection: AppCurrentHerdSelection
    ) {
        self.repository = repository
        // Preserve the opening selection generation even if a queued task
        // resumes after the user switches away and back to the same Herd.
        if self.herdSelection == nil {
            self.herdSelection = herdSelection
            originatingHerdIdentity = WorkingQueueEditorHerdIdentity(selection: herdSelection)
        }
    }

    /// Discard data from an editor whose opening Herd or selection revision
    /// is no longer active. A later return to the same UUID cannot revive it.
    func invalidateForHerdChange() {
        guard !isOriginatingHerdActive else { return }
        snapshot = nil
        errorMessage = nil
    }

    func load() {
        guard isOriginatingHerdActive else { return }
        do {
            snapshot = try repository.fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            )
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func replacePrimaryTag(number: String, colorID: UUID?) async {
        guard isOriginatingHerdActive, !Task.isCancelled else { return }
        do {
            let updated = try await repository.replacePrimaryTag(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingTagReplacementInput(number: number, colorID: colorID)
            )
            guard isOriginatingHerdActive, !Task.isCancelled else { return }
            snapshot = updated
            errorMessage = nil
        } catch {
            guard isOriginatingHerdActive, !Task.isCancelled else { return }
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
