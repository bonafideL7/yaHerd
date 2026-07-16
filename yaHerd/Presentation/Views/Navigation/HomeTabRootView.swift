import SwiftUI

struct HomeTabRootView: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        NavigationStack {
            HomeView(
                openAnimalList: { navigation.openAnimalList($0) },
                openPastureList: { navigation.openPastureList($0) },
                openFieldCheckArea: { navigation.openFieldCheckArea($0) },
                openWorkArea: { navigation.openWorkArea($0) }
            )
            .yaherdInlineLargeNavigationTitle("Home")
            .appSettingsToolbar()
        }
    }
}

struct DashboardTabRootView: View {
    var body: some View {
        NavigationStack {
            DashboardView()
                .yaherdInlineLargeNavigationTitle("Dashboard")
                .appSettingsToolbar()
        }
    }
}
