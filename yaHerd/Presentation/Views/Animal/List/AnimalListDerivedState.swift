import Foundation

struct AnimalSection: Identifiable {
    let id: String
    let title: String
    let animals: [AnimalSummary]
}

struct AnimalListEmptyStateConfiguration {
    let title: String
    let description: String
    let systemImage: String
}

enum AnimalListDerivations {
    static func filteredAndSortedAnimals(
        items: [AnimalSummary],
        searchText: String,
        sortOrder: AnimalSortOrder,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool,
        formatTag: (String, UUID?) -> String
    ) -> [AnimalSummary] {
        var result = items

        if !showRemovedStatuses {
            result = result.filter { $0.status == .active }
        }

        if !showArchivedRecords {
            result = result.filter { !$0.isArchived }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.displayTagNumber.localizedCaseInsensitiveContains(query)
                || formatTag($0.displayTagNumber, $0.displayTagColorID).localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
            }
        }

        if let selectedSex = filter.sex {
            result = result.filter { $0.sex == selectedSex }
        }

        if let selectedAnimalType = filter.animalType {
            result = result.filter { $0.animalType == selectedAnimalType }
        }

        if let selectedStatus = filter.status {
            result = result.filter { $0.status == selectedStatus }
        }

        switch filter.pasture {
        case .any:
            break
        case .noPasture:
            result = result.filter { isNoPasture($0) }
        case let .pasture(selectedPastureID):
            result = result.filter { $0.pastureID == selectedPastureID }
        }

        switch sortOrder {
        case .tagAscending:
            result.sort { $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending }
        case .tagDescending:
            result.sort { $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedDescending }
        case .birthDateNewest:
            result.sort { $0.birthDate > $1.birthDate }
        case .birthDateOldest:
            result.sort { $0.birthDate < $1.birthDate }
        case .sex:
            result.sort { lhs, rhs in
                if lhs.sex.rawValue != rhs.sex.rawValue {
                    return lhs.sex.rawValue < rhs.sex.rawValue
                }

                return tagAscending(lhs, rhs)
            }
        case .animalType:
            result.sort { lhs, rhs in
                let lhsKey = animalTypeSortKey(for: lhs.animalType)
                let rhsKey = animalTypeSortKey(for: rhs.animalType)

                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }

                return tagAscending(lhs, rhs)
            }
        case .status:
            result.sort { lhs, rhs in
                if lhs.status.rawValue != rhs.status.rawValue {
                    return lhs.status.rawValue < rhs.status.rawValue
                }

                return tagAscending(lhs, rhs)
            }
        case .pasture:
            result.sort { lhs, rhs in
                let lhsKey = pastureSortKey(for: lhs)
                let rhsKey = pastureSortKey(for: rhs)

                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }

