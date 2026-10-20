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
        if case .fieldCheckSession(let configuration) = navigation.workflowRouter.route,
           navigation.workflowRouter.fieldCheckListMode == nil {
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
        FieldChecksView(
            mode: fieldCheckModeBinding,
            startsWithPastureSelection: navigation.workflowRouter.startsWithPastureSelection
        ) { configuration in
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
        NavigationStack(path: workingSessionPathBinding) {
            rootContent
                .navigationDestination(for: UUID.self) { sessionID in
                    sessionContent(sessionID)
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if case .workingSession(let sessionID) = navigation.workflowRouter.route,
           !navigation.workflowRouter.canReturnToList {
            sessionContent(sessionID)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowCloseButton(action: onClose)
                    }
                }
        } else {
            sessionsList
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowCloseButton(action: onClose)
                    }
                }
        }
    }

    private var sessionsList: some View {
        WorkingSessionsView(startsWithPastureSelection: navigation.workflowRouter.startsWithPastureSelection) { sessionID in
            navigation.workflowRouter.openWorkingSession(sessionID)
        }
    }

    private func sessionContent(_ sessionID: UUID) -> some View {
        WorkingSessionDetailView(sessionID: sessionID) { deletedID in
            navigation.handleDeletedWorkingSession(deletedID)
        }
    }

    private var workingSessionPathBinding: Binding<[UUID]> {
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
