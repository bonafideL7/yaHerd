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
                        subtitle: "Version, privacy, and acknowledgements.",
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
        }
        .navigationTitle("Herd Setup")
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
        }
        .navigationTitle("Dashboard Setup")
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
                Text("Herd records are stored in yaHerd app data and may be synchronized through your iCloud account when iCloud storage is enabled.")

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
    }
}
