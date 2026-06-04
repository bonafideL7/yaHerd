//
//  EnableICloudSyncView.swift
//  yaHerd
//

import SwiftUI

struct EnableICloudSyncView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let checker: ICloudAvailabilityChecking
    private let preferences: AppPreferencesProviding
    private let settingsOpener: SystemSettingsOpening

    @State private var isChecking = false
    @State private var iCloudStatus: ICloudAccountStatus?
    @State private var statusMessage: String?
    @State private var didEnableSync = false
    @State private var showsRestartInstructions = false

    init(
        checker: ICloudAvailabilityChecking = ICloudAvailabilityChecker(),
        preferences: AppPreferencesProviding = AppPreferences(),
        settingsOpener: SystemSettingsOpening = SystemSettingsOpener()
    ) {
        self.checker = checker
        self.preferences = preferences
        self.settingsOpener = settingsOpener
    }

    var body: some View {
        List {
            Section {
                Label("iCloud Sync", systemImage: "icloud")
                    .font(.headline)

                Text("yaHerd can mirror your local SwiftData store and app settings through iCloud so the same herd data and preferences are available on your Apple devices.")
                    .foregroundStyle(.secondary)
            }

            Section("How This Works") {
                InfoRow(
                    title: "Still offline-first",
                    message: "Your data remains in the local on-device store. You can keep using yaHerd without signal. Sync resumes when iCloud is available."
                )

                InfoRow(
                    title: "No separate cloud database in the app",
                    message: "yaHerd uses the same persistent store and turns on CloudKit mirroring for sync."
                )

                InfoRow(
                    title: "Restart required",
                    message: "After enabling sync, restart yaHerd so the app can reopen the store with iCloud mirroring enabled and apply iCloud-backed app settings."
                )
            }

            Section("iCloud Status") {
                if isChecking {
                    HStack {
                        ProgressView()
                        Text("Checking iCloud availability…")
                    }
                } else if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("iCloud status will be checked automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let unavailableReason {
                iCloudHelpSection(for: unavailableReason)
            }

            if !didEnableSync {
                Section {
                    Button("Enable iCloud Sync") {
                        enableSync()
                    }
                    .disabled(!canEnableSync || isChecking)

                    Text(enableSyncExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if didEnableSync {
                Section("Restart Required") {
                    Label("iCloud Sync will be enabled after restart", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)

                    Text("iOS does not allow apps to restart themselves. Close yaHerd from the app switcher, then open it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        showsRestartInstructions.toggle()
                    } label: {
                        Label(showsRestartInstructions ? "Hide Restart Steps" : "Show Restart Steps", systemImage: "arrow.clockwise")
                    }

                    if showsRestartInstructions {
                        RestartInstructionList()
                    }
                }
            }
        }
        .navigationTitle("Enable iCloud Sync")
        .task {
            await refreshICloudAvailability()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !didEnableSync else { return }

            Task {
                await refreshICloudAvailability()
            }
        }
    }

    private var canEnableSync: Bool {
        guard case .available = iCloudStatus else {
            return false
        }

        return true
    }

    private var unavailableReason: ICloudUnavailableReason? {
        guard case .unavailable(let reason) = iCloudStatus else {
            return nil
        }

        return reason
    }

    private var enableSyncExplanation: String {
        if canEnableSync {
            return "This saves the iCloud Sync preference for next launch. If SwiftData cannot open the CloudKit-backed store after restart, yaHerd will automatically return to Local Only mode instead of crashing."
        }

        if isChecking {
            return "yaHerd is checking iCloud availability before sync can be enabled."
        }

        return "Enable iCloud Sync becomes available after yaHerd confirms this device can use iCloud."
    }

    @ViewBuilder
    private func iCloudHelpSection(for reason: ICloudUnavailableReason) -> some View {
        switch reason {
        case .noAccount:
            Section("Sign In to iCloud") {
                Button {
                    settingsOpener.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("After Settings opens:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("1. Tap Sign in to iPhone, or tap your Apple Account at the top.")
                    Text("2. Sign in with your Apple Account.")
                    Text("3. Open iCloud settings and make sure iCloud Drive is enabled.")
                    Text("4. Return to yaHerd. Availability will be checked again automatically.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

                Text("iOS does not provide an App Store-safe deep link directly to the iCloud sign-in screen. yaHerd can open Settings, then guide the user from there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .restricted:
            Section("iCloud Restricted") {
                Button {
                    settingsOpener.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }

                Text("Check Screen Time, parental controls, or device management restrictions. On managed devices, the user may need help from the device administrator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .couldNotDetermine, .temporarilyUnavailable, .unknown(_):
            Section("iCloud Help") {
                Button {
                    settingsOpener.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }

                Text("Confirm the device is signed in to iCloud, iCloud Drive is enabled, and the device has a network connection. Then return to yaHerd; availability will be checked again automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func refreshICloudAvailability() async {
        guard !isChecking else { return }

        isChecking = true
        iCloudStatus = nil
        statusMessage = nil

        let result = await checker.checkAvailability()
        iCloudStatus = result

        switch result {
        case .available:
            statusMessage = "iCloud is available. You can enable sync."

        case .unavailable(let reason):
            statusMessage = reason.message
        }

        isChecking = false
    }

    private func enableSync() {
        preferences.syncMode = .iCloud
        AppSettingsSynchronizer.shared.startIfNeeded(syncMode: .iCloud)
        didEnableSync = true
        statusMessage = "iCloud Sync preference saved. App settings are syncing now. Restart yaHerd to reopen the CloudKit-backed data store. If the CloudKit-backed store cannot open, yaHerd will return to Local Only mode and show a message."
    }
}

private struct RestartInstructionList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Swipe up from the bottom of the screen and pause to open the app switcher. On devices with a Home button, double-click the Home button.")
            Text("2. Swipe up on yaHerd to close it.")
            Text("3. Open yaHerd again from the Home Screen or App Library.")
            Text("4. Go to Settings > Sync and confirm iCloud Sync is enabled.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

private struct InfoRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
