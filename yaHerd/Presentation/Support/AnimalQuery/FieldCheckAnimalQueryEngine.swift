import Foundation

enum FieldCheckAnimalQueryEngine {
    static func apply(
        to checks: [FieldCheckAnimalCheckSnapshot],
        query: AnimalQuery,
        formatTag: (String, UUID?) -> String
    ) -> [FieldCheckAnimalCheckSnapshot] {
        var result = checks

        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            result = result.filter { check in
                check.displayTagNumber.localizedCaseInsensitiveContains(searchText)
                    || formatTag(check.displayTagNumber, check.displayTagColorID)
                        .localizedCaseInsensitiveContains(searchText)
                    || check.animalName.localizedCaseInsensitiveContains(searchText)
                    || (check.damDisplayTagNumber?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || formatTag(check.damDisplayTagNumber ?? "", check.damDisplayTagColorID)
                        .localizedCaseInsensitiveContains(searchText)
            }
        }

        if let selectedSex = query.filter.sex {
            result = result.filter { $0.animalSex == selectedSex }
        }

        if let selectedAnimalType = query.filter.animalType {
            result = result.filter { $0.animalType == selectedAnimalType }
        }

        switch query.sortOrder {
        case .tagAscending:
            result.sort(by: tagAscending)
        case .tagDescending:
            result.sort {
                $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedDescending
            }
        case .sex:
            result.sort { left, right in
                if left.animalSex.rawValue != right.animalSex.rawValue {
                    return left.animalSex.rawValue < right.animalSex.rawValue
                }
                return tagAscending(left, right)
            }
        case .animalType:
            result.sort { left, right in
                if left.animalType.rawValue != right.animalType.rawValue {
                    return left.animalType.rawValue < right.animalType.rawValue
                }
                return tagAscending(left, right)
            }
        case .birthDateNewest, .birthDateOldest, .status, .pasture:
            result.sort(by: tagAscending)
        }

        return result
    }

    private static func tagAscending(
        _ left: FieldCheckAnimalCheckSnapshot,
        _ right: FieldCheckAnimalCheckSnapshot
    ) -> Bool {
        left.displayTagNumber.localizedStandardCompare(right.displayTagNumber) == .orderedAscending
    }
}

enum FieldCheckRosterQueryEngine {
    static func apply(
        to checks: [FieldCheckAnimalCheckSnapshot],
        rosterFilter: FieldCheckRosterFilter,
        effectivelySeenCheckIDs: Set<UUID>,
        query: AnimalQuery,
        formatTag: (String, UUID?) -> String
    ) -> [FieldCheckAnimalCheckSnapshot] {
        let rosterFilteredChecks = checks.filter { check in
            let isEffectivelySeen = check.wasCounted || effectivelySeenCheckIDs.contains(check.id)

            switch rosterFilter {
            case .all:
                return true
            case .remaining:
                return !isEffectivelySeen && !check.isMissing
            case .seen:
                return isEffectivelySeen
            case .missing:
                return check.isMissing
            case .flagged:
                return check.needsAttention
            }
        }

        return FieldCheckAnimalQueryEngine.apply(
            to: rosterFilteredChecks,
            query: query,
            formatTag: formatTag
        )
    }
}
