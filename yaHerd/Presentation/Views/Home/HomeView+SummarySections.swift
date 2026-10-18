import SwiftUI

extension HomeView {
    var homeSummaryCardsSection: some View {
        HStack(spacing: 12) {
            pastureCheckActionCard
                .frame(maxWidth: .infinity)
            startWorkingSessionActionCard
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    var pastureCheckActionCard: some View {
        let isAvailable = snapshot != nil && !pastureCheckStartPastures.isEmpty
        let card = HomeActionCardView(
            title: "Pasture Check",
            subtitle: "Start a pasture check",
            systemImage: "checklist",
            tint: .purple,
            actionTitle: pastureCheckActionTitle,
            showsChevron: isAvailable
        )

        if isAvailable {
            NavigationLink {
                HomePastureCheckStartListView(pastures: pastureCheckStartPastures) { sessionID in
                    openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID)))
                }
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    @ViewBuilder
    var startWorkingSessionActionCard: some View {
        let isAvailable = snapshot != nil && hasActiveAnimals
        let card = HomeActionCardView(
            title: "Work animals",
            subtitle: "Collect animals and track work",
            systemImage: "plus.circle.fill",
            tint: .blue,
            actionTitle: workAnimalsActionTitle,
            showsChevron: isAvailable
        )

        if isAvailable {
            NavigationLink {
                WorkingSessionPastureStartListView(hasActiveAnimals: hasActiveAnimals) { sessionID in
                    openWorkArea(.session(sessionID))
                }
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    @ViewBuilder
    var alertsSection: some View {
        if snapshot == nil || !alerts.isEmpty {
            HomeSection(title: "Alerts") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading alerts…")
                } else {
                    NavigationLink {
                        HomeAlertsView(
                            alerts: alerts,
                            openAnimalList: openAnimalList,
                            openPastureList: openPastureList
                        )
                    } label: {
                        HomeListRow(
                            title: "Alerts",
                            subtitle: alertSummarySubtitle,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: alertTint,
                            count: alerts.count,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
