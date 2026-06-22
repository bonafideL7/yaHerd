import Foundation

struct DashboardConfiguration: Equatable, Hashable {}


enum DashboardAnimalListKind: String, Hashable {
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

enum DashboardPastureFilter: CaseIterable, Hashable {
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

enum DashboardAlertSeverity: Hashable {
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

enum DashboardNavigationTarget: Hashable {
    case animal(UUID)
    case pasture(UUID)
    case animalList(DashboardAnimalListKind)
    case pastureList
}

enum DashboardPregnancyStatus: Hashable {
    case open
    case pregnant
    case unknown
}
