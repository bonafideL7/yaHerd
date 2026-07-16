import SwiftUI

struct HomePastureCheckStartListView: View {
    let pastures: [DashboardPastureItem]
    let onSessionStarted: (UUID) -> Void

    init(pastures: [DashboardPastureItem], onSessionStarted: @escaping (UUID) -> Void = { _ in }) {
        self.pastures = pastures
        self.onSessionStarted = onSessionStarted
    }

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
                                FieldCheckSessionSetupView(suggestedPastureID: pasture.id, onSessionStarted: onSessionStarted)
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

struct WorkingSessionPastureStartListView: View {
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var pastureRepository: any PastureReferenceDataReader { workingDependencies.pastureReferenceReader }

    @State private var pastures: [PastureOption] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let onSessionCreated: (UUID) -> Void

    init(onSessionCreated: @escaping (UUID) -> Void = { _ in }) {
        self.onSessionCreated = onSessionCreated
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pastures…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else if pastures.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture before starting work animals.")
                )
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section("Start Work") {
                        ForEach(pastures) { pasture in
                            NavigationLink {
                                NewWorkingSessionView(
                                    suggestedPastureID: pasture.id,
                                    wrapsInNavigationStack: false,
                                    onSessionCreated: onSessionCreated
                                )
                            } label: {
                                workingSessionStartRow(pasture)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Start Work")
        .task {
            loadPasturesIfNeeded()
        }
        .alert("Can't Load Pastures", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func workingSessionStartRow(_ pasture: PastureOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pasture.name)
                .font(.headline)

            Text("Start a working session from this pasture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadPasturesIfNeeded() {
        guard pastures.isEmpty else { return }
        isLoading = true
        do {
            pastures = try pastureRepository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        isLoading = false
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )
    }
}

struct FieldCheckPastureStartListView: View {
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    private var pastureRepository: any PastureReferenceDataReader { fieldCheckDependencies.pastureReferenceReader }

    @State private var pastures: [PastureOption] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let onSessionStarted: (UUID) -> Void

    init(onSessionStarted: @escaping (UUID) -> Void = { _ in }) {
        self.onSessionStarted = onSessionStarted
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pastures…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else if pastures.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture before starting a pasture check.")
                )
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section("Start Check") {
                        ForEach(pastures) { pasture in
                            NavigationLink {
                                FieldCheckSessionSetupView(suggestedPastureID: pasture.id, onSessionStarted: onSessionStarted)
                            } label: {
                                fieldCheckStartRow(pasture)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Pasture Check")
        .task {
            loadPasturesIfNeeded()
        }
        .alert("Can't Load Pastures", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func fieldCheckStartRow(_ pasture: PastureOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pasture.name)
                .font(.headline)

            Text("Start a check for this pasture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadPasturesIfNeeded() {
        guard pastures.isEmpty else { return }
        isLoading = true
        do {
            pastures = try pastureRepository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        isLoading = false
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )
    }
}
