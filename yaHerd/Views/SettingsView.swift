//
//  SettingsView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("allowHardDelete") private var allowHardDelete = false

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
