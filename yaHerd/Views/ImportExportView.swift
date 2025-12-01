//
//  ImportExportView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

struct ImportExportView: View {
    var body: some View {
        Form {
            Section("Export") {
                Text("JSON / CSV export tools will appear here.")
                    .foregroundStyle(.secondary)
            }

            Section("Import") {
                Text("Import (CSV/JSON) with validation will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Import & Export")
    }
}
