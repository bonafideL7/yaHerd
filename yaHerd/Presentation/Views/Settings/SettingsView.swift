//
//  SettingsView.swift
//  yaHerd
//

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

                    Text("Data editing, sharing, and synchronization are disabled for this launch.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Setup") {                    
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
                        subtitle: "Configure tag colors used across animal records.",
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
            
            Section("Sharing") {
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    SettingsRow(
                        title: "Sync",
                        subtitle: "View storage mode and iCloud sync status.",
                        systemImage: "icloud"
                    )
                }

                NavigationLink {
                    HerdCollaborationView()
                } label: {
                    SettingsRow(
                        title: "Herd Collaboration",
                        subtitle: "Prepare the herd for sharing and review incoming invitations.",
                        systemImage: "person.2"
                    )
                }
            }
            
            Section("About") {
                NavigationLink {
                    AboutYaHerdView()
                } label: {
                    SettingsRow(
                        title: "About yaHerd",
                        subtitle: "App information and platform details.",
                        systemImage: "info.circle"
                    )
                }
            }
        }
        .navigationTitle("Settings")
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
    @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false
    
    var body: some View {
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
            
            Section("Animal List Swipe") {
                Toggle("Use hard delete for swipe actions", isOn: $hardDeleteOnSwipe)
                    .tint(.red)
                    .disabled(dataAccessMode.isRecoveryMode)
                
                Text("When off, swiping an animal archives the record. When on, swiping asks for confirmation before permanently deleting it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Herd Setup")
    }
}

struct DashboardRulesView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = false

    var body: some View {
        Form {
            Section("Navigation") {
                Toggle("Show Dashboard", isOn: $isDashboardEnabled)
                    .disabled(dataAccessMode.isRecoveryMode)
                
                Text("When off, the Dashboard tab is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dashboard Setup")
    }
}

struct PastureDefaultsView: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @AppStorage("targetAcresPerHeadDefault") private var targetAcresPerHeadDefault = 3.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100

    var body: some View {
        Form {
            Section("New Pasture Defaults") {
                Stepper(
                    "Target acres/head: \(targetAcresPerHeadDefault, format: .number.precision(.fractionLength(2)))",
                    value: $targetAcresPerHeadDefault,
                    in: 0.25...25.0,
                    step: 0.25
                )
                .disabled(dataAccessMode.isRecoveryMode)

                Stepper(
                    "Usable acreage: \(usableAcreagePercentDefault)%",
                    value: $usableAcreagePercentDefault,
                    in: 10...100
                )
                .disabled(dataAccessMode.isRecoveryMode)

                Text("Defaults are applied to newly created pasture records only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pasture Setup")
    }
}

private struct AboutYaHerdView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("yaHerd")
                        .font(.title2)
                        .bold()

                    Text("Beef cattle herd management")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("iOS 26+ • Swift 6 • SwiftUI • SwiftData")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("About")
    }
}
