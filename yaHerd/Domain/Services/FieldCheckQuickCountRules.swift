import Foundation

struct FieldCheckQuickCountRosterEntry: Hashable {
    let animalType: AnimalType
    let wasExpectedAtStart: Bool
    let wasCounted: Bool
    let isMissing: Bool
}

enum FieldCheckQuickCountRules {
    static func individuallyVerifiedCount(in rosterEntries: [FieldCheckQuickCountRosterEntry]) -> Int {
        rosterEntries.filter { entry in
            entry.wasExpectedAtStart && entry.wasCounted
        }.count
    }

    static func availableQuickCountCapacity(for rosterEntries: [FieldCheckQuickCountRosterEntry]) -> [AnimalType: Int] {
        rosterEntries.reduce(into: zeroCounts()) { result, entry in
            guard entry.wasExpectedAtStart, !entry.wasCounted, !entry.isMissing else { return }
            result[entry.animalType, default: 0] += 1
        }
    }

    static func normalizedCounts(
        _ counts: [AnimalType: Int],
        rosterEntries: [FieldCheckQuickCountRosterEntry]
    ) -> [AnimalType: Int] {
        let capacityByType = availableQuickCountCapacity(for: rosterEntries)

        return AnimalType.allCases.reduce(into: zeroCounts()) { result, animalType in
            let requestedCount = max(counts[animalType, default: 0], 0)
            let availableCount = max(capacityByType[animalType, default: 0], 0)
            result[animalType] = min(requestedCount, availableCount)
        }
    }

    static func totalSeen(
        quickCounts: [AnimalType: Int],
        rosterEntries: [FieldCheckQuickCountRosterEntry]
    ) -> Int {
        let verifiedCount = individuallyVerifiedCount(in: rosterEntries)
        let normalizedQuickCountTotal = normalizedCounts(
            quickCounts,
            rosterEntries: rosterEntries
        )
        .values
        .reduce(0, +)

        return verifiedCount + normalizedQuickCountTotal
    }

    static func zeroCounts() -> [AnimalType: Int] {
        AnimalType.allCases.reduce(into: [:]) { result, animalType in
            result[animalType] = 0
        }
    }
}

extension FieldCheckAnimalCheckSnapshot {
    var quickCountRosterEntry: FieldCheckQuickCountRosterEntry {
        FieldCheckQuickCountRosterEntry(
            animalType: animalType,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            isMissing: isMissing
        )
    }
}
