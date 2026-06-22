import Foundation

struct HomeSetupSuggestionContext: Equatable {
    let isDashboardEnabled: Bool
    let syncMode: SyncMode
    let customTagColorCount: Int
    let dismissedIDs: Set<String>
}

enum HomeSetupSuggestionID: String, CaseIterable, Hashable {
    case addFirstPasture
    case addFirstAnimal
    case startFirstPastureCheck
    case createWorkingProtocol
    case enableDashboard
    case customizeTagColors
    case completePastureStockingData
    case reviewSyncSetup
}

struct HomeSetupSuggestionPolicy {
    func visibleSuggestionIDs(
        snapshot: HomeSnapshot,
        context: HomeSetupSuggestionContext
    ) -> [HomeSetupSuggestionID] {
        var ids: [HomeSetupSuggestionID] = []

        if !snapshot.hasPastures { ids.append(.addFirstPasture) }
        if !snapshot.hasActiveAnimals { ids.append(.addFirstAnimal) }
        if snapshot.hasPastures && !snapshot.hasFieldCheckHistory { ids.append(.startFirstPastureCheck) }
        if !snapshot.hasWorkingProtocolTemplates && snapshot.hasPastures && snapshot.hasActiveAnimals { ids.append(.createWorkingProtocol) }
        if !context.isDashboardEnabled { ids.append(.enableDashboard) }
        if context.customTagColorCount == 0 { ids.append(.customizeTagColors) }
        if !snapshot.pasturesMissingStockingData.isEmpty { ids.append(.completePastureStockingData) }
        if context.syncMode == .localOnly { ids.append(.reviewSyncSetup) }

        return ids.filter { !context.dismissedIDs.contains($0.rawValue) }
    }
}
