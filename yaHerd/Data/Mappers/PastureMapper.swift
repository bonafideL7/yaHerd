import Foundation

enum PastureMapper {
    static func makeSummary(from pasture: Pasture) -> PastureSummary {
        PastureSummary(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter(\.isActiveInHerd).count
        )
    }

    static func makeDetail(from pasture: Pasture) -> PastureDetailSnapshot {
        PastureDetailSnapshot(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter(\.isActiveInHerd).count,
            lastGrazedDate: pasture.lastGrazedDate
        )
    }

    static func makeResidentAnimalSummary(from animal: Animal) -> AnimalSummary {
        AnimalSummary(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .unknown,
            birthDate: animal.birthDate,
            status: animal.status,
            isArchived: animal.isArchived,
            pastureID: animal.pasture?.publicID,
            pastureName: animal.pasture?.name,
            location: animal.location
        )
    }
}
