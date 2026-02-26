//
//  DashboardView.swift
//  yaHerd
//

import SwiftUI
import SwiftData
import LucideIcons

struct DashboardView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query private var animals: [Animal]
    @Query private var pastures: [Pasture]
    @Query(sort: \WorkingSession.date, order: .reverse) private var workingSessions: [WorkingSession]

    @State private var searchText: String = ""
    @State private var pastureFilter: PastureDashboardFilter = .all
    @State private var showingAddAnimal = false
    @State private var showingAddPasture = false
    @State private var showingNewWorkingSession = false

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

    private var activeSession: WorkingSession? {
        workingSessions.first(where: { $0.status == .active })
    }

    private var aliveAnimals: [Animal] {
        animals.filter { $0.status == .alive }
    }

    private var workingPenAnimals: [Animal] {
        aliveAnimals.filter { $0.location == .workingPen }
    }

    private var unassignedAnimals: [Animal] {
        aliveAnimals.filter { $0.location == .pasture && $0.pasture == nil }
    }

    private var searchResults: [Animal] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let matches = aliveAnimals.filter {
            $0.tagNumber.localizedCaseInsensitiveContains(q)
            || tagColorLibrary.formattedTag(for: $0).localizedCaseInsensitiveContains(q)
        }

        return matches
            .sorted { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedAscending }
            .prefix(10)
            .map { $0 }
    }

    private var filteredPastures: [Pasture] {
        let sorted = pastures.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch pastureFilter {
        case .all:
            return sorted
        case .overstocked:
            return sorted.filter { pasture in
                let alive = pasture.animals.filter { $0.status == .alive }.count
                return PastureAnalytics(
                    pasture: pasture,
                    aliveAnimals: alive,
                    fallbackCapacityHead: Double(pastureCapacity)
                ).isOverstocked
            }
        case .underutilized:
            return sorted.filter { pasture in
                let alive = pasture.animals.filter { $0.status == .alive }.count
                return PastureAnalytics(
                    pasture: pasture,
                    aliveAnimals: alive,
                    fallbackCapacityHead: Double(pastureCapacity)
                ).isUnderutilized
            }
        }
    }

    var body: some View {
        List {

            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults) { animal in
                        NavigationLink(value: animal) {
                            animalRow(animal)
                        }
                    }
                }
            }

            Section("Active Work") {
                if let session = activeSession {
                    NavigationLink {
                        WorkingSessionDetailView(session: session)
                    } label: {
                        WorkingSessionSummaryCard(session: session)
                    }
                } else {
                    Button {
                        showingNewWorkingSession = true
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
                if alerts.isEmpty {
                    Text("No alerts. Herd looks good.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alerts, id: \.id) { alert in
                        alertRow(alert)
                    }
                }
            }

            Section("Overview") {
                DashboardMetricsGrid(
                    items: [
                        DashboardMetric(
                            title: "Alive",
                            value: aliveAnimals.count,
                            iconLucide: "beef",
                            destination: .animalList(.alive)
                        ),
                        DashboardMetric(
                            title: "Working Pen",
                            value: workingPenAnimals.count,
                            iconSystem: "wrench",
                            destination: .animalList(.workingPen)
                        ),
                        DashboardMetric(
                            title: "Unassigned",
                            value: unassignedAnimals.count,
                            iconLucide: "map-pin-off",
                            destination: .animalList(.unassigned)
                        ),
                        DashboardMetric(
                            title: "Pastures",
                            value: pastures.count,
                            iconSystem: "leaf",
                            destination: .pastureList
                        )
                    ],
                    onNavigate: navigate
                )
                .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                if pastures.isEmpty {
                    ContentUnavailableView(
                        "No pastures",
                        systemImage: "leaf",
                        description: Text("Create a pasture to track stocking and grazing.")
                    )
                } else {
                    Picker("Pastures", selection: $pastureFilter) {
                        ForEach(PastureDashboardFilter.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filteredPastures.isEmpty {
                        Text("No matching pastures.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredPastures) { pasture in
                        NavigationLink(value: pasture) {
                            pastureRow(pasture)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                pasture.lastGrazedDate = .now
                                try? context.save()
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
                        showingAddAnimal = true
                    } label: {
                        Label("Add Animal", systemImage: "plus")
                    }

                    Button {
                        showingAddPasture = true
                    } label: {
                        Label("Add Pasture", systemImage: "leaf")
                    }

                    Button {
                        showingNewWorkingSession = true
                    } label: {
                        Label("New Working Session", systemImage: "wrench")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAnimal) {
            AddAnimalView()
        }
        .sheet(isPresented: $showingAddPasture) {
            AddPastureView()
        }
        .sheet(isPresented: $showingNewWorkingSession) {
            NewWorkingSessionView()
        }
    }

    private func alertRow(_ alert: DashboardAlert) -> some View {
        Group {
            if let destination = alert.destination {
                switch destination {
                case .animal(let animal):
                    NavigationLink(value: animal) {
                        alertRowContent(alert)
                    }
                case .pasture(let pasture):
                    NavigationLink(value: pasture) {
                        alertRowContent(alert)
                    }
                case .animalList(let kind):
                    NavigationLink(value: DashboardRoute.animalList(kind)) {
                        alertRowContent(alert)
                    }
                case .pastureList:
                    NavigationLink(value: DashboardRoute.pastureList) {
                        alertRowContent(alert)
                    }
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

    private func navigate(_ destination: DashboardAlertDestination) {
        // NOTE: We intentionally drive dashboard navigation via the shared path (value-based)
        // to avoid SwiftUI List issues when multiple NavigationLinks exist in the same row.
        switch destination {
        case .animal(let animal):
            nav.push(animal)
        case .pasture(let pasture):
            nav.push(pasture)
        case .animalList(let kind):
            nav.push(DashboardRoute.animalList(kind))
        case .pastureList:
            nav.push(DashboardRoute.pastureList)
        }
    }

    private func animalRow(_ animal: Animal) -> some View {
        HStack(spacing: 12) {
            let def = tagColorLibrary.resolvedDefinition(for: animal)
            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(tagColorLibrary.formattedTag(for: animal))
                    .font(.headline)

                HStack(spacing: 6) {
                    Text((animal.sex ?? .female).label)
                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pasture = animal.pasture?.name {
                        Text("• \(pasture)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func pastureRow(_ pasture: Pasture) -> some View {
        let alive = pasture.animals.filter { $0.status == .alive }.count
        let analytics = PastureAnalytics(
            pasture: pasture,
            aliveAnimals: alive,
            fallbackCapacityHead: Double(pastureCapacity)
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                if analytics.isOverstocked {
                    Label("Over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if analytics.isUnderutilized {
                    Label("Low", systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("\(alive) head")
                if analytics.acres > 0 {
                    Text("• \(analytics.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                }
                if let cap = analytics.capacityHead {
                    Text("• cap \(Int(cap))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let cap = analytics.capacityHead, cap > 0 {
                ProgressView(value: Double(alive), total: cap)
            }
        }
    }

    private func color(for severity: AlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }
}

private enum PastureDashboardFilter: CaseIterable, Hashable {
    case all
    case overstocked
    case underutilized

    var label: String {
        switch self {
        case .all: return "All"
        case .overstocked: return "Over"
        case .underutilized: return "Low"
        }
    }
}

private struct DashboardMetric: Identifiable {
    let id: String
    let title: String
    let value: Int
    var iconSystem: String? = nil
    var iconLucide: String? = nil
    var destination: DashboardAlertDestination?

    init(
        title: String,
        value: Int,
        iconSystem: String? = nil,
        iconLucide: String? = nil,
        destination: DashboardAlertDestination? = nil
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
    let onNavigate: (DashboardAlertDestination) -> Void

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
    private var done: Int { session.queueItems.filter { $0.status == .done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.protocolName)
                    .font(.headline)
                Spacer()
                Text("Continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                if let source = session.sourcePasture?.name {
                    Text("• \(source)")
                }
                Spacer()
                if total > 0 {
                    Text("\(done)/\(total)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            }
        }
        .padding(.vertical, 4)
    }
}
