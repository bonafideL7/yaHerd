nonisolated enum ApplicationSettingKey: String, CaseIterable, Sendable {
    case dashboardEnabled = "settings.dashboardEnabled"
    case dashboardHiddenSections = "settings.dashboardHiddenSections"
    case hardDeleteAnimals = "settings.hardDeleteAnimals"
    case inlineAnimalEditingEnabled = "settings.inlineAnimalEditingEnabled"
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
        case .dashboardHiddenSections:
            []
        case .hardDeleteAnimals:
            []
        case .inlineAnimalEditingEnabled:
            []
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
}
