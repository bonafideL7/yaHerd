import SwiftUI

extension HomeView {
    @ViewBuilder
    var fieldWorkSection: some View {
        if snapshot == nil || hasFieldWorkRows {
            HomeSection(title: "Field Work") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading field work…")
                } else {
                    fieldWorkRows
                }
            }
        }
    }

    @ViewBuilder
    var fieldWorkRows: some View {
        if shouldShowUnfinishedChecksRow {
            NavigationLink {
                FieldChecksView(mode: .inProgress)
            } label: {
                HomeListRow(
                    title: "Checks not completed",
                    subtitle: "Finish remaining roster work before those counts go stale.",
                    systemImage: "checklist",
                    tint: .purple,
                    count: activeCheckSessions.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !pastureCheckDueItems.isEmpty {
            if pastureCheckDueItems.count == 1, let item = pastureCheckDueItems.first {
                NavigationLink {
                    FieldCheckSessionDetailView(suggestedPastureID: item.id)
                } label: {
                    HomeListRow(
                        title: "Check \(item.name)",
                        subtitle: item.lastCheckDescription,
                        systemImage: "calendar.badge.exclamationmark",
                        tint: .purple,
                        count: item.activeAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    HomePastureCheckDueListView(items: pastureCheckDueItems)
                } label: {
                    HomeListRow(
                        title: "Pasture checks due",
                        subtitle: "Start checks for pastures without a recent completed pass.",
                        systemImage: "calendar.badge.exclamationmark",
                        tint: .purple,
                        count: pastureCheckDueItems.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if shouldShowOpenFindingsRow {
            if openFindings.count == 1, let finding = openFindings.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
                } label: {
                    HomeListRow(
                        title: "Resolve open field finding",
                        subtitle: finding.pastureName ?? "Open finding from a pasture check.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        count: 1,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .openFindings)
                } label: {
                    HomeListRow(
                        title: "Open field findings",
                        subtitle: "Fence, water, health, and missing-animal notes from checks.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        count: openFindings.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if flaggedCheckAnimalCount > 0 {
            if flaggedCheckSessions.count == 1, let session = flaggedCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensFlaggedRoster: true)
                } label: {
                    HomeListRow(
                        title: "Flagged animals from checks",
                        subtitle: session.displayTitle,
                        systemImage: "flag.fill",
                        tint: .orange,
                        count: flaggedCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .flaggedAnimals)
                } label: {
                    HomeListRow(
                        title: "Flagged animals from checks",
                        subtitle: "Jump directly to animals marked for attention in the field.",
                        systemImage: "flag.fill",
                        tint: .orange,
                        count: flaggedCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if missingCheckAnimalCount > 0 {
            if missingCheckSessions.count == 1, let session = missingCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensMissingRoster: true)
                } label: {
                    HomeListRow(
                        title: "Missing animals from checks",
                        subtitle: session.displayTitle,
                        systemImage: "questionmark.app.fill",
                        tint: .brown,
                        count: missingCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .missingAnimals)
                } label: {
                    HomeListRow(
                        title: "Missing animals from checks",
                        subtitle: "Open check rosters filtered to animals marked missing.",
                        systemImage: "questionmark.app.fill",
                        tint: .brown,
                        count: missingCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

}
