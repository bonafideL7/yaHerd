import LucideIcons
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query(sort: \WorkingSession.date, order: .reverse) private var workingSessions: [WorkingSession]

    @State private var viewModel = DashboardViewModel()
    @State private var searchText = ""
    @State private var pastureFilter: DashboardPastureFilter = .all

    private var repository: any DashboardRepository {
        SwiftDataDashboardRepository(context: context)
    }

    private var configuration: DashboardConfiguration {
        DashboardConfiguration(
            pregnancyCheckIntervalDays: pregCheckIntervalDays,
            treatmentIntervalDays: treatmentIntervalDays,
            enablePastureOverstockWarnings: enablePastureOverstockWarnings,
            fallbackPastureCapacity: pastureCapacity
        )
    }

    private var configurationSignature: String {
        [
            String(configuration.pregnancyCheckIntervalDays),
            String(configuration.treatmentIntervalDays),
            String(configuration.enablePastureOverstockWarnings),
            String(configuration.fallbackPastureCapacity)
        ].joined(separator: ":")
    }

    private var searchResults: [DashboardAnimalItem] {
        viewModel.searchResults(matching: searchText) { animal in
            tagColorLibrary.formattedTag(
                tagNumber: animal.displayTagNumber,
                colorID: animal.displayTagColorID
            )
        }
    }

    private var filteredPastures: [DashboardPastureItem] {
        viewModel.pastures(filteredBy: pastureFilter)
    }

    private var activeSession: WorkingSession? {
        guard let summary = viewModel.snapshot?.activeSession else { return nil }

        return workingSessions.first { session in
            session.status == .active
                && session.protocolName == summary.protocolName
                && session.date == summary.date
                && session.sourcePasture?.name == summary.sourcePastureName
        }
    }

    var body: some View {
        List {
            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults) { animal in
                        NavigationLink(value: DashboardRoute.animal(animal.id)) {
                            animalRow(animal)
                        }
                    }
                }
            }

            Section("Active Work") {
                if viewModel.snapshot == nil {
                    ProgressView()
                } else if let session = activeSession {
                    NavigationLink {
                        WorkingSessionDetailView(session: session)
                    } label: {
                        WorkingSessionSummaryCard(session: session)
                    }
                } else {
                    Button {
                        viewModel.isPresentingNewWorkingSession = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Start working session")
                            Spacer()
                        }
                    }
                }
            }

            Section("Alerts") {
                if viewModel.snapshot == nil {
                    ProgressView()
                } else if let snapshot = viewModel.snapshot, snapshot.alerts.isEmpty {
                    Text("No alerts. Herd looks good.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.snapshot?.alerts ?? []) { alert in
                        alertRow(alert)
                    }
                }
            }

            Section("Overview") {
                DashboardMetricsGrid(
                    items: metricItems,
                    onNavigate: navigate
                )
                .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                if viewModel.snapshot == nil {
                    ProgressView()
                } else if viewModel.snapshot?.pastures.isEmpty ?? true {
                    ContentUnavailableView(
                        "No pastures",
                        systemImage: "leaf",
                        description: Text("Create a pasture to track stocking and grazing.")
                    )
                } else {
                    Picker("Pastures", selection: $pastureFilter) {
                        ForEach(DashboardPastureFilter.allCases, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filteredPastures.isEmpty {
                        Text("No matching pastures.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredPastures) { pasture in
                        NavigationLink(value: DashboardRoute.pasture(pasture.id)) {
                            pastureRow(pasture)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                viewModel.markPastureGrazedToday(
                                    pastureID: pasture.id,
                                    configuration: configuration,
                                    using: repository
                                )
                            } label: {
                                Label("Grazed today", systemImage: "calendar")
                            }
                            .tint(.green)
                        }
                    }
                }
            } header: {
                Text("Pastures")
            }
        }
        .navigationTitle("Dashboard")
        .searchable(text: $searchText, prompt: "Search tag…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.isPresentingAddAnimal = true
                    } label: {
                        Label("Add Animal", systemImage: "plus")
                    }

                    Button {
                        viewModel.isPresentingAddPasture = true
                    } label: {
                        Label("Add Pasture", systemImage: "leaf")
                    }

                    Button {
                        viewModel.isPresentingNewWorkingSession = true
                    } label: {
                        Label("New Working Session", systemImage: "wrench")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            viewModel.load(configuration: configuration, using: repository)
        }
        .onChange(of: configurationSignature) { _, _ in
            viewModel.load(configuration: configuration, using: repository)
        }
        .onAppear {
            viewModel.load(configuration: configuration, using: repository)
        }
        .sheet(isPresented: addAnimalBinding) {
            AddAnimalView()
        }
        .sheet(isPresented: addPastureBinding) {
            AddPastureView()
        }
        .sheet(isPresented: newWorkingSessionBinding) {
            NewWorkingSessionView()
        }
        .alert("Dashboard Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var metricItems: [DashboardMetric] {
        let overview = viewModel.snapshot?.overview

        return [
            DashboardMetric(
                title: "Active",
                value: overview?.activeAnimalCount ?? 0,
                iconLucide: "beef",
                destination: .animalList(.active)
            ),
            DashboardMetric(
                title: "Working Pen",
                value: overview?.workingPenCount ?? 0,
                iconSystem: "wrench",
                destination: .animalList(.workingPen)
            ),
            DashboardMetric(
                title: "Unassigned",
                value: overview?.unassignedAnimalCount ?? 0,
                iconLucide: "map-pin-off",
                destination: .animalList(.unassigned)
            ),
            DashboardMetric(
                title: "Pastures",
                value: overview?.pastureCount ?? 0,
                iconSystem: "leaf",
                destination: .pastureList
            )
        ]
    }

    private var addAnimalBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPresentingAddAnimal },
            set: { viewModel.isPresentingAddAnimal = $0 }
        )
    }

    private var addPastureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPresentingAddPasture },
            set: { viewModel.isPresentingAddPasture = $0 }
        )
    }

    private var newWorkingSessionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPresentingNewWorkingSession },
            set: { viewModel.isPresentingNewWorkingSession = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func alertRow(_ alert: DashboardAlert) -> some View {
        Group {
            if let destination = alert.destination {
                NavigationLink(value: route(for: destination)) {
                    alertRowContent(alert)
                }
            } else {
                alertRowContent(alert)
            }
        }
        .padding(.vertical, 4)
    }

    private func alertRowContent(_ alert: DashboardAlert) -> some View {
        HStack(spacing: 12) {
            if let icon = UIImage(lucideId: alert.icon) {
                Image(uiImage: icon.scaled(to: CGSize(width: 22, height: 22)))
                    .renderingMode(.template)
                    .foregroundStyle(color(for: alert.severity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.headline)
                if let message = alert.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func navigate(_ destination: DashboardNavigationTarget) {
        nav.push(route(for: destination))
    }

    private func route(for destination: DashboardNavigationTarget) -> DashboardRoute {
        switch destination {
        case .animal(let id):
            return .animal(id)
        case .pasture(let id):
            return .pasture(id)
        case .animalList(let kind):
            return .animalList(kind)
        case .pastureList:
            return .pastureList
        }
    }

    private func animalRow(_ animal: DashboardAnimalItem) -> some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)

            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name
                )

                HStack(spacing: 6) {
                    Text(animal.sex.label)
                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pastureName = animal.pastureName {
                        Text("• \(pastureName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func pastureRow(_ pasture: DashboardPastureItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                if pasture.isOverstocked {
                    Label("Over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if pasture.isUnderutilized {
                    Label("Low", systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("\(pasture.activeAnimalCount) head")
                if pasture.acres > 0 {
                    Text("• \(pasture.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                }
                if let capacity = pasture.capacityHead {
                    Text("• cap \(Int(capacity))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let capacity = pasture.capacityHead, capacity > 0 {
                ProgressView(value: Double(pasture.activeAnimalCount), total: capacity)
            }
        }
    }

    private func color(for severity: DashboardAlertSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .warning:
            return .yellow
        case .info:
            return .blue
        }
    }
}

private struct DashboardMetric: Identifiable {
    let id: String
    let title: String
    let value: Int
    var iconSystem: String? = nil
    var iconLucide: String? = nil
    var destination: DashboardNavigationTarget?

    init(
        title: String,
        value: Int,
        iconSystem: String? = nil,
        iconLucide: String? = nil,
        destination: DashboardNavigationTarget? = nil
    ) {
        self.id = title
        self.title = title
        self.value = value
        self.iconSystem = iconSystem
        self.iconLucide = iconLucide
        self.destination = destination
    }
}

private struct DashboardMetricsGrid: View {
    let items: [DashboardMetric]
    let onNavigate: (DashboardNavigationTarget) -> Void

    private var rows: [[DashboardMetric]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            let end = min(start + 2, items.count)
            return Array(items[start..<end])
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { item in
                        cell(item)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count == 1 {
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func cell(_ item: DashboardMetric) -> some View {
        if let destination = item.destination {
            Button {
                onNavigate(destination)
            } label: {
                card(item)
            }
            .buttonStyle(.plain)
        } else {
            card(item)
        }
    }

    private func card(_ item: DashboardMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let lucide = item.iconLucide, let base = UIImage(lucideId: lucide) {
                    Image(uiImage: base.scaled(to: CGSize(width: 22, height: 22)))
                        .renderingMode(.template)
                } else if let system = item.iconSystem {
                    Image(systemName: system)
                }
                Spacer()
            }

            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(item.value)")
                .font(.title2.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct WorkingSessionSummaryCard: View {
    let session: WorkingSession

    private var total: Int { session.queueItems.count }
    private var completed: Int { session.queueItems.filter { $0.status == .done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.protocolName)
                    .font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let source = session.sourcePasture?.name {
                    Text("• \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if total > 0 {
                    Text("\(completed)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
