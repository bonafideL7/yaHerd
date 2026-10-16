import SwiftUI

struct IsolatedFieldCheckAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onReturnHome: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowHomeButton(action: onReturnHome)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.workflowRouter.route {
        case .fieldCheckSession(let session):
            FieldCheckSessionDetailView(
                sessionID: session.sessionID,
                opensFindings: session.opensFindings,
                opensFlaggedRoster: session.opensFlaggedRoster,
                opensRemainingRoster: session.opensRemainingRoster,
                opensMissingRoster: session.opensMissingRoster,
                focusedFindingID: session.focusedFindingID
            )
        case .fieldCheckSessions(let mode):
            FieldChecksView(mode: mode, onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        default:
            FieldChecksView(mode: .all, onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        }
    }
}

struct IsolatedWorkAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onReturnHome: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowHomeButton(action: onReturnHome)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.workflowRouter.route {
        case .workingSession(let sessionID):
            WorkingSessionDetailView(sessionID: sessionID)
        case .workingSessions:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.route = .workingSession(sessionID)
            }
        default:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.route = .workingSession(sessionID)
            }
        }
    }
}

private struct IsolatedFlowHomeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Home", systemImage: "house")
        }
        .accessibilityLabel("Return Home")
    }
}
