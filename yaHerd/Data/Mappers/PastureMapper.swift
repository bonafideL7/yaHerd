import Foundation

enum PastureMapper {
    static func makeSummary(from pasture: Pasture) -> PastureSummary {
        PastureSummary(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter(\.isActiveInHerd).count,
            sortOrder: pasture.sortOrder,
            lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.publicID,
            groupName: pasture.group?.name,
            restDays: pasture.group?.restDays
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
            lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.publicID,
            groupName: pasture.group?.name
        )
    }

    static func makeGroupSummary(from group: PastureGroup) -> PastureGroupSummary {
        PastureGroupSummary(
            id: group.publicID,
            name: group.name,
            grazeDays: group.grazeDays,
            restDays: group.restDays,
            pastureCount: group.pastures.count
        )
    }

    static func makeGroupDetail(from group: PastureGroup) -> PastureGroupDetailSnapshot {
        PastureGroupDetailSnapshot(
            id: group.publicID,
            name: group.name,
            grazeDays: group.grazeDays,
            restDays: group.restDays,
            pastures: group.pastures
                .map { Self.makeSummary(from: $0) }
                .sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder {
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        )
    }
}


extension PastureMapper {
    static func makeSummary(from pasture: CDPasture) -> PastureSummary {
        PastureSummary(
            id: pasture.id,
            name: pasture.name,
            acreage: pasture.acreage?.doubleValue,
            usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: activeAnimalCount(in: pasture),
            sortOrder: Int(pasture.sortOrder),
            lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.id,
            groupName: pasture.group?.name,
            restDays: pasture.group.map { Int($0.restDays) }
        )
    }

    static func makeDetail(from pasture: CDPasture) -> PastureDetailSnapshot {
        PastureDetailSnapshot(
            id: pasture.id,
            name: pasture.name,
            acreage: pasture.acreage?.doubleValue,
            usableAcreage: pasture.usableAcreage?.doubleValue,
            targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
            activeAnimalCount: activeAnimalCount(in: pasture),
            lastGrazedDate: pasture.lastGrazedDate,
            groupID: pasture.group?.id,
            groupName: pasture.group?.name
        )
    }

    static func makeGroupSummary(from group: CDPastureGroup) -> PastureGroupSummary {
        PastureGroupSummary(
            id: group.id,
            name: group.name,
            grazeDays: Int(group.grazeDays),
            restDays: Int(group.restDays),
            pastureCount: group.pastures?.count ?? 0
        )
    }

    static func makeGroupDetail(from group: CDPastureGroup) -> PastureGroupDetailSnapshot {
        let pastures = group.pastures?.allObjects.compactMap { $0 as? CDPasture } ?? []
        return PastureGroupDetailSnapshot(
            id: group.id,
            name: group.name,
            grazeDays: Int(group.grazeDays),
            restDays: Int(group.restDays),
            pastures: pastures
                .map(makeSummary)
                .sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder {
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        )
    }

    private static func activeAnimalCount(in pasture: CDPasture) -> Int {
        pasture.animals?.allObjects
            .compactMap { $0 as? CDAnimal }
            .filter {
                AnimalStatus(rawValue: $0.statusRawValue) == .active && !$0.isArchived
            }
            .count ?? 0
    }
}
