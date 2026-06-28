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
