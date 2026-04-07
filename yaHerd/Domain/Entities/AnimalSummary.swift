import Foundation

struct AnimalSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let isArchived: Bool
    let pastureID: UUID?
    let pastureName: String?
    let location: AnimalLocation

    var age: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let birth = calendar.startOfDay(for: birthDate)

        guard birth <= today else { return "1 day" }

        let yearMonth = calendar.dateComponents([.year, .month], from: birth, to: today)
        if let y = yearMonth.year, y >= 1 {
            let m = yearMonth.month ?? 0
            if m > 0 {
                return "\(y)yr \(m)mo"
            } else {
                return y == 1 ? "1yr" : "\(y)yr"
            }
        }

        let months = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        if months >= 1 {
            return months == 1 ? "1mo" : "\(months)mo"
        }

        let weekDay = calendar.dateComponents([.weekOfYear, .day], from: birth, to: today)
        let w = weekDay.weekOfYear ?? 0
        let d = weekDay.day ?? 0

        if w >= 1 {
            if d > 0 {
                let weekText = w == 1 ? "1 wk" : "\(w) wks"
                let dayText = d == 1 ? "1 day" : "\(d) days"
                return "\(weekText) \(dayText)"
            } else {
                return w == 1 ? "1 wk" : "\(w) wks"
            }
        }

        let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        let dayCount = max(days, 1)
        return dayCount == 1 ? "1 day" : "\(dayCount) days"
    }
}
