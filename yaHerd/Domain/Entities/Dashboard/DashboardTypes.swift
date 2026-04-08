import Foundation

struct DashboardConfiguration: Equatable, Hashable {
    var pregnancyCheckIntervalDays: Int
    var treatmentIntervalDays: Int
    var enablePastureOverstockWarnings: Bool
    var fallbackPastureCapacity: Int
}

enum DashboardAnimalListKind: String, Hashable {
    case active
    case workingPen
    case unassigned
    case overduePregChecks
    case overdueTreatments

    var title: String {
        switch self {
        case .active:
            return "Active"
        case .workingPen:
            return "Working Pen"
        case .unassigned:
            return "Unassigned"
        case .overduePregChecks:
            return "Overdue Pregnancy Checks"
        case .overdueTreatments:
            return "Overdue Treatments"
        }
    }
}

enum DashboardPastureFilter: CaseIterable, Hashable {
    case all
    case overstocked
    case underutilized

    var label: String {
        switch self {
        case .all:
            return "All"
        case .overstocked:
            return "Over"
        case .underutilized:
            return "Low"
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
