import Foundation
import Observation

/// Coordinates the one selected Herd used by every repository and the scene router.
/// Listing failures never destroy a previously coherent selection.
@MainActor
@Observable
final class AppHerdLifecycle {
    private let repository: any HerdRepository
    private let selection: AppCurrentHerdSelection

    let isMirroring: Bool
    private(set) var availableHerds: [AccessibleHerd] = []
    private(set) var errorMessage: String?
    private(set) var hasLoadedHerds = false
    private(set) var isCreating = false

    var selectedHerdID: UUID? { selection.currentHerdID }

    init(
        repository: any HerdRepository,
        selection: AppCurrentHerdSelection,
        isMirroring: Bool
    ) {
        self.repository = repository
        self.selection = selection
        self.isMirroring = isMirroring
    }

    func refresh(navigation: AppNavigationState) {
        do {
            let herds = try repository.fetchAccessibleHerds()
            availableHerds = herds
            hasLoadedHerds = true
            errorMessage = nil
            if let current = selection.currentHerdID,
               !herds.contains(where: { $0.id == current }) {
                // The selected root is no longer locally accessible. Immediately
                // discard all record-bound navigation before leaving the Herd.
                navigation.resetForHerdChange(to: nil)
                selection.select(nil)
            }
        } catch {
            // A transient query failure cannot prove a Herd was removed.
            errorMessage = error.localizedDescription
            hasLoadedHerds = true
        }
    }

    func restoreSelection(from scenePayload: String, navigation: AppNavigationState) {
        guard let data = Data(base64Encoded: scenePayload),
              let saved = try? JSONDecoder().decode(AppNavigationSnapshot.self, from: data),
              let desiredID = saved.selectedHerdID,
              AppNavigationSnapshot.supportedVersions.contains(saved.version),
              availableHerds.contains(where: { $0.id == desiredID }) else {
            return
        }
        if selection.currentHerdID != desiredID {
            navigation.resetForHerdChange(to: desiredID)
            selection.select(desiredID)
        }
    }

    func select(_ herdID: UUID, navigation: AppNavigationState) {
        do {
            // Revalidate at the action boundary, not against a stale list.
            let herds = try repository.fetchAccessibleHerds()
            availableHerds = herds
            guard herds.contains(where: { $0.id == herdID }) else {
                throw HerdRepositoryError.missingHerd
            }
            if selection.currentHerdID != herdID {
                navigation.resetForHerdChange(to: herdID)
                selection.select(herdID)
            }
            navigation.showingHerds = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createOwnedHerd(named name: String, navigation: AppNavigationState) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await repository.createOwnedHerd(named: name)
            let herds = try repository.fetchAccessibleHerds()
            availableHerds = herds
            guard herds.contains(where: { $0.id == created.id }) else {
                throw HerdRepositoryError.missingHerd
            }
            navigation.resetForHerdChange(to: created.id)
            selection.select(created.id)
            navigation.showingHerds = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
