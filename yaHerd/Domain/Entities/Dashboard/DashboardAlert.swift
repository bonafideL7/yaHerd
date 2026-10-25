import Foundation

struct DashboardAlert: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let message: String?
    let icon: String
    let severity: DashboardAlertSeverity
    let destination: DashboardNavigationTarget?

    init(
        id: UUID = UUID(),
        title: String,
        message: String?,
        icon: String,
        severity: DashboardAlertSeverity,
        destination: DashboardNavigationTarget?
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.icon = icon
        self.severity = severity
        self.destination = destination
    }

    var severityOrder: Int {
        severity.severityOrder
    }
}
