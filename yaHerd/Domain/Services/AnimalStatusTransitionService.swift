import Foundation

struct AnimalStatusState: Hashable {
    let status: AnimalStatus
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
}

enum AnimalStatusTransitionService {
    static func normalizedState(
        status: AnimalStatus,
        saleDate: Date?,
        salePrice: Double?,
        reasonSold: String?,
        deathDate: Date?,
        causeOfDeath: String?,
        statusReferenceID: UUID?,
        effectiveDate: Date
    ) -> AnimalStatusState {
        switch status {
        case .active:
            return AnimalStatusState(
                status: status,
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: statusReferenceID
            )
        case .sold:
            return AnimalStatusState(
                status: status,
                saleDate: saleDate ?? effectiveDate,
                salePrice: salePrice,
                reasonSold: reasonSold,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: statusReferenceID
            )
        case .dead:
            return AnimalStatusState(
                status: status,
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: deathDate ?? effectiveDate,
                causeOfDeath: causeOfDeath,
                statusReferenceID: statusReferenceID
            )
        }
    }

    static func effectiveDate(
        for status: AnimalStatus,
        saleDate: Date?,
        deathDate: Date?,
        now: Date = .now
    ) -> Date {
        switch status {
        case .active:
            return now
        case .sold:
            return saleDate ?? now
        case .dead:
            return deathDate ?? now
        }
    }
}
