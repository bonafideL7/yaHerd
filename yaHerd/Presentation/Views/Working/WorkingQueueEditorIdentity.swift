import Foundation

struct WorkingQueueEditorSourcePastureReference: Equatable {
    let id: UUID?
    let name: String?

    init(id: UUID?, name: String?) {
        self.id = id
        self.name = name
    }

    init(session: WorkingSessionDetailSnapshot) {
        self.init(
            id: session.sourcePastureID,
            name: session.sourcePastureName
        )
    }
}

struct WorkingQueueEditorIdentity: Equatable {
    let id: UUID
    let animalID: UUID?
    let destinationPastureID: UUID?

    init(snapshot: WorkingQueueItemEditorSnapshot) {
        id = snapshot.id
        animalID = snapshot.animalID
        destinationPastureID = snapshot.destinationPastureID
    }

    static func invalidates(
        presented: WorkingQueueItemEditorSnapshot,
        refreshed: WorkingQueueItemEditorSnapshot?
    ) -> Bool {
        guard let refreshed else { return true }
        return WorkingQueueEditorIdentity(snapshot: presented)
            != WorkingQueueEditorIdentity(snapshot: refreshed)
    }

    static func sourcePastureChangeRequiresReview(
        presented: WorkingQueueEditorSourcePastureReference?,
        refreshed: WorkingQueueEditorSourcePastureReference,
        selectedDestinationPastureID: UUID?
    ) -> Bool {
        guard selectedDestinationPastureID == nil else { return false }
        guard let presented else { return true }
        return presented.id != refreshed.id
    }

    static func canUseSourcePasture(
        _ sourcePasture: WorkingQueueEditorSourcePastureReference?
    ) -> Bool {
        sourcePasture?.id != nil
    }

    static func destinationPastureSelection(
        persistedDestinationPastureID: UUID?,
        sourcePasture: WorkingQueueEditorSourcePastureReference?
    ) -> UUID? {
        guard let sourcePasture else { return persistedDestinationPastureID }
        return persistedDestinationPastureID == sourcePasture.id
            ? nil
            : persistedDestinationPastureID
    }

    static func destinationPastureIDForSave(
        selectedDestinationPastureID: UUID?,
        sourcePasture: WorkingQueueEditorSourcePastureReference
    ) -> UUID? {
        selectedDestinationPastureID ?? sourcePasture.id
    }
}
