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
            FieldChecksView(mode: fieldCheckModeBinding(fallback: mode), onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        default:
            FieldChecksView(mode: fieldCheckModeBinding(fallback: .all), onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        }
    }

    private func fieldCheckModeBinding(fallback: FieldChecksViewMode) -> Binding<FieldChecksViewMode> {
        Binding {
            guard case .fieldCheckSessions(let mode) = navigation.workflowRouter.route
            else { return fallback }
            return mode
        } set: { mode in
            // A completed list selection must not replace an already-open session route.
            if case .fieldCheckSession = navigation.workflowRouter.route { return }
            navigation.workflowRouter.route = .fieldCheckSessions(mode)
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
