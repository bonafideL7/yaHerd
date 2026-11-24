//
//  SettingsView.swift
//  yaHerd
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(\.recoveryModeController) private var recoveryModeController

    var body: some View {
        List {
            if dataAccessMode.isRecoveryMode {
                Section("Storage Recovery") {
                    Button {
                        recoveryModeController?.isPresentingCenter = true
                    } label: {
                        SettingsRow(
                            title: "Recovery Mode — Read Only",
                            subtitle: "Changes cannot be saved. Export diagnostics or attempt store repair.",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    }

                    Text("Data editing is disabled for this launch.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Setup") {
                NavigationLink {
                    HerdDirectoryView()
                } label: {
                    SettingsRow(
                        title: "Herds",
                        subtitle: "Choose or create a Herd.",
                        systemImage: "square.stack.3d.up"
                    )
                }

                NavigationLink {
                    DashboardRulesView()
                } label: {
                    SettingsRow(
                        title: "Dashboard",
                        subtitle: "Configure dashboard visibility.",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                }

                NavigationLink {
                    HerdSetupView()
                } label: {
                    SettingsRow(
                        title: "Herd",
                        subtitle: "Configure tag colors and animal record behavior.",
                        systemImage: "tag"
                    )
                }

                NavigationLink {
                    PastureDefaultsView()
                } label: {
                    SettingsRow(
                        title: "Pasture",
                        subtitle: "Set default stocking and usable acreage assumptions.",
                        systemImage: "leaf"
                    )
                }
            }

            Section("About") {
                NavigationLink {
                    AboutYaHerdView()
                } label: {
                    SettingsRow(
                        title: "About yaHerd",
                        subtitle: "Version, privacy, and acknowledgements.",
                        systemImage: "info.circle"
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .settingsSaveAndCloseToolbar()
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HerdSetupView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(ApplicationSettings.self) private var applicationSettings

    var body: some View {
        @Bindable var applicationSettings = applicationSettings

        List {
            Section("Tags") {
                NavigationLink {
                    TagColorLibraryView()
                } label: {
                    Label("Tag Colors", systemImage: "tag")
                }

                Text("Control the color library used when assigning and displaying animal tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Animal Records") {
                Toggle("Inline Editing", isOn: $applicationSettings.inlineAnimalEditingEnabled)
                    .disabled(dataAccessMode.isRecoveryMode)

                Text("When enabled, tap an animal to edit it inline, or tap empty space to add one. Long-press an animal for the full editor or details. When disabled, tapping an animal opens the full editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Hard Delete Animals", isOn: $applicationSettings.hardDeleteAnimals)
                    .disabled(dataAccessMode.isRecoveryMode)

                Text("When enabled, swiping an active animal deletes it permanently instead of archiving it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Herd Setup")
        .settingsSaveAndCloseToolbar()
    }
}

struct DashboardRulesView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(ApplicationSettings.self) private var applicationSettings

    var body: some View {
        @Bindable var applicationSettings = applicationSettings
        Form {
            Section("Navigation") {
                Toggle("Show Dashboard", isOn: $applicationSettings.isDashboardEnabled)
                    .disabled(dataAccessMode.isRecoveryMode)

                Text("When off, the Dashboard tab is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visible Sections") {
                ForEach(DashboardSection.allCases) { section in
                    Toggle(section.title, isOn: visibilityBinding(for: section))
                        .disabled(dataAccessMode.isRecoveryMode)
                }

                Text("Hide charts you do not need. Your choices are saved on this device and do not affect herd records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dashboard Setup")
        .settingsSaveAndCloseToolbar()
    }

    private func visibilityBinding(for section: DashboardSection) -> Binding<Bool> {
        Binding(
            get: { applicationSettings.isDashboardSectionVisible(section) },
            set: { isVisible in
                var hiddenSections = applicationSettings.hiddenDashboardSections
                if isVisible {
                    hiddenSections.remove(section)
                } else {
                    hiddenSections.insert(section)
                }
                applicationSettings.hiddenDashboardSections = hiddenSections
            }
        )
    }
}

struct PastureDefaultsView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(ApplicationSettings.self) private var applicationSettings

    var body: some View {
        @Bindable var applicationSettings = applicationSettings
        Form {
            Section("New Pasture Defaults") {
                Stepper(
                    "Target acres/head: \(applicationSettings.targetAcresPerHeadDefault, format: .number.precision(.fractionLength(2)))",
                    value: $applicationSettings.targetAcresPerHeadDefault,
                    in: 0.25...25.0,
                    step: 0.25
                )
                .disabled(dataAccessMode.isRecoveryMode)

                Stepper(
                    "Usable acreage: \(applicationSettings.usableAcreagePercentDefault)%",
                    value: $applicationSettings.usableAcreagePercentDefault,
                    in: 10...100
                )
                .disabled(dataAccessMode.isRecoveryMode)

                Text("Defaults are applied to newly created pasture records only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pasture Setup")
        .settingsSaveAndCloseToolbar()
    }
}

private struct AboutYaHerdView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var lucideProjectURL: URL? {
        URL(string: "https://github.com/JakubMazur/lucide-icons-swift")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("yaHerd")
                        .font(.title2)
                        .bold()

                    Text("Beef cattle herd management")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Keep herd records, pasture checks, working sessions, and health history together in one place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Installed Version") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)

                Text("Version \(version) (\(build))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Press and hold the version line to copy it when reporting an issue.")
                    .foregroundStyle(HierarchicalShapeStyle.tertiary)
                    .font(.caption)
            }

            Section("Data & Privacy") {
                Text("Herd records are stored locally in yaHerd app data on this device.")

                Text("This build does not include advertising or third-party analytics tracking.")
                    .foregroundStyle(.secondary)
            }

            Section("Open Source") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lucide Icons")
                        .font(.headline)

                    Text("Interface icons provided by Lucide Icons under the ISC License.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let lucideProjectURL {
                        Link("View project and license", destination: lucideProjectURL)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("About")
        .settingsSaveAndCloseToolbar()
    }
}

private struct SettingsSaveAndCloseToolbarModifier: ViewModifier {
    @Environment(AppNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        content
            .toolbar {
                if navigation.presentedSheet == .settings {
                    ToolbarItem(placement: .confirmationAction) {
                        ToolbarDoneButton(accessibilityLabel: "Save and Close Settings") {
                            navigation.dismissSheet()
                        }
                    }
                }
            }
    }
}

extension View {
    func settingsSaveAndCloseToolbar() -> some View {
        modifier(SettingsSaveAndCloseToolbarModifier())
    }
}

@MainActor
struct HerdDirectoryView: View {
    @Environment(HerdDirectoryController.self) private var directory
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(\.scenePhase) private var scenePhase

    @State private var isCreating = false
    @State private var openingState = HerdDirectoryOpeningState()
    @State private var pendingHerd: AccessibleHerd?
    @State private var validationTask: Task<Void, Never>?
    @State private var creationTask: Task<Void, Never>?
    @State private var showsCreatePrompt = false
    @State private var newHerdName = ""

    private var isOpeningHerd: Bool { openingState.isOpening }

    var body: some View {
        List {
            Section("Available Herds") {
                ForEach(directory.herds) { herd in
                    Button {
                        beginOpeningHerd(herd: herd)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(herd.name)
                                    .foregroundStyle(.primary)
                                Text(herd.category == .owned ? "Owned" : "Shared")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if directory.selectedHerdID == herd.id {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel("Selected Herd")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(dataAccessMode.isRecoveryMode || isCreating || isOpeningHerd)
                }

                if directory.inventoryState == .loading {
                    ProgressView("Loading available Herds")
                } else if directory.inventoryState == .unavailable {
                    Label(
                        "The Herd list could not be read. Existing Herds may still be present. Refresh before creating a Herd.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                } else if directory.inventoryState == .incomplete {
                    Label(
                        "Some Herd records are incomplete and may still be importing. Refresh to check for newly available Herds.",
                        systemImage: "icloud.and.arrow.down"
                    )
                    .foregroundStyle(.secondary)
                } else if directory.herds.isEmpty {
                    Text("No Herds are available. If iCloud synchronization is still starting, refresh before creating a separate Herd.")
                        .foregroundStyle(.secondary)
                }

                if pendingHerd != nil {
                    HStack {
                        ProgressView()
                        Text("Waiting for the selected Herd's records to finish importing.")
                            .font(.callout)
                        Spacer()
                        Button("Cancel") {
                            validationTask?.cancel()
                            validationTask = nil
                            openingState.cancel()
                            pendingHerd = nil
                        }
                    }
                }
            }

            if !dataAccessMode.isRecoveryMode {
                Section {
                    Button {
                        newHerdName = ""
                        showsCreatePrompt = true
                    } label: {
                        Label(
                            directory.inventoryState == .incomplete ? "Create Separate Herd" : "Create Herd",
                            systemImage: "plus"
                        )
                    }
                    .disabled(isCreating || isOpeningHerd ||
                              (directory.inventoryState != .available &&
                               directory.inventoryState != .incomplete))
                } footer: {
                    Text("Creating a Herd adds a separate owned Herd. It does not join an invitation or replace incomplete imported records.")
                }
            }
        }
        .navigationTitle("Herds")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    directory.refresh()
                }
            }
        }
        .task {
            directory.refresh(reportErrors: false)
            // Keep the original stores active while imported relationships arrive.
            while !Task.isCancelled {
                // Do not overwrite the active validation task with a no-op
                // retry, or Cancel could miss the in-flight Herd opening.
                if let pendingHerd {
                    // Do not await an uncooperative canceled validation here:
                    // the retry loop must remain free to open another Herd.
                    beginOpeningHerd(herd: pendingHerd)
                }
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
                directory.refresh(reportErrors: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { directory.refresh(reportErrors: false) }
        }
        .onDisappear {
            // Invalidate the old attempt immediately, even if its validation
            // callback does not cooperate with Task cancellation.
            validationTask?.cancel()
            validationTask = nil
            openingState.cancel()
            creationTask?.cancel()
        }
        .alert("Create Herd", isPresented: $showsCreatePrompt) {
            TextField("Herd name", text: $newHerdName)
            Button("Create") {
                guard !isCreating, !isOpeningHerd,
                      directory.inventoryState == .available ||
                      directory.inventoryState == .incomplete else { return }
                validationTask?.cancel()
                pendingHerd = nil
                isCreating = true
                creationTask = Task { @MainActor in
                    defer {
                        isCreating = false
                        creationTask = nil
                    }
                    do {
                        try Task.checkCancellation()
                        let created = try await directory.createOwnedHerd(named: newHerdName)
                        guard !Task.isCancelled, directory.selectedHerdID == created.id else {
                            return
                        }
                        navigation.resetForHerdChange(to: created.id)
                        navigation.dismissSheet()
                    } catch is CancellationError {
                        // A committed root is still available, but a dismissed
                        // chooser must not reactivate it.
                    } catch {
                        if !Task.isCancelled {
                            directory.report(error)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a separate owned Herd with its own animals and pastures.")
        }
        .alert("Herd Unavailable", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.dismissError() } }
        )) {
            Button("OK", role: .cancel) { directory.dismissError() }
        } message: {
            Text(directory.errorMessage ?? "The Herd cannot be opened.")
        }
    }

    /// Claim the opening attempt before scheduling its task, so a rapid
    /// second tap cannot cancel the first and lose the newer selection.
    @discardableResult
    @MainActor
    private func beginOpeningHerd(herd: AccessibleHerd) -> Task<Void, Never>? {
        guard let attemptID = openingState.begin() else { return nil }
        validationTask?.cancel()
        let attempt = Task { @MainActor in await openHerd(herd: herd, attemptID: attemptID) }
        validationTask = attempt
        return attempt
    }

    @MainActor
    private func openHerd(herd: AccessibleHerd, attemptID: UUID) async {
        defer {
            if openingState.finish(attemptID) {
                validationTask = nil
            }
        }
        do {
            try await directory.selectHerdWhenReady(id: herd.id, expectedRoot: herd)
            guard !Task.isCancelled, openingState.isCurrent(attemptID) else { return }
            pendingHerd = nil
            navigation.resetForHerdChange(to: herd.id)
            navigation.dismissSheet()
        } catch {
            // A canceled or superseded validation cannot publish old state.
            if Task.isCancelled || error is CancellationError ||
                !openingState.isCurrent(attemptID) { return }
            #if DEBUG
            if CloudKitDevelopmentLaunch.isImportPending(error) {
                if directory.shouldContinueWaitingForHerd(id: herd.id) {
                    pendingHerd = herd
                } else {
                    pendingHerd = nil
                    directory.report(HerdDirectoryError.pendingHerdUnavailable)
                }
                return
            }
            #endif
            pendingHerd = nil
            directory.report(error)
        }
    }
}

@MainActor
struct HerdDirectoryOpeningState {
    private(set) var activeAttemptID: UUID?

    var isOpening: Bool { activeAttemptID != nil }

    mutating func begin() -> UUID? {
        guard activeAttemptID == nil else { return nil }
        let id = UUID()
        activeAttemptID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        activeAttemptID == id
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard activeAttemptID == id else { return false }
        activeAttemptID = nil
        return true
    }

    mutating func cancel() {
        activeAttemptID = nil
    }
}
