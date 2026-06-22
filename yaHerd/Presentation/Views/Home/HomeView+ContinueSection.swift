import SwiftUI

extension HomeView {
    var continueSection: some View {
        HomeSection(title: "Continue") {
            if snapshot == nil {
                HomeLoadingRow(title: "Loading current work…")
            } else if let activeSession {
                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    HomePrimaryActionRow(
                        title: "Resume working session",
                        subtitle: activeSessionSummary(activeSession),
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange,
                        actionTitle: "Resume"
                    )
                }
                .buttonStyle(.plain)
            } else if let session = activeCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensRemainingRoster: true)
                } label: {
                    HomePrimaryActionRow(
                        title: "Finish \(session.displayTitle) check",
                        subtitle: "\(session.individuallyVerifiedCount)/\(session.expectedHeadCountSnapshot) verified · \(session.remainingExpectedCount) remaining",
                        systemImage: "checklist",
                        tint: .purple,
                        actionTitle: "Continue"
                    )
                }
                .buttonStyle(.plain)
            } else if workingPenCount > 0 {
                Button {
                    openAnimalList(.workingPen)
                } label: {
                    HomePrimaryActionRow(
                        title: "Clear the working pen",
                        subtitle: "\(workingPenCount) animals are still staged for work.",
                        systemImage: "arrowshape.turn.up.left.circle.fill",
                        tint: .orange,
                        actionTitle: "Open"
                    )
                }
                .buttonStyle(.plain)
            } else if let finding = openFindings.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
                } label: {
                    HomePrimaryActionRow(
                        title: "Resolve field finding",
                        subtitle: finding.pastureName ?? "Open finding from a pasture check.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        actionTitle: "Resolve"
                    )
                }
                .buttonStyle(.plain)
            } else {
                HomeStatusRow(
                    title: "Nothing in progress",
                    subtitle: "Start a pasture check or working session from the plus button.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
        }
    }


}
