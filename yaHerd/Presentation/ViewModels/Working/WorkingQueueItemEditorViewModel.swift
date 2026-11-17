import Foundation

@MainActor
final class WorkingQueueItemEditorViewModel: ObservableObject {
    @Published private(set) var snapshot: WorkingQueueItemEditorSnapshot?
    @Published var errorMessage: String?

    private let sessionID: UUID
    private let queueItemID: UUID
    private var repository: any WorkingQueueItemEditingRepository
    private var herdSelection: (any CurrentHerdSelectionReading)?
    private var originatingHerdID: UUID?

    private var isOriginatingHerdActive: Bool {
        guard let herdSelection, let originatingHerdID else { return false }
        return herdSelection.currentHerdID == originatingHerdID
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
        herdSelection: any CurrentHerdSelectionReading
    ) {
        self.repository = repository
        // The view belongs to its initial Herd even if an old task resumes
        // after the application's active Herd has changed.
        if self.herdSelection == nil {
            self.herdSelection = herdSelection
            originatingHerdID = herdSelection.currentHerdID
        }
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
