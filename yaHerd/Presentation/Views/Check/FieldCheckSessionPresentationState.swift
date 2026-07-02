import SwiftUI

enum FieldCheckRosterFilter: String, CaseIterable, Identifiable {
    case all
    case remaining
    case flagged
    case missing
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .all:
            return "All"
        case .remaining:
            return "Remaining"
        case .flagged:
            return "Flagged"
        case .missing:
            return "Missing"
        }
    }
}

enum FieldCheckLinkedAnimalPickerFilter: String, CaseIterable, Identifiable {
    case all
    case remaining
    case missing
    case flagged
    case checked
    case added

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .remaining:
            return "Remaining"
        case .missing:
            return "Missing"
        case .flagged:
            return "Flagged"
        case .checked:
            return "Checked"
        case .added:
            return "Added"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .remaining:
            return "circle.dotted"
        case .missing:
            return "questionmark.circle"
        case .flagged:
            return "exclamationmark.triangle"
        case .checked:
            return "checkmark.circle"
        case .added:
            return "plus.circle"
        }
    }
}

enum FieldCheckLinkedAnimalPickerRules {
    static func animalOptions(from animals: [FieldCheckAnimalCheckSnapshot]) -> [FieldCheckAnimalCheckSnapshot] {
        animals
            .filter { $0.animalID != nil }
            .sorted { left, right in
                sortKey(for: left).localizedStandardCompare(sortKey(for: right)) == .orderedAscending
            }
    }

    static func filteredAnimals(
        from animals: [FieldCheckAnimalCheckSnapshot],
        searchText: String,
        filter: FieldCheckLinkedAnimalPickerFilter
    ) -> [FieldCheckAnimalCheckSnapshot] {
        let query = normalizedSearchText(searchText)

        return animals
            .filter { matches(filter: filter, animal: $0) }
            .filter { animal in
                guard !query.isEmpty else { return true }
                return searchTokens(for: animal).contains { token in
                    token.localizedCaseInsensitiveContains(query)
                }
            }
    }

    static func priorityAnimals(
        from animals: [FieldCheckAnimalCheckSnapshot],
        excluding selectedAnimalID: UUID?,
        limit: Int
    ) -> [FieldCheckAnimalCheckSnapshot] {
        Array(
            animals
                .filter { $0.animalID != selectedAnimalID }
                .sorted { left, right in
                    let leftPriority = priorityScore(for: left)
                    let rightPriority = priorityScore(for: right)
                    if leftPriority != rightPriority {
                        return leftPriority > rightPriority
                    }
                    return sortKey(for: left).localizedStandardCompare(sortKey(for: right)) == .orderedAscending
                }
                .prefix(max(limit, 0))
        )
    }

    static func searchCompletionText(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let tag = animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            return animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tag
    }

    static func statusSummary(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        var statuses: [String] = []

        if !animal.wasExpectedAtStart {
            statuses.append("Added")
        }

        if animal.isMissing {
            statuses.append("Missing")
        }

        if animal.wasCounted {
            statuses.append("Checked")
        }

        if animal.needsAttention {
            statuses.append("Flagged")
        }

        if statuses.isEmpty {
            statuses.append("Expected")
        }

        statuses.append(animal.animalType.label)
        return statuses.joined(separator: " • ")
    }

    private static func matches(filter: FieldCheckLinkedAnimalPickerFilter, animal: FieldCheckAnimalCheckSnapshot) -> Bool {
        switch filter {
        case .all:
            return true
        case .remaining:
            return !animal.wasCounted && !animal.isMissing
        case .missing:
            return animal.isMissing
        case .flagged:
            return animal.needsAttention
        case .checked:
            return animal.wasCounted
        case .added:
            return !animal.wasExpectedAtStart
        }
    }

    private static func priorityScore(for animal: FieldCheckAnimalCheckSnapshot) -> Int {
        if animal.isMissing { return 500 }
        if animal.needsAttention { return 400 }
        if !animal.wasCounted { return 300 }
        if !animal.wasExpectedAtStart { return 200 }
        return 100
    }

    private static func sortKey(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            animal.displayTagNumber,
            trimmedName,
            animal.animalType.label,
            animal.animalSex.label
        ]
        .joined(separator: " ")
    }

    private static func searchTokens(for animal: FieldCheckAnimalCheckSnapshot) -> [String] {
        [
            animal.displayTagNumber,
            animal.animalName,
            animal.animalType.label,
            animal.animalSex.label,
            animal.damDisplayTagNumber ?? "",
            statusSummary(for: animal)
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func normalizedSearchText(_ searchText: String) -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FieldCheckSessionPane: String, CaseIterable, Identifiable {
    case summary
    case roster
    case quickCount
    case findings
    case notes
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .summary:
            return "Summary"
        case .roster:
            return "Roster"
        case .quickCount:
            return "Quick Count"
        case .findings:
            return "Findings"
        case .notes:
            return "Notes"
        }
    }
    
    static let defaultPane: FieldCheckSessionPane = .roster
}

extension View {
    func applyFieldCheckNavigationSubtitle(_ subtitle: String) -> some View {
        self.navigationSubtitle(subtitle)
    }
}
