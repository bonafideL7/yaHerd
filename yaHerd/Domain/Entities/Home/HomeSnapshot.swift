import Foundation

struct HomeSnapshot: Equatable {
    let activeSession: DashboardWorkingSessionSummary?
    let activeCheckSessions: [FieldCheckSessionSummary]
    let openFindings: [FieldCheckFindingSnapshot]
    let flaggedCheckSessions: [FieldCheckSessionSummary]
    let missingCheckSessions: [FieldCheckSessionSummary]
    let pastureCheckDueItems: [HomePastureCheckDueItem]
    let workingPenAnimalRecords: [DashboardAnimalRecord]
    let overstockedPastures: [DashboardPastureItem]
    let rotationReadyPastures: [DashboardPastureItem]
    let underutilizedPastures: [DashboardPastureItem]
    let pasturesMissingStockingData: [DashboardPastureItem]
    let unassignedAnimalRecords: [DashboardAnimalRecord]
    let missingTagAnimals: [DashboardAnimalRecord]
    let unknownSexAnimals: [DashboardAnimalRecord]
    let archivedActiveRecords: [DashboardAnimalRecord]
    let hasPastures: Bool
    let hasActiveAnimals: Bool
    let hasFieldCheckHistory: Bool
    let hasWorkingProtocolTemplates: Bool

    var flaggedCheckAnimalCount: Int {
        flaggedCheckSessions.reduce(0) { $0 + $1.flaggedAnimalCount }
    }

    var missingCheckAnimalCount: Int {
        missingCheckSessions.reduce(0) { $0 + $1.missingAnimalCount }
    }

    var workingPenCount: Int {
        workingPenAnimalRecords.count
    }

    var fieldWorkCardCount: Int {
        activeCheckSessions.count
            + pastureCheckDueItems.count
            + openFindings.count
            + flaggedCheckAnimalCount
            + missingCheckAnimalCount
    }

    var pastureOperationsCardCount: Int {
        overstockedPastures.count
            + rotationReadyPastures.count
            + underutilizedPastures.count
            + pasturesMissingStockingData.count
    }

    var recordsCleanupCardCount: Int {
        unassignedAnimalRecords.count
            + missingTagAnimals.count
            + unknownSexAnimals.count
            + archivedActiveRecords.count
    }

    var hasCurrentWork: Bool {
        activeSession != nil
            || !activeCheckSessions.isEmpty
            || workingPenCount > 0
            || !openFindings.isEmpty
    }

    var continueCardCount: Int {
        hasCurrentWork ? 1 : 0
    }

    var shouldShowUnfinishedChecksRow: Bool {
        guard !activeCheckSessions.isEmpty else { return false }
        return !(activeSession == nil && activeCheckSessions.count == 1)
    }

    var shouldShowWorkingPenAnimalsRow: Bool {
        guard workingPenCount > 0 else { return false }
        return !(activeSession == nil && activeCheckSessions.isEmpty)
    }

    var shouldShowOpenFindingsRow: Bool {
        let openFindingCount = openFindings.count
        guard openFindingCount > 0 else { return false }
        return !(activeSession == nil && activeCheckSessions.isEmpty && workingPenCount == 0 && openFindingCount == 1)
    }

    var hasFieldWorkRows: Bool {
        shouldShowUnfinishedChecksRow
            || shouldShowOpenFindingsRow
            || flaggedCheckAnimalCount > 0
            || missingCheckAnimalCount > 0
            || !pastureCheckDueItems.isEmpty
    }

    var hasPastureOperationRows: Bool {
        !overstockedPastures.isEmpty
            || !rotationReadyPastures.isEmpty
            || !underutilizedPastures.isEmpty
            || !pasturesMissingStockingData.isEmpty
    }

    var hasRecordsCleanupRows: Bool {
        !unassignedAnimalRecords.isEmpty
            || !missingTagAnimals.isEmpty
            || !unknownSexAnimals.isEmpty
            || !archivedActiveRecords.isEmpty
    }

}

struct HomePastureCheckDueItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let activeAnimalCount: Int
    let lastCheckDate: Date?
}
