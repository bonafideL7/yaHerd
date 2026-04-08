import Foundation

struct DashboardAlert: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String?
    let icon: String
    let severity: DashboardAlertSeverity
    let destination: DashboardNavigationTarget?

    var severityOrder: Int {
        severity.severityOrder
    }
}
