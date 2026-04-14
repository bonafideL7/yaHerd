import Foundation

struct GrazingRotationService {
    static func isPastureRested(lastGrazedDate: Date?, restDays: Int?, asOf date: Date = .now) -> Bool {
        guard let lastGrazedDate, let restDays else { return true }
        let days = Calendar.current.dateComponents([.day], from: lastGrazedDate, to: date).day ?? 0
        return days >= restDays
    }
}
