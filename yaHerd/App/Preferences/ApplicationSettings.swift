import Foundation
import Observation

@MainActor
@Observable
final class ApplicationSettings {
    nonisolated static let defaultTargetAcresPerHead = 3.0
    nonisolated static let defaultUsableAcreagePercent = 100
    nonisolated static let targetAcresPerHeadRange = 0.25...25.0
    nonisolated static let usableAcreagePercentRange = 10...100
    nonisolated static let maximumRecentPastures = 4

    @ObservationIgnored private let store: any ApplicationSettingsStore

    private var dashboardEnabledValue: Bool
    private var targetAcresPerHeadDefaultValue: Double
    private var usableAcreagePercentDefaultValue: Int
    private var recentPastureIDsValue: [UUID]
    private var homeDismissedSetupSuggestionIDsValue: Set<String>
    private var homeSetupSuggestionsExpandedValue: Bool
    private var legacyRecentPastureNamesValue: [String]

    convenience init() {
        self.init(store: UserDefaultsApplicationSettingsStore())
    }

    init(store: any ApplicationSettingsStore) {
        self.store = store
        ApplicationSettingsKeyMigrator.migrate(store: store)
        store.removeObject(forKey: ApplicationSettingKey.allowHardDelete.rawValue)

        self.dashboardEnabledValue = Self.decodeBool(
            store.object(forKey: ApplicationSettingKey.dashboardEnabled.rawValue),
            defaultValue: false
        )
        self.targetAcresPerHeadDefaultValue = Self.validatedTargetAcresPerHead(
            Self.decodeDouble(
                store.object(forKey: ApplicationSettingKey.targetAcresPerHeadDefault.rawValue),
                defaultValue: Self.defaultTargetAcresPerHead
            )
        )
        self.usableAcreagePercentDefaultValue = Self.validatedUsableAcreagePercent(
            Self.decodeInt(
                store.object(forKey: ApplicationSettingKey.usableAcreagePercentDefault.rawValue),
                defaultValue: Self.defaultUsableAcreagePercent
            )
        )
        self.recentPastureIDsValue = Self.validatedRecentPastureIDs(
            Self.decodeUUIDs(store.object(forKey: ApplicationSettingKey.recentPastureIDs.rawValue))
        )
        self.homeDismissedSetupSuggestionIDsValue = Self.validatedStringSet(
            Self.decodeStrings(
                store.object(forKey: ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue),
                legacySeparator: ","
            )
        )
        self.homeSetupSuggestionsExpandedValue = Self.decodeBool(
            store.object(forKey: ApplicationSettingKey.homeSetupSuggestionsExpanded.rawValue),
            defaultValue: true
        )
        self.legacyRecentPastureNamesValue = Self.decodeStrings(
            store.object(forKey: ApplicationSettingKey.legacyRecentPastureNames.rawValue),
            legacySeparator: "|"
        )

        persistNormalizedValues()
    }

    var allowHardDelete: Bool {
        false
    }

    var isDashboardEnabled: Bool {
        get { dashboardEnabledValue }
        set {
            guard dashboardEnabledValue != newValue else { return }
            dashboardEnabledValue = newValue
            persistChange(key: .dashboardEnabled, encodedValue: newValue)
        }
    }

    var targetAcresPerHeadDefault: Double {
        get { targetAcresPerHeadDefaultValue }
        set {
            let validatedValue = Self.validatedTargetAcresPerHead(newValue)
            guard targetAcresPerHeadDefaultValue != validatedValue else { return }
            targetAcresPerHeadDefaultValue = validatedValue
            persistChange(
                key: .targetAcresPerHeadDefault,
                encodedValue: validatedValue
            )
        }
    }

    var usableAcreagePercentDefault: Int {
        get { usableAcreagePercentDefaultValue }
        set {
            let validatedValue = Self.validatedUsableAcreagePercent(newValue)
            guard usableAcreagePercentDefaultValue != validatedValue else { return }
            usableAcreagePercentDefaultValue = validatedValue
            persistChange(
                key: .usableAcreagePercentDefault,
                encodedValue: validatedValue
            )
        }
    }

    var recentPastureIDs: [UUID] {
        get { recentPastureIDsValue }
        set {
            let validatedValue = Self.validatedRecentPastureIDs(newValue)
            guard recentPastureIDsValue != validatedValue else { return }
            recentPastureIDsValue = validatedValue
            persistChange(
                key: .recentPastureIDs,
                encodedValue: validatedValue.map(\.uuidString)
            )
        }
    }

    var homeDismissedSetupSuggestionIDs: Set<String> {
        get { homeDismissedSetupSuggestionIDsValue }
        set {
            let validatedValue = Self.validatedStringSet(newValue)
            guard homeDismissedSetupSuggestionIDsValue != validatedValue else { return }
            homeDismissedSetupSuggestionIDsValue = validatedValue
            persistChange(
                key: .homeDismissedSetupSuggestionIDs,
                encodedValue: validatedValue.sorted()
            )
        }
    }