                return tagAscending(lhs, rhs)
            }
        }

        return result
    }

    static func groupedAnimals(_ animals: [AnimalSummary], sortOrder: AnimalSortOrder) -> [AnimalSection] {
        switch sortOrder {
        case .sex:
            let grouped = Dictionary(grouping: animals) { $0.sex.label }
            return grouped
                .map { key, value in
                    AnimalSection(id: "sex-\(key)", title: key, animals: value)
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .animalType:
            let grouped = Dictionary(grouping: animals) { $0.animalType.label }
            return grouped
                .map { key, value in
                    AnimalSection(id: "animal-type-\(key)", title: key, animals: value)
                }
                .sorted { animalTypeSectionSortKey(for: $0.title) < animalTypeSectionSortKey(for: $1.title) }

        case .status:
            let grouped = Dictionary(grouping: animals) { $0.status.label }
            return grouped
                .map { key, value in
                    AnimalSection(id: "status-\(key)", title: key, animals: value)
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .pasture:
            let grouped = Dictionary(grouping: animals) { pastureSectionTitle(for: $0) }
            return grouped
                .map { key, value in
                    AnimalSection(id: "pasture-\(key)", title: key, animals: value)
                }
                .sorted { pastureSectionSortKey(for: $0.title) < pastureSectionSortKey(for: $1.title) }

        default:
            return [AnimalSection(id: "all", title: "Animals", animals: animals)]
        }
    }

    static func shouldUseSections(for sortOrder: AnimalSortOrder) -> Bool {
        switch sortOrder {
        case .sex, .animalType, .status, .pasture:
            return true
        default:
            return false
        }
    }

    static func emptyStateConfiguration(
        items: [AnimalSummary],
        searchText: String,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool
    ) -> AnimalListEmptyStateConfiguration {
        let hasHiddenOffHerdAnimals = items.contains(where: { $0.status != .active && !$0.isArchived })
        let hasHiddenArchivedRecords = items.contains(where: \.isArchived)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if items.isEmpty {
            return .init(
                title: "No Animals Yet",
                description: "Add your first animal to start building the herd.",
                systemImage: "pawprint"
            )
        }

        if !trimmedSearch.isEmpty {
            return .init(
                title: "No Matches",
                description: "Try a different search or clear your text.",
                systemImage: "magnifyingglass"
            )
        }

        if filter.pasture == .noPasture {
            return .init(
                title: "No Animals Without a Pasture",
                description: "Every visible animal is currently assigned to a pasture.",
                systemImage: "map"
            )
        }

        if filter.isActive {
            return .init(
                title: "No Animals Match These Filters",
                description: "Adjust or clear the current filters to see more animals.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }

        if !showArchivedRecords && hasHiddenArchivedRecords && !showRemovedStatuses && !hasHiddenOffHerdAnimals {
            return .init(
                title: "Archived Records Hidden",
                description: "Archived records are currently hidden.",
                systemImage: "archivebox"
            )
        }

        if !showRemovedStatuses {
            return .init(
                title: "No Active Animals",
                description: "Off-herd animals are currently hidden.",
                systemImage: "person.3.sequence.fill"
            )
        }

        if !showArchivedRecords && hasHiddenArchivedRecords {
            return .init(
                title: "Archived Records Hidden",
                description: "Archived records are currently hidden.",
                systemImage: "archivebox"
            )
        }

        return .init(
            title: "Nothing to Show",
            description: "Try changing the current filters or sort.",
            systemImage: "tray"
        )
    }

    static func hasHiddenOffHerdAnimals(items: [AnimalSummary]) -> Bool {
        items.contains(where: { $0.status != .active && !$0.isArchived })
    }

    static func hasHiddenArchivedRecords(items: [AnimalSummary]) -> Bool {
        items.contains(where: \.isArchived)
    }


    private static func animalTypeSectionSortKey(for title: String) -> String {
        switch title {
        case AnimalType.calf.label:
            return "0-calf"
        case AnimalType.heifer.label:
            return "1-heifer"
        case AnimalType.steer.label:
            return "2-steer"
        case AnimalType.cow.label:
            return "3-cow"
        case AnimalType.bull.label:
            return "4-bull"
        default:
            return "9-\(title.lowercased())"
        }
    }

    private static func animalTypeSortKey(for animalType: AnimalType) -> String {
        animalTypeSectionSortKey(for: animalType.label)
    }

    private static func pastureSectionTitle(for animal: AnimalSummary) -> String {
        if animal.location == .workingPen {
            return "Working Pen"
        }

        if let pastureName = animal.pastureName, !pastureName.isEmpty {
            return pastureName
        }

        return "No Pasture"
    }

    private static func isNoPasture(_ animal: AnimalSummary) -> Bool {
        animal.location != .workingPen && animal.pastureID == nil
    }

    private static func pastureSectionSortKey(for title: String) -> String {
        switch title {
        case "Working Pen":
            return "0-working-pen"
        case "No Pasture":
            return "2-no-pasture"
        default:
            return "1-\(title.lowercased())"
        }
    }

    private static func pastureSortKey(for animal: AnimalSummary) -> String {
        pastureSectionSortKey(for: pastureSectionTitle(for: animal))
    }

    private static func tagAscending(_ lhs: AnimalSummary, _ rhs: AnimalSummary) -> Bool {
        lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
    }
}
