import SwiftUI

extension HomeView {
    var snapshot: HomeSnapshot? {
        viewModel.snapshot
    }

    var activeSession: DashboardWorkingSessionSummary? {
        snapshot?.activeSession
    }

    var alerts: [DashboardAlert] {
        snapshot?.alerts ?? []
    }

    var openFindings: [FieldCheckFindingSnapshot] {
        snapshot?.openFindings ?? []
    }

    var flaggedCheckSessions: [FieldCheckSessionSummary] {
        snapshot?.flaggedCheckSessions ?? []
    }

    var flaggedCheckAnimalCount: Int {
        snapshot?.flaggedCheckAnimalCount ?? 0
    }

    var activeAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.activeAnimalRecords ?? []
    }

    var calvingWatchAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.calvingWatchAnimalRecords ?? []
    }

    var overduePregnancyCheckAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.overduePregnancyCheckAnimalRecords ?? []
    }

    var overdueTreatmentAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.overdueTreatmentAnimalRecords ?? []
    }

    var pastureAssignedAnimalCount: Int {
        snapshot?.pastureAssignedAnimalCount ?? 0
    }

    var pastureCheckDueItems: [HomePastureCheckDueItem] {
        snapshot?.pastureCheckDueItems ?? []
    }


    var activeCheckSessions: [FieldCheckSessionSummary] {
        snapshot?.activeCheckSessions ?? []
    }

    var missingCheckSessions: [FieldCheckSessionSummary] {
        snapshot?.missingCheckSessions ?? []
    }

    var missingCheckAnimalCount: Int {
        snapshot?.missingCheckAnimalCount ?? 0
    }

    var workingPenCount: Int {
        snapshot?.workingPenCount ?? 0
    }

    var workingPenAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.workingPenAnimalRecords ?? []
    }

    var overstockedPastures: [DashboardPastureItem] {
        snapshot?.overstockedPastures ?? []
    }

    var rotationReadyPastures: [DashboardPastureItem] {
        snapshot?.rotationReadyPastures ?? []
    }

    var underutilizedPastures: [DashboardPastureItem] {
        snapshot?.underutilizedPastures ?? []
    }

    var pasturesMissingStockingData: [DashboardPastureItem] {
        snapshot?.pasturesMissingStockingData ?? []
    }

    var unassignedAnimalRecords: [DashboardAnimalRecord] {
        snapshot?.unassignedAnimalRecords ?? []
    }

    var missingTagAnimals: [DashboardAnimalRecord] {
        snapshot?.missingTagAnimals ?? []
    }


    var unknownSexAnimals: [DashboardAnimalRecord] {
        snapshot?.unknownSexAnimals ?? []
    }

    var archivedActiveRecords: [DashboardAnimalRecord] {
        snapshot?.archivedActiveRecords ?? []
    }

    var fieldWorkCardCount: Int {
        snapshot?.fieldWorkCardCount ?? 0
    }

    var pastureOperationsCardCount: Int {
        snapshot?.pastureOperationsCardCount ?? 0
    }

    var recordsCleanupCardCount: Int {
        snapshot?.recordsCleanupCardCount ?? 0
    }

    var continueCardCount: Int {
        snapshot?.continueCardCount ?? 0
    }

    var continueCardSubtitle: String {
        guard let snapshot else { return "Loading current work" }
        if activeSession != nil { return "Resume session" }
        if !activeCheckSessions.isEmpty { return "Finish check" }
        if workingPenCount > 0 { return "Clear pen" }
        if !snapshot.openFindings.isEmpty { return "Resolve finding" }
        return "Start work"
    }

    var alertSummarySubtitle: String {
        guard snapshot != nil else { return "Loading alerts" }
        guard !alerts.isEmpty else { return "No current alerts" }

        let criticalCount = alerts.filter { $0.severity == .critical }.count
        let warningCount = alerts.filter { $0.severity == .warning }.count

        if criticalCount > 0 {
            return "\(criticalCount) critical · \(warningCount) warnings"
        }

        if warningCount > 0 {
            return warningCount == 1 ? "1 warning" : "\(warningCount) warnings"
        }

        return alerts.count == 1 ? "1 informational alert" : "\(alerts.count) informational alerts"
    }

    var alertTint: Color {
        if alerts.contains(where: { $0.severity == .critical }) { return .red }
        if alerts.contains(where: { $0.severity == .warning }) { return .orange }
        return alerts.isEmpty ? .green : .blue
    }

    var hasFieldWorkRows: Bool {
        snapshot?.hasFieldWorkRows ?? false
    }

    var shouldShowUnfinishedChecksRow: Bool {
        snapshot?.shouldShowUnfinishedChecksRow ?? false
    }

    var shouldShowWorkingPenAnimalsRow: Bool {
        snapshot?.shouldShowWorkingPenAnimalsRow ?? false
    }

    var shouldShowOpenFindingsRow: Bool {
        snapshot?.shouldShowOpenFindingsRow ?? false
    }

    var unassignedAnimalCount: Int {
        unassignedAnimalRecords.count
    }

    var hasPastureOperationRows: Bool {
        snapshot?.hasPastureOperationRows ?? false
    }

    var hasRecordsCleanupRows: Bool {
        snapshot?.hasRecordsCleanupRows ?? false
    }

    var hasSetupSuggestionRows: Bool {
        !visibleSetupSuggestionIDs.isEmpty
    }

    var visibleSetupSuggestionIDs: [HomeSetupSuggestionID] {
        guard let snapshot else { return [] }
        return HomeSetupSuggestionPolicy().visibleSuggestionIDs(
            snapshot: snapshot,
            context: setupSuggestionContext
        )
    }

    var setupSuggestionContext: HomeSetupSuggestionContext {
        HomeSetupSuggestionContext(
            isDashboardEnabled: isDashboardEnabled,
            syncMode: syncMode,
            customTagColorCount: customTagColorCount,
            dismissedIDs: dismissedSetupSuggestionIDs
        )
    }

    var dismissedSetupSuggestionIDs: Set<String> {
        Set(
            dismissedSetupSuggestionIDsRaw
                .split(separator: ",")
                .map { String($0) }
        )
    }

    var customTagColorCount: Int {
        tagColorLibrary.colors.filter { !TagColorLibraryStore.defaultColorIDs.contains($0.id) }.count
    }

    var syncMode: SyncMode {
        SyncMode(rawValue: syncModeRawValue) ?? .localOnly
    }
}