    var isHomeSetupSuggestionsExpanded: Bool {
        get { homeSetupSuggestionsExpandedValue }
        set {
            guard homeSetupSuggestionsExpandedValue != newValue else { return }
            homeSetupSuggestionsExpandedValue = newValue
            persistChange(
                key: .homeSetupSuggestionsExpanded,
                encodedValue: newValue
            )
        }
    }

    var legacyRecentPastureNames: [String] {
        legacyRecentPastureNamesValue
    }

    func clearLegacyRecentPastureNames() {
        guard !legacyRecentPastureNamesValue.isEmpty else { return }
        legacyRecentPastureNamesValue = []
        store.removeObject(forKey: ApplicationSettingKey.legacyRecentPastureNames.rawValue)
    }

    func resetToDefaults() {
        isDashboardEnabled = false
        targetAcresPerHeadDefault = Self.defaultTargetAcresPerHead
        usableAcreagePercentDefault = Self.defaultUsableAcreagePercent
        recentPastureIDs = []
        homeDismissedSetupSuggestionIDs = []
        isHomeSetupSuggestionsExpanded = true
        clearLegacyRecentPastureNames()
        store.removeObject(forKey: ApplicationSettingKey.allowHardDelete.rawValue)
    }

    private func persistNormalizedValues() {
        for key in ApplicationSettingKey.allCases {
            guard let value = encodedValue(for: key) else {
                store.removeObject(forKey: key.rawValue)
                continue
            }
            if key == .legacyRecentPastureNames, legacyRecentPastureNamesValue.isEmpty {
                store.removeObject(forKey: key.rawValue)
            } else {
                store.set(value, forKey: key.rawValue)
            }
        }
    }

    private func encodedValue(for key: ApplicationSettingKey) -> Any? {
        switch key {
        case .allowHardDelete:
            nil
        case .dashboardEnabled:
            isDashboardEnabled
        case .targetAcresPerHeadDefault:
            targetAcresPerHeadDefault
        case .usableAcreagePercentDefault:
            usableAcreagePercentDefault
        case .recentPastureIDs:
            recentPastureIDs.map(\.uuidString)
        case .homeDismissedSetupSuggestionIDs:
            homeDismissedSetupSuggestionIDs.sorted()
        case .homeSetupSuggestionsExpanded:
            isHomeSetupSuggestionsExpanded
        case .legacyRecentPastureNames:
            legacyRecentPastureNames
        }
    }

    private func persistChange(
        key: ApplicationSettingKey,
        encodedValue: Any
    ) {
        store.set(encodedValue, forKey: key.rawValue)
    }

    private static func decodeBool(_ value: Any?, defaultValue: Bool) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: break
            }
        }
        return defaultValue
    }

    private static func decodeDouble(_ value: Any?, defaultValue: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String, let number = Double(value) { return number }
        return defaultValue
    }

    private static func decodeInt(_ value: Any?, defaultValue: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let number = Int(value) { return number }
        return defaultValue
    }

    private static func decodeUUIDs(_ value: Any?) -> [UUID] {
        let strings: [String]
        if let values = value as? [String] {
            strings = values
        } else if let value = value as? String {
            strings = value.split(separator: "|").map(String.init)
        } else {
            strings = []
        }
        return strings.compactMap(UUID.init(uuidString:))
    }

    private static func decodeStrings(_ value: Any?, legacySeparator: Character) -> Set<String> {
        if let values = value as? [String] {
            return Set(values)
        }
        if let value = value as? String {
            return Set(value.split(separator: legacySeparator).map(String.init))
        }
        return []
    }

    private static func decodeStrings(_ value: Any?, legacySeparator: Character) -> [String] {
        let values: [String]
        if let storedValues = value as? [String] {
            values = storedValues
        } else if let storedValue = value as? String {
            values = storedValue.split(separator: legacySeparator).map(String.init)
        } else {
            values = []
        }

        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func validatedTargetAcresPerHead(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTargetAcresPerHead }
        return min(max(value, targetAcresPerHeadRange.lowerBound), targetAcresPerHeadRange.upperBound)
    }

    private static func validatedUsableAcreagePercent(_ value: Int) -> Int {
        min(max(value, usableAcreagePercentRange.lowerBound), usableAcreagePercentRange.upperBound)
    }

    private static func validatedRecentPastureIDs(_ values: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0).inserted }.prefix(maximumRecentPastures).map { $0 }
    }

    private static func validatedStringSet(_ values: Set<String>) -> Set<String> {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(64)
        )
    }
}
