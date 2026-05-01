//
//  SettingsView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = true
    @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false
    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30  // per 30 acres default guideline
    @AppStorage("targetAcresPerHeadDefault") private var targetAcresPerHeadDefault = 1.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100


    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    Toggle("Show Dashboard", isOn: $isDashboardEnabled)

                    Text("When off, the Dashboard tab is hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink("About") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("yaherd")
                                .font(.title2)
                                .bold()
                            Text("Beef cattle herd management")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("iOS 26+ • Swift 6 • SwiftUI • SwiftData")
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
                    Stepper("Pasture capacity: \(pastureCapacity) animals", value: $pastureCapacity, in: 1...200)
                }
                
                Section("Pasture Defaults") {
                    Stepper("Default target acres/head: \(targetAcresPerHeadDefault, format: .number.precision(.fractionLength(2)))",
                            value: $targetAcresPerHeadDefault, in: 0.1...3.0, step: 0.1)

                    Stepper("Default usable acreage %: \(usableAcreagePercentDefault)%",
                            value: $usableAcreagePercentDefault, in: 10...100)
                }

                
                Section("Animal List Swipe") {
                    Toggle("Use hard delete for swipe actions", isOn: $hardDeleteOnSwipe)
                        .tint(.red)

                    Text("When off, swiping an animal archives the record. When on, swiping permanently deletes it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    NavigationLink("Import / Export") {
                        ImportExportView()
                    }
                }

                Section("Tags") {
                    NavigationLink("Tag Colors") {
                        TagColorLibraryView()
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
