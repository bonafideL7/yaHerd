//
//  SettingsView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30  // per 30 acres default guideline

    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    NavigationLink("About") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("yaherd")
                                .font(.title2)
                                .bold()
                            Text("Beef cattle herd management")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("iOS 18 • Swift 6 • SwiftUI • SwiftData")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
                
                Section("Dashboard Rules") {
                    Stepper("Preg Check overdue after \(pregCheckIntervalDays) days", value: $pregCheckIntervalDays, in: 30...365)
                    Stepper("Treatment overdue after \(treatmentIntervalDays) days", value: $treatmentIntervalDays, in: 30...365)
                    
                    Toggle("Warn about pasture overcrowding", isOn: $enablePastureOverstockWarnings)
                    Stepper("Pasture capacity: \(pastureCapacity) animals", value: $pastureCapacity, in: 10...200)
                }
                
                Section("Danger Zone") {
                    Toggle("Enable Hard Delete", isOn: $allowHardDelete)
                        .tint(.red)

                    Text("When enabled, animals can be permanently removed. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    NavigationLink("Import / Export") {
                        ImportExportView()
                    }
                }

                Section("Debug") {
                    Button("Reset All (dev)") {
                        // developer-only placeholder; implement carefully
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
