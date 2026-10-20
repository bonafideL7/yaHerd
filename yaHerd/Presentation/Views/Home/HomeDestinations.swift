import SwiftUI

enum PastureSessionStartKind {
    case fieldCheck
    case working

    var navigationTitle: String {
        switch self {
        case .fieldCheck: "Pasture Check"
        case .working: "Work Animals"
        }
    }
}

/// Both workflows use the same live pasture roster, row presentation, and navigation step.
struct PastureSessionStartListView: View {
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies

    @State private var rows: [PastureSessionStartRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let kind: PastureSessionStartKind
    let onPastureSelected: (UUID) -> Void

    init(kind: PastureSessionStartKind, onPastureSelected: @escaping (UUID) -> Void) {
        self.kind = kind
        self.onPastureSelected = onPastureSelected
    }

    private var pastureReader: any PastureReferenceDataReader {
        switch kind {
        case .fieldCheck: fieldCheckDependencies.pastureReferenceReader
        case .working: workingDependencies.pastureReferenceReader
        }
    }

    private var animalReader: (any AnimalReferenceQueryReading)? {
        switch kind {
        case .fieldCheck: fieldCheckDependencies.animalReferenceQueryReader
        case .working: workingDependencies.animalReferenceQueryReader
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pastures…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Can't Load Pastures", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { @MainActor in await loadPastures() }
                    }
                }
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture before starting a session.")
                )
            } else {
                List {
                    Section("Select Pasture") {
                        ForEach(rows) { row in
                            Button {
                                onPastureSelected(row.pasture.id)
                            } label: {
                                HStack(spacing: 12) {
                                    pastureRow(row)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await loadPastures() }
            }
        }
        .navigationTitle(kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPastures() }
    }

    private func pastureRow(_ row: PastureSessionStartRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.pasture.name)
                    .font(.headline)

                Spacer()

                Text(row.total == 1 ? "1 head" : "\(row.total) head")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(row.animalTypeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadPastures() async {
        // Preserve the list during pull-to-refresh so its refresh task is not cancelled.
        if rows.isEmpty { isLoading = true }
        do {
            let pastures = try pastureReader.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard let animalReader else {
                throw PastureStartLoadError.animalReaderUnavailable
            }
            // One active, pasture-assigned snapshot, not a separate query per row.
            // It excludes removed, archived, unassigned and working-pen Animals.
            let animals = try await animalReader.fetchAnimalReferenceSnapshot(
                matching: AnimalReferenceQuery(pastureScope: .assignedPasture, location: .pasture)
            )
            try Task.checkCancellation()

            var counts: [UUID: [AnimalType: Int]] = [:]
            for animal in animals {
                guard let pastureID = animal.pastureID else { continue }
                counts[pastureID, default: [:]][animal.animalType, default: 0] += 1
            }

            rows = pastures.map { PastureSessionStartRow(pasture: $0, counts: counts[$0.id] ?? [:]) }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            rows = []
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        isLoading = false
    }
}

private enum PastureStartLoadError: LocalizedError {
    case animalReaderUnavailable

    var errorDescription: String? {
        "Animal roster data is unavailable. Reopen the pasture selection screen to retry."
    }
}

private struct PastureSessionStartRow: Identifiable {
    let pasture: PastureOption
    let counts: [AnimalType: Int]

    var id: UUID { pasture.id }
    var total: Int { counts.values.reduce(0, +) }

    var animalTypeSummary: String {
        let orderedTypes: [AnimalType] = [.cow, .bull, .heifer, .steer, .calf]
        let descriptions = orderedTypes.compactMap { type -> String? in
            guard let count = counts[type], count > 0 else { return nil }
            let plural = type == .calf ? "calves" : "\(type.label.lowercased())s"
            return "\(count) \(count == 1 ? type.label.lowercased() : plural)"
        }
        return descriptions.isEmpty ? "No animals" : descriptions.joined(separator: " · ")
    }
}

struct HomeAlertsView: View {
    @Environment(AppNavigationState.self) private var navigation

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
            Button {
                navigation.openAnimal(animalID)
            } label: {
                alertLabel(alert, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .some(.pasture(let pastureID)):
            Button {
                navigation.openPasture(pastureID)
            } label: {
                alertLabel(alert, showsChevron: true)
            }
            .buttonStyle(.plain)
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
                    .foregroundStyle(.primary)
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
