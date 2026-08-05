import Foundation

nonisolated enum ApplicationSettingScope: String, Sendable {
    case local
    case synchronized
}

nonisolated enum ApplicationSettingKey: String, CaseIterable, Sendable {
    case syncMode = "settings.syncMode"
    case allowHardDelete = "settings.allowHardDelete"
    case dashboardEnabled = "settings.dashboardEnabled"
    case targetAcresPerHeadDefault = "settings.targetAcresPerHeadDefault"
    case usableAcreagePercentDefault = "settings.usableAcreagePercentDefault"
    case recentPastureIDs = "settings.recentPastureIDs"
    case homeDismissedSetupSuggestionIDs = "settings.homeDismissedSetupSuggestionIDs"
    case homeSetupSuggestionsExpanded = "settings.homeSetupSuggestionsExpanded"
    case legacyRecentPastureNames = "settings.legacy.recentPastureNames"

    var scope: ApplicationSettingScope {
        switch self {
        case .dashboardEnabled,
             .targetAcresPerHeadDefault,
             .usableAcreagePercentDefault,
             .homeDismissedSetupSuggestionIDs:
            .synchronized

        case .syncMode,
             .allowHardDelete,
             .recentPastureIDs,
             .homeSetupSuggestionsExpanded,
             .legacyRecentPastureNames:
            .local
        }
    }

    var legacyKeys: [String] {
        switch self {
        case .syncMode:
            ["syncMode"]
        case .allowHardDelete:
            ["allowHardDelete"]
        case .dashboardEnabled:
            ["isDashboardEnabled"]
        case .targetAcresPerHeadDefault:
            ["targetAcresPerHeadDefault"]
        case .usableAcreagePercentDefault:
            ["usableAcreagePercentDefault"]
        case .recentPastureIDs:
            ["recentPastureIDs"]
        case .homeDismissedSetupSuggestionIDs:
            ["homeDismissedSetupSuggestionIDs"]
        case .homeSetupSuggestionsExpanded:
            ["homeSetupSuggestionsExpanded"]
        case .legacyRecentPastureNames:
            ["recentPastureNames"]
        }
    }
}

nonisolated enum ApplicationSettingsCatalog {
    static let currentSchemaVersion = 1
    static let schemaVersionKey = "settings.schemaVersion"

    static let synchronizedKeys = ApplicationSettingKey.allCases.filter {
        $0.scope == .synchronized
    }

    static let localKeys = ApplicationSettingKey.allCases.filter {
        $0.scope == .local
    }

    static let deprecatedCloudKeys = [
        ApplicationSettingKey.allowHardDelete.rawValue,
        "allowHardDelete",
        "recentPastureNames",
    ]
}
