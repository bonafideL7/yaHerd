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
        NavigationLink {
            HomePastureCheckStartListView(pastures: pastureCheckStartPastures)
        } label: {
            HomeActionCardView(
                title: "Pasture Check",
                subtitle: "Start a pasture check",
                systemImage: "checklist",
                tint: .purple,
                actionTitle: pastureCheckActionTitle
            )
        }
        .buttonStyle(.plain)
        .disabled(snapshot == nil)
    }

    @ViewBuilder
    var startWorkingSessionActionCard: some View {
        Button {
            isPresentingNewWorkingSession = true
        } label: {
            HomeActionCardView(
                title: "Work animals",
                subtitle: "Collect animals and track work",
                systemImage: "plus.circle.fill",
                tint: .blue,
                actionTitle: "Start"
            )
        }
        .buttonStyle(.plain)
        .disabled(snapshot == nil)
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
