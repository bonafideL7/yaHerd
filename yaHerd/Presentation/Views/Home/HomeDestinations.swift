import SwiftUI

struct HomePastureCheckStartListView: View {
    let pastures: [DashboardPastureItem]

    var body: some View {
        Group {
            if pastures.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture before starting a pasture check.")
                )
            } else {
                List {
                    Section("Start Check") {
                        ForEach(pastures) { pasture in
                            NavigationLink {
                                FieldCheckSessionDetailView(suggestedPastureID: pasture.id)
                            } label: {
                                pastureCheckStartRow(pasture)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Pasture Check")
    }

    private func pastureCheckStartRow(_ pasture: DashboardPastureItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                Text(pasture.activeAnimalCount == 1 ? "1 head" : "\(pasture.activeAnimalCount) head")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Start a check for this pasture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct HomeAlertsView: View {
    let alerts: [DashboardAlert]
    let openAnimalList: (AnimalListLaunchConfiguration) -> Void
    let openPastureList: (PastureListLaunchConfiguration) -> Void

    var body: some View {
        Group {
            if alerts.isEmpty {
                ContentUnavailableView(
                    "No Alerts",
                    systemImage: "checkmark.shield.fill",
                    description: Text("There are no current record alerts.")
                )
            } else {
                List {
                    Section("Current Alerts") {
                        ForEach(alerts) { alert in
                            alertRow(alert)
                        }
                    }
                }
            }
        }
        .navigationTitle("Alerts")
    }

    @ViewBuilder
    func alertRow(_ alert: DashboardAlert) -> some View {
        switch alert.destination {
        case .some(.animal(let animalID)):
            NavigationLink {
                AnimalDetailView(animalID: animalID)
            } label: {
                alertLabel(alert)
            }
        case .some(.pasture(let pastureID)):
            NavigationLink {
                PastureDetailView(pastureID: pastureID)
            } label: {
                alertLabel(alert)
            }
        case .some(.animalList(let kind)):
            Button {
                openAnimalList(.dashboard(kind))
            } label: {
                alertLabel(alert, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .some(.pastureList):
            Button {
                openPastureList(.all)
            } label: {
                alertLabel(alert, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .none:
            alertLabel(alert)
        }
    }

    func alertLabel(_ alert: DashboardAlert, showsChevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            DashboardAlertRow(alert: alert, colorForSeverity: alertSeverityColor)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    func alertSeverityColor(_ severity: DashboardAlertSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}
