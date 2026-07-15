//
//  SyncSettingsView.swift
//  yaHerd
//

import SwiftUI

struct SyncSettingsView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(\.recoveryModeController) private var recoveryModeController

    private let preferences: AppPreferencesProviding
    @State private var syncMode: SyncMode

    init(preferences: AppPreferencesProviding = AppPreferences()) {
        self.preferences = preferences
        self._syncMode = State(initialValue: preferences.syncMode)
    }

    var body: some View {
        List {
            if dataAccessMode.isRecoveryMode {
                Section("Recovery Mode") {
                    Label("Read-only in-memory store", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.red)

                    Text("Changes cannot be saved. iCloud sync and all collaboration operations are disabled for this launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Open Storage Recovery") {
                        recoveryModeController?.isPresentingCenter = true
                    }
                }
            }

            Section("Current Storage") {
                LabeledContent("Mode", value: syncMode.displayName)

                Text(syncMode.storageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("iCloud Sync") {
                switch syncMode {
                case .localOnly:
                    NavigationLink {
                        EnableICloudSyncView()
                    } label: {
                        Label("Enable iCloud Sync", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(dataAccessMode.isRecoveryMode)

                    Text("yaHerd stays offline-first. Enabling iCloud adds sync mirroring to the same local store, so data remains available without signal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .iCloud:
                    Label("iCloud Sync Enabled", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)

                    Text("Changes are saved locally first and sync through iCloud when the device is online and iCloud is available. App settings also sync through iCloud, and iCloud settings override this device when sync is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                NavigationLink {
                    SyncDiagnosticsView()
                } label: {
                    Label("Sync Diagnostics", systemImage: "stethoscope")
                }

                Text("Use this when sync is not behaving the same on every install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sync")
        .onAppear {
            syncMode = preferences.syncMode
        }
    }
}
