nonisolated enum ApplicationSettingKey: String, CaseIterable, Sendable {
    case dashboardEnabled = "settings.dashboardEnabled"
    case hardDeleteAnimals = "settings.hardDeleteAnimals"
    case targetAcresPerHeadDefault = "settings.targetAcresPerHeadDefault"
    case usableAcreagePercentDefault = "settings.usableAcreagePercentDefault"
    case recentPastureIDs = "settings.recentPastureIDs"
    case homeDismissedSetupSuggestionIDs = "settings.homeDismissedSetupSuggestionIDs"
    case homeSetupSuggestionsExpanded = "settings.homeSetupSuggestionsExpanded"
    case legacyRecentPastureNames = "settings.legacy.recentPastureNames"

    var legacyKeys: [String] {
        switch self {
        case .dashboardEnabled:
            ["isDashboardEnabled"]
        case .hardDeleteAnimals:
            ["hardDeleteAnimals", "hardDeleteEnabled", "useHardDelete"]
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
    static let currentSchemaVersion = 2
    static let schemaVersionKey = "settings.schemaVersion"
}
