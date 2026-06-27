import Foundation

enum AnimalAgeFormatter {
    enum Style: Equatable {
        case standard
        case compact
    }

    static func ageInMonths(
        from birthDate: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard birthDate <= now else { return 0 }
        let components = calendar.dateComponents([.month], from: birthDate, to: now)
        return max(0, components.month ?? 0)
    }

    static func string(
        from birthDate: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        style: Style = .standard
    ) -> String {
        let today = calendar.startOfDay(for: now)
        let birth = calendar.startOfDay(for: birthDate)

        guard birth <= today else {
            return style == .compact ? "1d" : "1 day"
        }

        let yearMonth = calendar.dateComponents([.year, .month], from: birth, to: today)
        if let years = yearMonth.year, years >= 1 {
            let months = yearMonth.month ?? 0
            return formattedYears(years, months: months, style: style)
        }

        let months = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        if months >= 1 {
            return formattedMonths(months, style: style)
        }

        if style == .compact {
            let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
            return "\(max(days, 1))d"
        }

        let weekDay = calendar.dateComponents([.weekOfYear, .day], from: birth, to: today)
        let weeks = weekDay.weekOfYear ?? 0
        let days = weekDay.day ?? 0

        if weeks >= 1 {
            if days > 0 {
                return "\(formattedWeeks(weeks)) \(formattedDays(days))"
            }
            return formattedWeeks(weeks)
        }

        let totalDays = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        return formattedDays(max(totalDays, 1))
    }

    private static func formattedYears(_ years: Int, months: Int, style: Style) -> String {
        switch style {
        case .compact:
            return months > 0 ? "\(years)y \(months)m" : "\(years)y"
        case .standard:
            guard months > 0 else { return years == 1 ? "1yr" : "\(years)yr" }
            return "\(years)yr \(months)mo"
        }
    }

    private static func formattedMonths(_ months: Int, style: Style) -> String {
        switch style {
        case .compact:
            return "\(months)m"
        case .standard:
            return months == 1 ? "1mo" : "\(months)mo"
        }
    }

    private static func formattedWeeks(_ weeks: Int) -> String {
        weeks == 1 ? "1 wk" : "\(weeks) wks"
    }

    private static func formattedDays(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}
