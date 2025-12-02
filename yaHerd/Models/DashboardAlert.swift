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

    var severityOrder: Int {
        severity.severityOrder
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
