import SwiftUI

private struct AppNavigationPresentationModifier: ViewModifier {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.recoveryModeController) private var recoveryModeController

    func body(content: Content) -> some View {
        @Bindable var navigation = navigation
        @Bindable var router = navigation.herdRouter

        content
            .recoveryModeScenePresentation(
                controller: recoveryModeController,
                presentsDetails: navigation.presentedSheet == nil && navigation.fullScreenWorkflow == nil
            )
            .sheet(item: $navigation.presentedSheet) { sheet in
                sheetContent(sheet)
                    .recoveryModeScenePresentation(
                        controller: recoveryModeController,
                        presentsDetails: navigation.fullScreenWorkflow == nil
                    )
            }
            .fullScreenCover(item: $navigation.fullScreenWorkflow) { workflow in
                fullScreenContent(workflow)
                    .recoveryModeScenePresentation(controller: recoveryModeController)
            }
            // Keep sort presentation on the stable app presentation layer.
            // The iOS 26 tab accessory only requests it through HerdRouter.
            .confirmationDialog(
                "Sort Animals",
                isPresented: $router.showingSort,
                titleVisibility: .visible
            ) {
                ForEach(AnimalSortOrder.menuOptions, id: \.self) { option in
                    Button {
                        router.sortOrder = option
                    } label: {
                        Label(
                            option.label,
                            systemImage: router.sortOrder == option
                                ? "checkmark"
                                : option.menuIcon
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
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
            NavigationStack {
                NewWorkingSessionView(
                    wrapsInNavigationStack: false,
                    onSessionCreated: { sessionID in
                        navigation.openWorkArea(.session(sessionID))
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            navigation.dismissSheet()
                        }
                    }
                }
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
