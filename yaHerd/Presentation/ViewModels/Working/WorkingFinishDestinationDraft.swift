import Foundation

/// Reconciles successful reads with the finish-session draft. A failed read
/// never supplies a new baseline; nil destination options are not authoritative.
enum WorkingFinishDestinationDraft {
    struct Exception: Equatable {
        let isSelected: Bool
        let destinationID: UUID?
    }

    struct Reconciliation {
        let savedExceptions: [UUID: Exception]
        let selectedIDs: Set<UUID>
        let destinations: [UUID: UUID]
    }

    static func reconcile(
        queueItems: [WorkingQueueItemSnapshot],
        sourcePastureID: UUID?,
        validDestinations: Set<UUID>?,
        savedExceptions: [UUID: Exception],
        selectedIDs: Set<UUID>,
        destinations: [UUID: UUID]
    ) -> Reconciliation {
        var nextSaved: [UUID: Exception] = [:]
        var nextSelection: Set<UUID> = []
        var nextDestinations: [UUID: UUID] = [:]

        for item in queueItems {
            let selected = sourcePastureID == nil ||
                (item.destinationPastureID != nil && item.destinationPastureID != sourcePastureID)
            let destinationID = item.destinationPastureID.flatMap { id in
                validDestinations?.contains(id) != false ? id : nil
            }
            let saved = Exception(isSelected: selected, destinationID: selected ? destinationID : nil)
            let draft = Exception(isSelected: selectedIDs.contains(item.id), destinationID: destinations[item.id])
            let resolved: Exception
            if let previous = savedExceptions[item.id], draft != previous {
                resolved = draft
            } else {
                resolved = saved
            }
            nextSaved[item.id] = saved
            guard resolved.isSelected || sourcePastureID == nil else { continue }
            nextSelection.insert(item.id)
            if let destinationID = resolved.destinationID,
               validDestinations?.contains(destinationID) != false {
                nextDestinations[item.id] = destinationID
            }
        }
        return Reconciliation(
            savedExceptions: nextSaved, selectedIDs: nextSelection, destinations: nextDestinations
        )
    }
}
