//
//  ManagementView.swift
//  yaHerd
//

import SwiftUI

struct ManagementView: View {
    var body: some View {
        List {
            Section("Setup") {                    
                NavigationLink {
                    DashboardRulesView()
                } label: {
                    ManagementRow(
                        title: "Dashboard",
                        subtitle: "Configure overdue alerts and pasture warning thresholds.",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                }
                
                NavigationLink {
                    HerdSetupView()
                } label: {
                    ManagementRow(
                        title: "Herd",
                        subtitle: "Manage tag colors used across animal records.",
                        systemImage: "tag"
                    )
                }

                NavigationLink {
                    PastureDefaultsView()
                } label: {
                    ManagementRow(
                        title: "Pasture",
                        subtitle: "Set default stocking and usable acreage assumptions.",
                        systemImage: "leaf"
                    )
                }
            }
            
            NavigationLink {
                SyncSettingsView()
            } label: {
                ManagementRow(
                    title: "Sync",
                    subtitle: "View storage mode and iCloud sync status.",
                    systemImage: "icloud"
                )
            }
            
            Section("About") {
                NavigationLink {
                    AboutYaHerdView()
                } label: {
                    ManagementRow(
                        title: "About yaHerd",
                        subtitle: "App information and platform details.",
                        systemImage: "info.circle"
                    )
                }
            }
        }
        .navigationTitle("Manage")
    }
}

private struct ManagementRow: View {
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
                
                Text("When off, swiping an animal archives the record. When on, swiping permanently deletes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Herd Setup")
    }
}

struct DashboardRulesView: View {
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = false
    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    var body: some View {
        Form {
            Section("Navigation") {
                Toggle("Show Dashboard", isOn: $isDashboardEnabled)
                
                Text("When off, the Dashboard tab is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Animal Alerts") {
                Stepper("Preg check overdue after \(pregCheckIntervalDays) days", value: $pregCheckIntervalDays, in: 30...365)
                Stepper("Treatment overdue after \(treatmentIntervalDays) days", value: $treatmentIntervalDays, in: 30...365)
            }

            Section("Pasture Alerts") {
                Toggle("Warn about pasture overcrowding", isOn: $enablePastureOverstockWarnings)
                Stepper("Pasture capacity: \(pastureCapacity) animals", value: $pastureCapacity, in: 1...200)

                Text("These values control dashboard warning logic. They do not change existing pasture records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dashboard Setup")
    }
}

struct PastureDefaultsView: View {
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

                Stepper(
                    "Usable acreage: \(usableAcreagePercentDefault)%",
                    value: $usableAcreagePercentDefault,
                    in: 10...100
                )

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
