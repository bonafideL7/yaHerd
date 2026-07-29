import SwiftUI

private struct AppNavigationPresentationModifier: ViewModifier {
    @Environment(AppNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        @Bindable var navigation = navigation

        content
            .sheet(item: $navigation.presentedSheet) { sheet in
                sheetContent(sheet)
            }
            .fullScreenCover(item: $navigation.fullScreenWorkflow) { workflow in
                fullScreenContent(workflow)
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppPresentedSheet) -> some View {
        switch sheet {
        case .settings:
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            ToolbarDoneButton { navigation.dismissSheet() }
                        }
                    }
            }
        case .addAnimal:
            AddAnimalView()
        case .addPasture:
            AddPastureView()
        case .startFieldCheck:
            NavigationStack {
                FieldCheckPastureStartListView { sessionID in
                    navigation.openFieldCheckArea(
                        .session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID))
                    )
                }
                .sheetCancelToolbar()
            }
        case .startWorkingSession:
            WorkingSessionStartSheetFlow {
                navigation.dismissSheet()
            }
        }
    }

    @ViewBuilder
    private func fullScreenContent(_ workflow: AppFullScreenWorkflow) -> some View {
        switch workflow {
        case .fieldCheck:
            IsolatedFieldCheckAreaView {
                navigation.closeFullScreenWorkflow()
            }
        case .workingSession:
            IsolatedWorkAreaView {
                navigation.closeFullScreenWorkflow()
            }
        }
    }
}

private struct WorkingSessionStartSheetFlow: View {
    @State private var startedSessionID: UUID?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            if let startedSessionID {
                WorkingSessionDetailView(sessionID: startedSessionID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                onClose()
                            }
                        }
                    }
            } else {
                NewWorkingSessionView(
                    wrapsInNavigationStack: false,
                    onSessionCreated: { sessionID in
                        startedSessionID = sessionID
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            onClose()
                        }
                    }
                }
            }
        }
    }
}

private extension View {
    func sheetCancelToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                DismissButton()
            }
        }
    }
}

private struct DismissButton: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        Button("Cancel", role: .cancel) { navigation.dismissSheet() }
    }
}

extension View {
    func appNavigationPresentations() -> some View {
        modifier(AppNavigationPresentationModifier())
    }

    func appSettingsToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AppSettingsMenuButton()
            }
        }
    }

    func yaherdInlineLargeNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
    }
}

private struct AppSettingsMenuButton: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        Menu {
            Button {
                navigation.present(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("More actions")
    }
}
