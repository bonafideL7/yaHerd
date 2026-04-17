import Foundation

struct AnimalEditorContext: Hashable {
    enum Kind: Hashable {
        case standard
        case offspring(OffspringMetadata)
    }

    struct OffspringMetadata: Hashable {
        let damDisplayName: String
        let pastureName: String?
        let inferredSireDisplayName: String?

        var inferredSireHelperText: String? {
            guard let inferredSireDisplayName else { return nil }
            if let pastureName, !pastureName.isEmpty {
                return "Sire was inferred as \(inferredSireDisplayName), the only active bull in \(pastureName)."
            }
            return "Sire was inferred as \(inferredSireDisplayName), the only active bull in the same pasture."
        }
    }

    enum DateQuickSelection: String, Hashable, CaseIterable, Identifiable {
        case today
        case yesterday
        case oneWeekAgo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .oneWeekAgo: return "1 Week Ago"
            }
        }

        func resolvedDate(now: Date = .now, calendar: Calendar = .current) -> Date {
            let startOfToday = calendar.startOfDay(for: now)
            switch self {
            case .today:
                return startOfToday
            case .yesterday:
                return calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            case .oneWeekAgo:
                return calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            }
        }
    }

    let kind: Kind

    static let standard = AnimalEditorContext(kind: .standard)

    var offspringMetadata: OffspringMetadata? {
        guard case let .offspring(metadata) = kind else { return nil }
        return metadata
    }

    var birthDateQuickSelections: [DateQuickSelection] {
        switch kind {
        case .standard:
            return []
        case .offspring:
            return [.today, .yesterday, .oneWeekAgo]
        }
    }
}
