import SwiftUI

extension HomePastureCheckDueItem {
    var lastCheckDescription: String {
        guard let lastCheckDate else {
            return "No recorded pasture check."
        }

        return "Last checked \(lastCheckDate.formatted(date: .abbreviated, time: .omitted))."
    }
}

struct HomePastureCheckDueListView: View {
    let items: [HomePastureCheckDueItem]

    var body: some View {
        List {
            if items.isEmpty {
                Text("No pasture checks are due.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Start Check") {
                    ForEach(items) { item in
                        NavigationLink {
                            FieldCheckSessionDetailView(suggestedPastureID: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(item.activeAnimalCount) head")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Text(item.lastCheckDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pasture Checks Due")
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
                    description: Text("There are no current pasture, care, or record alerts.")
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
