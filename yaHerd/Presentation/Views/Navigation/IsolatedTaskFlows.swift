import SwiftUI

struct IsolatedFieldCheckAreaView: View {
    let route: FieldCheckAreaLaunchConfiguration
    let onReturnHome: () -> Void

    @State private var activeSession: FieldCheckSessionLaunchConfiguration?

    init(route: FieldCheckAreaLaunchConfiguration, onReturnHome: @escaping () -> Void) {
        self.route = route
        self.onReturnHome = onReturnHome
        _activeSession = State(initialValue: route.session)
    }

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
        if let session = activeSession {
            FieldCheckSessionDetailView(
                sessionID: session.sessionID,
                opensFindings: session.opensFindings,
                opensFlaggedRoster: session.opensFlaggedRoster,
                opensRemainingRoster: session.opensRemainingRoster,
                opensMissingRoster: session.opensMissingRoster
            )
        } else {
            FieldChecksView(mode: route.mode ?? .all, onSessionLaunch: { configuration in
                activeSession = configuration
            })
        }
    }
}

struct IsolatedWorkAreaView: View {
    let route: WorkAreaLaunchConfiguration
    let onReturnHome: () -> Void

    @State private var activeSessionID: UUID?

    init(route: WorkAreaLaunchConfiguration, onReturnHome: @escaping () -> Void) {
        self.route = route
        self.onReturnHome = onReturnHome
        _activeSessionID = State(initialValue: route.sessionID)
    }

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
        if let sessionID = activeSessionID {
            WorkingSessionDetailView(sessionID: sessionID)
        } else {
            WorkingSessionsView { sessionID in
                activeSessionID = sessionID
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
