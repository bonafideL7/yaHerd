//
//  DashboardView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData
import LucideIcons

struct DashboardView: View {

    @Environment(\.modelContext) private var context
    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query private var animals: [Animal]
    @Query private var pastures: [Pasture]

    private var alerts: [DashboardAlert] {
        DashboardService.generateAlerts(
            animals: animals,
            pastures: pastures,
            pregCheckIntervalDays: pregCheckIntervalDays,
            treatmentIntervalDays: treatmentIntervalDays,
            enablePastureOverstockWarnings: enablePastureOverstockWarnings,
            pastureCapacity: pastureCapacity
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Alerts") {
                    if alerts.isEmpty {
                        Text("No alerts. Herd looks good.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts) { alert in
                            alertRow(alert)
                        }
                    }
                }

                Section("Overview") {

                    Label {
                        Text("\(animals.count) total animals")
                    } icon: {
                        if let base = UIImage(lucideId: "beef") {
                            Image(uiImage: base.scaled(to: CGSize(width: 28, height: 28)))
                                .renderingMode(.template)
                        }
                    }

                    Label("\(pastures.count) pastures", systemImage: "leaf")
                }

            }
            .navigationTitle("Dashboard")
        }
    }

    private func alertRow(_ alert: DashboardAlert) -> some View {
        HStack {
            if let icon = UIImage(lucideId: alert.icon) {
                Image(uiImage: icon.scaled(to: CGSize(width: 24, height: 24)))
                    .renderingMode(.template)
                    .foregroundStyle(color(for: alert.severity))
            }

            VStack(alignment: .leading) {
                Text(alert.title)
                    .font(.headline)
                if let message = alert.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for severity: AlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }
}
