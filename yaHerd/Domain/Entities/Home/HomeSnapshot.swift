import Foundation

struct HomeSnapshot: Equatable {
    let activeSession: DashboardWorkingSessionSummary?
    let alerts: [DashboardAlert]
    let activeAnimalRecords: [DashboardAnimalRecord]
    let activeCheckSessions: [FieldCheckSessionSummary]
    let openFindings: [FieldCheckFindingSnapshot]
    let flaggedCheckSessions: [FieldCheckSessionSummary]
    let missingCheckSessions: [FieldCheckSessionSummary]
    let pastureCheckStartPastures: [DashboardPastureItem]
    let workingPenAnimalRecords: [DashboardAnimalRecord]
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

    var pastureAssignedAnimalCount: Int {
        activeAnimalRecords.filter { $0.location == .pasture && $0.pastureID != nil }.count
    }

    var shouldShowUnfinishedChecksRow: Bool {
        !activeCheckSessions.isEmpty
    }

    var shouldShowWorkingPenAnimalsRow: Bool {
        workingPenCount > 0
    }

    var shouldShowOpenFindingsRow: Bool {
        !openFindings.isEmpty
    }

    var hasFieldWorkRows: Bool {
        shouldShowUnfinishedChecksRow
            || shouldShowOpenFindingsRow
            || flaggedCheckAnimalCount > 0
            || missingCheckAnimalCount > 0
    }

    var hasPastureOperationRows: Bool {
        !rotationReadyPastures.isEmpty
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

