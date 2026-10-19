import SwiftUI

struct IsolatedFieldCheckAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onClose: () -> Void

    var body: some View {
        NavigationStack(path: fieldCheckPathBinding) {
            rootContent
                .navigationDestination(for: FieldCheckSessionLaunchConfiguration.self) { configuration in
                    sessionContent(configuration)
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if navigation.workflowRouter.fieldCheckListMode != nil {
            checksList
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowCloseButton(action: onClose)
                    }
                }
        } else if case .fieldCheckSession(let configuration) = navigation.workflowRouter.route {
            sessionContent(configuration)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowCloseButton(action: onClose)
                    }
                }
        } else {
            checksList
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowCloseButton(action: onClose)
                    }
                }
        }
    }

    private var checksList: some View {
        FieldChecksView(mode: fieldCheckModeBinding) { configuration in
            navigation.workflowRouter.openFieldCheckSession(configuration)
        }
    }

    private func sessionContent(_ configuration: FieldCheckSessionLaunchConfiguration) -> some View {
        FieldCheckSessionDetailView(
            sessionID: configuration.sessionID,
            opensFindings: configuration.opensFindings,
            opensFlaggedRoster: configuration.opensFlaggedRoster,
            opensRemainingRoster: configuration.opensRemainingRoster,
            opensMissingRoster: configuration.opensMissingRoster,
            focusedFindingID: configuration.focusedFindingID
        )
    }

    private var fieldCheckPathBinding: Binding<[FieldCheckSessionLaunchConfiguration]> {
        Binding(
            get: { navigation.workflowRouter.fieldCheckNavigationPath },
            set: { navigation.workflowRouter.fieldCheckNavigationPath = $0 }
        )
    }

    private var fieldCheckModeBinding: Binding<FieldChecksViewMode> {
        Binding {
            navigation.workflowRouter.fieldCheckListMode ?? .all
        } set: { mode in
            // Keep the list selection while a session is pushed onto the stack.
            guard case .fieldCheckSessions = navigation.workflowRouter.route else { return }
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
