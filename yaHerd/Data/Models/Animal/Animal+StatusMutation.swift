import Foundation

extension Animal {
    func applyStatus(_ newStatus: AnimalStatus, effectiveDate: Date = .now) {
        applyStatusState(
            AnimalStatusTransitionService.normalizedState(
                status: newStatus,
                saleDate: saleDate,
                salePrice: salePrice,
                reasonSold: reasonSold,
                deathDate: deathDate,
                causeOfDeath: causeOfDeath,
                statusReferenceID: statusReferenceID,
                effectiveDate: effectiveDate
            )
        )
    }

    func applyStatusState(_ state: AnimalStatusState) {
        status = state.status
        saleDate = state.saleDate
        salePrice = state.salePrice
        reasonSold = state.reasonSold
        deathDate = state.deathDate
        causeOfDeath = state.causeOfDeath
        statusReferenceID = state.statusReferenceID
    }
}
