import LucideIcons
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @EnvironmentObject private var dependencies: AppDependencies

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @State private var viewModel = DashboardViewModel()
    @State private var searchText = ""
    @State private var pastureFilter: DashboardPastureFilter = .all

    private var repository: any DashboardRepository {
        dependencies.dashboardRepository
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

    private var activeSessionSummary: DashboardWorkingSessionSummary? {
        viewModel.snapshot?.activeSession
    }

    var body: some View {
        List {
            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults) { animal in
                        NavigationLink(value: DashboardRoute.animal(animal.id)) {
                            DashboardAnimalRow(animal: animal)
                        }
                    }
                }
            }

            Section("Active Work") {
                if viewModel.snapshot == nil {
                    ProgressView()
                } else if let session = activeSessionSummary {
                    DashboardActiveSessionCard(session: session)
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
                            DashboardPastureRow(pasture: pasture)
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
                    DashboardAlertRow(alert: alert, colorForSeverity: color)
                }
            } else {
                DashboardAlertRow(alert: alert, colorForSeverity: color)
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

