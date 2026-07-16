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
            if activeCheckSessions.count == 1, let session = activeCheckSessions.first {
                Button {
                    openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensRemainingRoster: true)))
                } label: {
                    HomeListRow(
                        title: "Open pasture check",
                        subtitle: session.displayTitle,
                        systemImage: "checklist",
                        tint: .purple,
                        count: 1,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openFieldChecks(.inProgress)
                } label: {
                    HomeListRow(
                        title: "Open pasture checks",
                        subtitle: "Finish open pasture checks before counts go stale.",
                        systemImage: "checklist",
                        tint: .purple,
                        count: activeCheckSessions.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if shouldShowOpenFindingsRow {
            if openFindings.count == 1, let finding = openFindings.first {
                Button {
                    openFieldCheckArea(
                        .session(
                            FieldCheckSessionLaunchConfiguration(
                                sessionID: finding.sessionID,
                                opensFindings: true,
                                focusedFindingID: finding.id
                            )
                        )
                    )
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
                Button {
                    openFieldChecks(.openFindings)
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
                Button {
                    openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensFlaggedRoster: true)))
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
                Button {
                    openFieldChecks(.flaggedAnimals)
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
                Button {
                    openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensMissingRoster: true)))
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
                Button {
                    openFieldChecks(.missingAnimals)
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
