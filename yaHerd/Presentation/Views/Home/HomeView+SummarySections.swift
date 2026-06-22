import SwiftUI

extension HomeView {
    var homeSummaryCardsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                continueSummaryCard
                    .frame(maxWidth: .infinity)
                fieldWorkSummaryCard
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                pastureOperationsSummaryCard
                    .frame(maxWidth: .infinity)
                recordsCleanupSummaryCard
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    var continueSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Continue",
            value: continueCardCount,
            subtitle: continueCardSubtitle,
            systemImage: continueCardCount > 0 ? "play.fill" : "plus",
            tint: continueCardCount > 0 ? .orange : .blue
        )

        if activeSession != nil {
            NavigationLink {
                WorkingSessionsView()
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if let session = activeCheckSessions.first {
            NavigationLink {
                FieldCheckSessionDetailView(sessionID: session.id, opensRemainingRoster: true)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if workingPenCount > 0 {
            Button {
                openAnimalList(.workingPen)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if let finding = openFindings.first {
            NavigationLink {
                FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                isStartingFieldCheck = true
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var fieldWorkSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Field Work",
            value: fieldWorkCardCount,
            subtitle: fieldWorkCardCount == 1 ? "1 field task" : "Field tasks",
            systemImage: "checklist",
            tint: fieldWorkCardCount > 0 ? .purple : .gray
        )

        NavigationLink {
            FieldChecksView(mode: .all)
        } label: {
            HomeSummaryCardView(card: card)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var pastureOperationsSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Pasture Ops",
            value: pastureOperationsCardCount,
            subtitle: pastureOperationsCardCount == 1 ? "1 pasture task" : "Pasture tasks",
            systemImage: "arrow.triangle.2.circlepath",
            tint: pastureOperationsCardCount > 0 ? .green : .gray
        )

        if !overstockedPastures.isEmpty {
            Button {
                openPastureList(.overstocked)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !rotationReadyPastures.isEmpty {
            Button {
                openPastureList(.rotationReady)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !underutilizedPastures.isEmpty {
            Button {
                openPastureList(.underutilized)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !pasturesMissingStockingData.isEmpty {
            Button {
                openPastureList(.missingStockingData)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                openPastureList(.all)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var recordsCleanupSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Cleanup",
            value: recordsCleanupCardCount,
            subtitle: recordsCleanupCardCount == 1 ? "1 record issue" : "Record issues",
            systemImage: "wrench.and.screwdriver.fill",
            tint: recordsCleanupCardCount > 0 ? .brown : .gray
        )

        if !unassignedAnimalRecords.isEmpty {
            Button {
                openAnimalList(.missingPasture)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !missingTagAnimals.isEmpty {
            Button {
                openAnimalList(.missingTags)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !unknownSexAnimals.isEmpty {
            Button {
                openAnimalList(.unknownSex)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !archivedActiveRecords.isEmpty {
            Button {
                openAnimalList(.archivedActive)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                openAnimalList(.active)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var alertsSection: some View {
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
                        systemImage: alerts.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
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
