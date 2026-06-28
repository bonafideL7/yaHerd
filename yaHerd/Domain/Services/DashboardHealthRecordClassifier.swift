import Foundation

struct DashboardHealthRecordClassifier {
    func category(for treatment: String) -> String {
        let cleaned = treatment.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.lowercased()

        guard !normalized.isEmpty else { return "Unspecified" }

        if containsAny(normalized, ["pinkeye", "pink eye"]) { return "Pink eye" }
        if containsAny(normalized, ["foot", "hoof"]) { return "Foot/hoof" }
        if containsAny(normalized, ["vaccine", "vaccination", "shot"]) { return "Vaccination" }
        if containsAny(normalized, ["worm", "parasite"]) { return "Deworming" }
        if containsAny(normalized, ["castrat", "band"]) { return "Castration/banding" }
        if containsAny(normalized, ["antibiotic", "biotic"]) { return "Antibiotic" }

        return cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: " ")
            .capitalized
    }

    func isPinkEyeRecord(_ record: DashboardHealthRecord) -> Bool {
        let searchableText = [record.treatment, record.notes ?? ""]
            .joined(separator: " ")
            .lowercased()

        return containsAny(searchableText, ["pinkeye", "pink eye"])
    }

    private func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }
}
