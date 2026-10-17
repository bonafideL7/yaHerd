import SwiftUI

struct IsolatedFieldCheckAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if navigation.workflowRouter.canReturnToList {
                            Button {
                                navigation.workflowRouter.returnToList()
                            } label: {
                                Label("Back to Checks", systemImage: "chevron.left")
                            }
                        } else {
                            IsolatedFlowCloseButton(action: onClose)
                        }
                    }
                    if navigation.workflowRouter.canReturnToList {
                        ToolbarItem(placement: .topBarTrailing) {
                            IsolatedFlowCloseButton(action: onClose)
                        }
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
                navigation.workflowRouter.openFieldCheckSession(configuration)
            })
        default:
            FieldChecksView(mode: fieldCheckModeBinding(fallback: .all), onSessionLaunch: { configuration in
                navigation.workflowRouter.openFieldCheckSession(configuration)
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
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if navigation.workflowRouter.canReturnToList {
                            Button {
                                navigation.workflowRouter.returnToList()
                            } label: {
                                Label("Back to Sessions", systemImage: "chevron.left")
                            }
                        } else {
                            IsolatedFlowCloseButton(action: onClose)
                        }
                    }
                    if navigation.workflowRouter.canReturnToList {
                        ToolbarItem(placement: .topBarTrailing) {
                            IsolatedFlowCloseButton(action: onClose)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.workflowRouter.route {
        case .workingSession(let sessionID):
            WorkingSessionDetailView(sessionID: sessionID) { deletedID in
                navigation.handleDeletedWorkingSession(deletedID)
            }
        case .workingSessions:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.openWorkingSession(sessionID)
            }
        default:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.openWorkingSession(sessionID)
            }
        }
    }
}

private struct IsolatedFlowCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Close", systemImage: "xmark")
        }
        .accessibilityLabel("Close workflow")
    }
}
