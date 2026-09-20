import Foundation

struct WorkingQueueEditorSourcePastureReference: Equatable {
    let id: UUID?
    let name: String?

    init(id: UUID?, name: String?) {
        self.id = id
        self.name = name
    }

    init(session: WorkingSessionDetailSnapshot) {
        self.init(session: session, livePastures: nil)
    }

    init(
        session: WorkingSessionDetailSnapshot,
        livePastures: [PastureOption]?
    ) {
        let liveID = session.isSourcePastureAvailable ? session.sourcePastureID : nil
        let liveName = liveID.flatMap { id in
            livePastures?.first(where: { $0.id == id })?.name
        }

        self.init(
            id: liveID,
            name: liveName ?? session.sourcePastureName
        )
    }
}

enum WorkingQueueEditorIdentity {
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

    static func validatedDestinationPastureSelection(
        persistedDestinationPastureID: UUID?,
        sourcePasture: WorkingQueueEditorSourcePastureReference?,
        historicalSourcePastureID: UUID?,
        availablePastureIDs: Set<UUID>?
    ) -> (selection: UUID?, requiresReview: Bool) {
        if canUseSourcePasture(sourcePasture),
           persistedDestinationPastureID == sourcePasture?.id {
            return (nil, false)
        }

        if !canUseSourcePasture(sourcePasture),
           persistedDestinationPastureID == historicalSourcePastureID {
            return (nil, true)
        }

        guard let persistedDestinationPastureID else {
            return canUseSourcePasture(sourcePasture)
                ? (nil, false)
                : (nil, true)
        }

        guard let availablePastureIDs else {
            return (persistedDestinationPastureID, false)
        }

        return availablePastureIDs.contains(persistedDestinationPastureID)
            ? (persistedDestinationPastureID, false)
            : (nil, true)
    }

    static func destinationPastureIDForSave(
        selectedDestinationPastureID: UUID?,
        sourcePasture: WorkingQueueEditorSourcePastureReference
    ) -> UUID? {
        selectedDestinationPastureID ?? sourcePasture.id
    }
}
