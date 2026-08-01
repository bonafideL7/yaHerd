import Foundation

struct DashboardConfiguration: Equatable, Hashable, Sendable {}


enum DashboardAnimalListKind: String, Hashable, Codable, Sendable {
    case active
    case workingPen
    case unassigned

    var title: String {
        switch self {
        case .active:
            return "Active"
        case .workingPen:
            return "Working Pen"
        case .unassigned:
            return "Unassigned"
        }
    }
}

enum DashboardPastureFilter: CaseIterable, Hashable, Sendable {
    case all
    case underutilized
    case rotationReady

    var label: String {
        switch self {
        case .all:
            return "All"
        case .underutilized:
            return "Low"
        case .rotationReady:
            return "Ready"
        }
    }
}

enum DashboardAlertSeverity: Hashable, Sendable {
    case info
    case warning
    case critical

    var severityOrder: Int {
        switch self {
        case .critical:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }
}

enum DashboardNavigationTarget: Hashable, Sendable {
    case animal(UUID)
    case pasture(UUID)
    case animalList(DashboardAnimalListKind)
    case pastureList
}

enum DashboardPregnancyStatus: Hashable, Sendable {
    case open
    case pregnant
    case unknown
}
