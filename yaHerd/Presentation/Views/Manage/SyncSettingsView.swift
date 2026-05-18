//
//  SyncSettingsView.swift
//  yaHerd
//

import SwiftUI

struct SyncSettingsView: View {
    private let preferences: AppPreferencesProviding
    @State private var syncMode: SyncMode

    init(preferences: AppPreferencesProviding = AppPreferences()) {
        self.preferences = preferences
        self._syncMode = State(initialValue: preferences.syncMode)
    }

    var body: some View {
        List {
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

                    Text("yaHerd stays offline-first. Enabling iCloud adds sync mirroring to the same local store, so data remains available without signal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .iCloud:
                    Label("iCloud Sync Enabled", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)

                    Text("Changes are saved locally first and sync through iCloud when the device is online and iCloud is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sync")
        .onAppear {
            syncMode = preferences.syncMode
        }
    }
}
