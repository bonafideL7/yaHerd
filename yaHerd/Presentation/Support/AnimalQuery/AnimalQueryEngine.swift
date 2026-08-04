import Foundation

enum AnimalQueryEngine {
    static func apply(
        to items: [AnimalSummary],
        query: AnimalQuery,
        mandatoryConstraint: (AnimalSummary) -> Bool = { _ in true },
        availableSortOrders: Set<AnimalSortOrder>? = nil,
        tieBreaker: ((AnimalSummary, AnimalSummary) -> Bool)? = nil,
        formatTag: (String, UUID?) -> String
    ) -> [AnimalSummary] {
        var result = items.filter(mandatoryConstraint)

        if !query.showRemovedStatuses {
            result = result.filter { $0.status == .active }
        }

        if !query.showArchivedRecords {
            result = result.filter { !$0.isArchived }
        }

        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            result = result.filter {
                $0.displayTagNumber.localizedCaseInsensitiveContains(searchText)
                || formatTag($0.displayTagNumber, $0.displayTagColorID)
                    .localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let selectedSex = query.filter.sex {
            result = result.filter { $0.sex == selectedSex }
        }

        if let selectedAnimalType = query.filter.animalType {
            result = result.filter { $0.animalType == selectedAnimalType }
        }

        if let selectedStatus = query.filter.status {
            result = result.filter { $0.status == selectedStatus }
        }

        switch query.filter.pasture {
        case .any:
            break
        case .noPasture:
            result = result.filter(isNoPasture)
        case let .pasture(selectedPastureID):
            result = result.filter { $0.pastureID == selectedPastureID }
        }

        switch query.filter.location {
        case .any:
            break
        case .pasture:
            result = result.filter { $0.location == .pasture }
        case .workingPen:
            result = result.filter { $0.location == .workingPen }
        }

        switch query.filter.recordIssue {
        case .any:
            break
        case .missingPasture:
            result = result.filter { $0.isActiveInVisibleHerd && isNoPasture($0) }
        case .missingTag:
            result = result.filter {
                $0.isActiveInVisibleHerd
                    && $0.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .unknownSex:
            result = result.filter { $0.isActiveInVisibleHerd && $0.sex == .unknown }
        case .archivedActive:
            result = result.filter { $0.isArchived && $0.status == .active }
        }

        let sortOrder = resolvedSortOrder(
            query.sortOrder,
            availableSortOrders: availableSortOrders
        )
        sort(&result, by: sortOrder, tieBreaker: tieBreaker)
        return result
    }

    private static func resolvedSortOrder(
        _ requested: AnimalSortOrder,
        availableSortOrders: Set<AnimalSortOrder>?
    ) -> AnimalSortOrder {
        guard let availableSortOrders, !availableSortOrders.contains(requested) else {
            return requested
        }

        return availableSortOrders.contains(.tagAscending)
            ? .tagAscending
            : availableSortOrders.first ?? requested
    }

    private static func sort(
        _ animals: inout [AnimalSummary],
        by sortOrder: AnimalSortOrder,
        tieBreaker: ((AnimalSummary, AnimalSummary) -> Bool)?
    ) {
        let sortsBefore: (AnimalSummary, AnimalSummary) -> Bool

        switch sortOrder {
        case .tagAscending:
            sortsBefore = tagAscending
        case .tagDescending:
            sortsBefore = {
                $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedDescending
            }
        case .birthDateNewest:
            sortsBefore = { $0.birthDate > $1.birthDate }
        case .birthDateOldest:
            sortsBefore = { $0.birthDate < $1.birthDate }
        case .sex:
            sortsBefore = { lhs, rhs in
                if lhs.sex.rawValue != rhs.sex.rawValue {
                    return lhs.sex.rawValue < rhs.sex.rawValue
                }
                return tagAscending(lhs, rhs)
            }
        case .animalType:
            sortsBefore = { lhs, rhs in
                let lhsKey = animalTypeSortKey(for: lhs.animalType)
                let rhsKey = animalTypeSortKey(for: rhs.animalType)
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                return tagAscending(lhs, rhs)
            }
        case .status:
            sortsBefore = { lhs, rhs in
                if lhs.status.rawValue != rhs.status.rawValue {
                    return lhs.status.rawValue < rhs.status.rawValue
                }
                return tagAscending(lhs, rhs)
            }
        case .pasture:
            sortsBefore = { lhs, rhs in
                let lhsKey = pastureSortKey(for: lhs)
                let rhsKey = pastureSortKey(for: rhs)
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                return tagAscending(lhs, rhs)
            }
        }

        animals.sort { lhs, rhs in
            if sortsBefore(lhs, rhs) {
                return true
            }
            if sortsBefore(rhs, lhs) {
                return false
            }
            return tieBreaker?(lhs, rhs) ?? false
        }
    }

    static func animalTypeSortKey(for animalType: AnimalType) -> String {
        switch animalType {
        case .calf:
            return "0-calf"
        case .heifer:
            return "1-heifer"
        case .steer:
            return "2-steer"
        case .cow:
            return "3-cow"
        case .bull:
            return "4-bull"
        }
    }

    private static func isNoPasture(_ animal: AnimalSummary) -> Bool {
        animal.location != .workingPen && animal.pastureID == nil
    }

    private static func pastureSortKey(for animal: AnimalSummary) -> String {
        if animal.location == .workingPen {
            return "0-working-pen"
        }

        if let pastureName = animal.pastureName, !pastureName.isEmpty {
            return "1-\(pastureName.lowercased())"
        }

        return "2-no-pasture"
    }

    private static func tagAscending(_ lhs: AnimalSummary, _ rhs: AnimalSummary) -> Bool {
        lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
    }
}

enum WorkingQueueAnimalQueryEngine {
    static func apply(
        to items: [WorkingQueueItemSnapshot],
        summariesByID: [UUID: AnimalSummary],
        query: AnimalQuery,
        formatTag: (String, UUID?) -> String
    ) -> [WorkingQueueItemSnapshot] {
        var seenCandidateIDs = Set<UUID>()
        let candidates = items.compactMap { item -> AnimalSummary? in
            guard let animalID = item.animalID,
                  seenCandidateIDs.insert(animalID).inserted else {
                return nil
            }
            return summariesByID[animalID]
        }
        let sourceRankByAnimalID = Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map { ($0.element.id, $0.offset) }
        )

        let sortQuery = AnimalQuery(
            sortOrder: query.sortOrder,
            showRemovedStatuses: true,
            showArchivedRecords: true
        )
        let sortedCandidateIDs = AnimalQueryEngine.apply(
            to: candidates,
            query: sortQuery,
            tieBreaker: { lhs, rhs in
                let lhsRank = sourceRankByAnimalID[lhs.id] ?? .max
                let rhsRank = sourceRankByAnimalID[rhs.id] ?? .max
                return lhsRank < rhsRank
            },
            formatTag: formatTag
        )
        .map(\.id)
        let rankByAnimalID = Dictionary(
            uniqueKeysWithValues: sortedCandidateIDs.enumerated().map { ($0.element, $0.offset) }
        )

        let orderedItems = items.sorted { left, right in
            let leftRank = left.animalID.flatMap { rankByAnimalID[$0] }
            let rightRank = right.animalID.flatMap { rankByAnimalID[$0] }

            switch (leftRank, rightRank) {
            case let (.some(leftRank), .some(rightRank)):
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            return fallbackSort(left, right)
        }

        guard query.hasNarrowingCriteria else {
            return orderedItems
        }

        let matchingAnimalIDs = Set(
            AnimalQueryEngine.apply(
                to: candidates,
                query: query,
                formatTag: formatTag
            )
            .map(\.id)
        )

        return orderedItems.filter { item in
            guard let animalID = item.animalID else { return false }
            return matchingAnimalIDs.contains(animalID)
        }
    }

    private static func fallbackSort(
        _ left: WorkingQueueItemSnapshot,
        _ right: WorkingQueueItemSnapshot
    ) -> Bool {
        let leftTag = left.animalDisplayTagNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rightTag = right.animalDisplayTagNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if leftTag.isEmpty != rightTag.isEmpty {
            return !leftTag.isEmpty
        }

        let comparison = leftTag.localizedStandardCompare(rightTag)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }

        return left.id.uuidString < right.id.uuidString
    }
}

private extension AnimalSummary {
    var isActiveInVisibleHerd: Bool {
        status == .active && !isArchived
    }
}
