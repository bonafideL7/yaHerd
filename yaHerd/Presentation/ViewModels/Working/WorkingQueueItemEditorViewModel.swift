import Foundation

@MainActor
final class WorkingQueueItemEditorViewModel: ObservableObject {
    @Published private(set) var snapshot: WorkingQueueItemEditorSnapshot?
    @Published var errorMessage: String?

    private let sessionID: UUID
    private let queueItemID: UUID
    private var repository: any WorkingQueueItemEditingRepository

    init(
        sessionID: UUID,
        queueItemID: UUID,
        repository: any WorkingQueueItemEditingRepository
    ) {
        self.sessionID = sessionID
        self.queueItemID = queueItemID
        self.repository = repository
    }

    func configure(repository: any WorkingQueueItemEditingRepository) {
        self.repository = repository
    }

    func load() {
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

    func replacePrimaryTag(number: String, colorID: UUID?) {
        do {
            snapshot = try repository.replacePrimaryTag(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingTagReplacementInput(number: number, colorID: colorID)
            )
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
