import SwiftUI

struct IsolatedFieldCheckAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onClose: () -> Void

    var body: some View {
        NavigationStack(path: fieldCheckPathBinding) {
            FieldChecksView(
                mode: fieldCheckModeBinding,
                onSessionLaunch: { navigation.workflowRouter.openFieldCheckSession($0) },
                onStart: { navigation.workflowRouter.openFieldCheckStart() }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    IsolatedFlowCloseButton(action: onClose)
                }
            }
            .navigationDestination(for: FieldCheckWorkflowDestination.self) { destination in
                switch destination {
                case .start(let pastureID):
                    fieldCheckStartContent(pastureID: pastureID)
                case .session(let configuration):
                    sessionContent(configuration)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldCheckStartContent(pastureID: UUID?) -> some View {
        if let pastureID {
            FieldCheckSessionSetupView(
                suggestedPastureID: pastureID
           ) { sessionID in
                navigation.workflowRouter.openFieldCheckSession(
                    FieldCheckSessionLaunchConfiguration(sessionID: sessionID)
                )
            }
        } else {
            PastureSessionStartListView(kind: .fieldCheck) { sessionID in
                navigation.workflowRouter.openFieldCheckSession(
                    FieldCheckSessionLaunchConfiguration(sessionID: sessionID)
                )
            }
        }
    }

    private func sessionContent(_ configuration: FieldCheckSessionLaunchConfiguration) -> some View {
        FieldCheckSessionDetailView(
            sessionID: configuration.sessionID,
            opensFindings: configuration.opensFindings,
            opensFlaggedRoster: configuration.opensFlaggedRoster,
            opensRemainingRoster: configuration.opensRemainingRoster,
            opensMissingRoster: configuration.opensMissingRoster,
            focusedFindingID: configuration.focusedFindingID,
            onSessionFinished: { navigation.workflowRouter.returnToList() }
        )
    }

    private var fieldCheckPathBinding: Binding<[FieldCheckWorkflowDestination]> {
        Binding(
            get: { navigation.workflowRouter.fieldCheckNavigationPath },
            set: { navigation.workflowRouter.fieldCheckNavigationPath = $0 }
        )
    }

    private var fieldCheckModeBinding: Binding<FieldChecksViewMode> {
        Binding {
            navigation.workflowRouter.fieldCheckListMode ?? .all
        } set: { mode in
            guard case .fieldCheckSessions = navigation.workflowRouter.route else { return }
            navigation.workflowRouter.route = .fieldCheckSessions(mode)
        }
    }
}

struct IsolatedWorkAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onClose: () -> Void

    var body: some View {
        NavigationStack(path: workingSessionPathBinding) {
            WorkingSessionsView(
                onSessionStarted: { navigation.workflowRouter.openWorkingSession($0) },
                onStart: { navigation.workflowRouter.openWorkingSessionStart() }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    IsolatedFlowCloseButton(action: onClose)
                }
            }
            .navigationDestination(for: WorkingSessionWorkflowDestination.self) { destination in
                switch destination {
                case .start(let pastureID):
                    workingSessionStartContent(pastureID: pastureID)
                case .session(let sessionID):
                    sessionContent(sessionID)
                }
            }
        }
    }

    @ViewBuilder
    private func workingSessionStartContent(pastureID: UUID?) -> some View {
        if let pastureID {
            NewWorkingSessionView(
                suggestedPastureID: pastureID,
                wrapsInNavigationStack: false
            ) { sessionID in
                navigation.workflowRouter.openWorkingSession(sessionID)
            }
        } else {
            PastureSessionStartListView(kind: .working) { sessionID in
                navigation.workflowRouter.openWorkingSession(sessionID)
            }
        }
    }

    private func sessionContent(_ sessionID: UUID) -> some View {
        WorkingSessionDetailView(
            sessionID: sessionID,
            onSessionDeleted: { navigation.handleDeletedWorkingSession($0) },
            onSessionFinished: { navigation.workflowRouter.returnToList() }
        )
    }

    private var workingSessionPathBinding: Binding<[WorkingSessionWorkflowDestination]> {
        Binding(
            get: { navigation.workflowRouter.workingSessionNavigationPath },
            set: { navigation.workflowRouter.workingSessionNavigationPath = $0 }
        )
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
