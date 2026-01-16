//
//  DashboardAlert.swift
//  yaHerd
//
//  Created by mm on 12/2/25.
//


import Foundation

struct DashboardAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let icon: String
    let severity: AlertSeverity
    /// Optional navigation target used by the dashboard UI.
    let destination: DashboardAlertDestination?

    var severityOrder: Int {
        severity.severityOrder
    }
}

enum DashboardAlertDestination: Hashable {
    case animal(Animal)
    case pasture(Pasture)
    case animalList(DashboardAnimalListKind)
}

enum DashboardAnimalListKind: String, Hashable {
    case alive
    case workingPen
    case unassigned
    case overduePregChecks
    case overdueTreatments

    var title: String {
        switch self {
        case .alive: return "Alive"
        case .workingPen: return "Working Pen"
        case .unassigned: return "Unassigned"
        case .overduePregChecks: return "Overdue Pregnancy Checks"
        case .overdueTreatments: return "Overdue Treatments"
        }
    }
}

enum AlertSeverity {
    case info
    case warning
    case critical
}

extension AlertSeverity {
    var severityOrder: Int {
        switch self {
        case .critical: return 3
        case .warning: return 2
        case .info: return 1
        }
    }
}
