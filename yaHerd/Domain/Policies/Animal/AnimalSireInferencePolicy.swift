import Foundation

struct AnimalSireCandidate: Hashable {
    let id: UUID
    let pastureID: UUID?
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let isArchived: Bool
    let animalType: AnimalType
}

struct AnimalSireInferencePolicy {
    func inferSireID(
        from candidates: [AnimalSireCandidate],
        pastureID: UUID,
        excluding excludedAnimalID: UUID?,
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> UUID? {
        let oldestBullBirthDate = calendar.date(
            byAdding: .month,
            value: -AnimalTypeClassifier.calfAgeThresholdInMonths,
            to: date
        ) ?? date

        let eligibleCandidates = candidates.filter { candidate in
            candidate.pastureID == pastureID
                && candidate.status == .active
                && !candidate.isArchived
                && candidate.sex == .male
                && candidate.birthDate <= oldestBullBirthDate
                && candidate.id != excludedAnimalID
                && candidate.animalType == .bull
        }

        return eligibleCandidates.count == 1 ? eligibleCandidates[0].id : nil
    }
}
