import SwiftUI

private struct SharingAccessRefreshModifier: ViewModifier {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.collaborationDependencies) private var collaborationDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode

    func body(content: Content) -> some View {
        content
            .task {
                refresh()
            }
            .onChange(of: navigation.selectedTab) { _, selectedTab in
                refresh(tab: selectedTab)
            }
            .onChange(of: navigation.herdRouter.mode) { _, mode in
                refresh(mode: mode)
            }
    }

    private func refresh(tab: AppTab? = nil, mode: HerdViewMode? = nil) {
        guard dataAccessMode.allowsDataMutations,
              let coordinator = collaborationDependencies.syncCoordinator
        else { return }

        let activeTab = tab ?? navigation.selectedTab
        let activeMode = mode ?? navigation.herdRouter.mode
        let surfaceName: String

        switch activeTab {
        case .home:
            surfaceName = "Home"
        case .dashboard:
            surfaceName = "Dashboard"
        case .herd:
            surfaceName = activeMode == .animals ? "Animal records" : "Pasture records"
        }

        Task { @MainActor in
            await coordinator.refreshSharingAccessNow(trigger: .screenOpened(surfaceName))
        }
    }
}

extension View {
    func sharingAccessRefreshesForNavigation() -> some View {
        modifier(SharingAccessRefreshModifier())
    }
}
