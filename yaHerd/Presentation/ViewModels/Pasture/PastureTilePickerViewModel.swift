import Foundation
import Observation

@MainActor
@Observable
final class PastureTilePickerViewModel {
    private(set) var pastures: [PastureSummary] = []
    private(set) var recentPastures: [PastureSummary] = []
    var errorMessage: String?

    private var recentPastureIDs: [UUID] = []

    func load(
        using repository: any PastureListReader,
        recentPastureIDs: [UUID],
        legacyRecentPastureNames: [String]
    ) -> [UUID]? {
        do {
            pastures = try repository.fetchPastures()
            errorMessage = nil
            return configureRecentPastures(
                recentPastureIDs: recentPastureIDs,
                legacyRecentPastureNames: legacyRecentPastureNames
            )
        } catch {
            pastures = []
            recentPastures = []
            errorMessage = UserVisibleErrorMessage.make(error)
            return nil
        }
    }

    @discardableResult
    func configureRecentPastures(
        recentPastureIDs: [UUID],
        legacyRecentPastureNames: [String]
    ) -> [UUID]? {
        if recentPastureIDs.isEmpty, !legacyRecentPastureNames.isEmpty {
            self.recentPastureIDs = RecentPasturesStore.migrateNames(
                legacyRecentPastureNames,
                using: pastures
            )
            refreshRecentPastures()
            return self.recentPastureIDs
        }

        self.recentPastureIDs = recentPastureIDs
        refreshRecentPastures()
        return nil
    }

    func select(_ pasture: PastureSummary) -> [UUID] {
        recentPastureIDs.removeAll { $0 == pasture.id }
        recentPastureIDs.insert(pasture.id, at: 0)
        recentPastureIDs = Array(recentPastureIDs.prefix(RecentPasturesStore.maximumRecentPastures))
        refreshRecentPastures()
        return recentPastureIDs
    }

    private func refreshRecentPastures() {
        recentPastures = recentPastureIDs.compactMap { id in
            pastures.first { $0.id == id }
        }
    }
}

private enum RecentPasturesStore {
    static let maximumRecentPastures = ApplicationSettings.maximumRecentPastures

    static func migrateNames(_ names: [String], using pastures: [PastureSummary]) -> [UUID] {
        var ids: [UUID] = []

        for name in names {
            guard let pasture = pastures.first(where: { $0.name == name }),
                  !ids.contains(pasture.id) else {
                continue
            }
            ids.append(pasture.id)
        }

        return Array(ids.prefix(maximumRecentPastures))
    }
}
