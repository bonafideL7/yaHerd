//
//  EnableICloudSyncView.swift
//  yaHerd
//

import SwiftUI

struct EnableICloudSyncView: View {
    private let checker: ICloudAvailabilityChecking
    private let preferences: AppPreferencesProviding
    private let settingsOpener: SystemSettingsOpening

    @State private var isChecking = false
    @State private var iCloudStatus: ICloudAccountStatus?
    @State private var statusMessage: String?
    @State private var didEnableSync = false

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

                Text("yaHerd can mirror your local SwiftData store through iCloud so the same herd data is available on your Apple devices.")
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
                    message: "After enabling sync, restart yaHerd so the app can reopen the store with iCloud mirroring enabled."
                )
            }

            Section {
                Button {
                    checkICloudAvailability()
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Text("Check iCloud Availability")
                    }
                }
                .disabled(isChecking || didEnableSync)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let unavailableReason {
                iCloudHelpSection(for: unavailableReason)
            }

            if canEnableSync && !didEnableSync {
                Section {
                    Button("Enable iCloud Sync") {
                        enableSync()
                    }

                    Text("This changes the app preference to use iCloud mirroring on next launch. Your existing local data remains local and will be mirrored by SwiftData/CloudKit after restart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if didEnableSync {
                Section("Next Step") {
                    Label("iCloud Sync will be enabled after restart", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)

                    Text("Close and reopen yaHerd. After restart, changes continue saving locally and sync through iCloud when available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Enable iCloud Sync")
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
                    Text("4. Return to yaHerd and check iCloud availability again.")
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

                Text("Confirm the device is signed in to iCloud, iCloud Drive is enabled, and the device has a network connection. Then return to yaHerd and check again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkICloudAvailability() {
        isChecking = true
        iCloudStatus = nil
        statusMessage = nil

        Task {
            let result = await checker.checkAvailability()

            await MainActor.run {
                iCloudStatus = result

                switch result {
                case .available:
                    statusMessage = "iCloud is available. You can enable sync."

                case .unavailable(let reason):
                    statusMessage = reason.message
                }

                isChecking = false
            }
        }
    }

    private func enableSync() {
        preferences.syncMode = .iCloud
        didEnableSync = true
        statusMessage = "iCloud Sync preference saved. Restart yaHerd to apply it."
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
