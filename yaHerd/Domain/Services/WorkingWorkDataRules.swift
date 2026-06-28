import Foundation

enum WorkingWorkDataRules {
    static func shouldRecordPregnancyCheck(_ input: WorkingPregnancyCheckInput?) -> Bool {
        guard let input else { return false }
        return input.result == .open || input.result == .pregnant
    }

    static func normalizedObservationNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
