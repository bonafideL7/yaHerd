import LucideIcons
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var dependencies: AppDependencies

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @State private var viewModel = DashboardViewModel()
    @State private var fieldChecksModel = FieldChecksViewModel()
    @State private var isOverviewExpanded = true
    @State private var isStartingFieldCheck = false
    private let onShowSettings: () -> Void

    init(onShowSettings: @escaping () -> Void = {}) {
        self.onShowSettings = onShowSettings
    }

    private var repository: any DashboardRepository {
        dependencies.dashboardRepository
    }

    private var fieldCheckRepository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
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

    private var snapshot: DashboardSnapshot? {
        viewModel.snapshot
    }

    private var overview: DashboardOverview? {
        snapshot?.overview
    }

    private var activeSessionSummary: DashboardWorkingSessionSummary? {
        snapshot?.activeSession
    }

    private var alerts: [DashboardAlert] {
        snapshot?.alerts ?? []
    }

    private var activeAnimals: [DashboardAnimalItem] {
        snapshot?.searchableAnimals ?? []
    }

    private var pastures: [DashboardPastureItem] {
        snapshot?.pastures ?? []
    }

    private var overstockedPastures: [DashboardPastureItem] {
        pastures
            .filter(\.isOverstocked)
            .sorted { lhs, rhs in
                let leftOverage = Double(lhs.activeAnimalCount) - (lhs.capacityHead ?? 0)
                let rightOverage = Double(rhs.activeAnimalCount) - (rhs.capacityHead ?? 0)
                if leftOverage != rightOverage { return leftOverage > rightOverage }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var rotationReadyPastures: [DashboardPastureItem] {
        pastures
            .filter(\.isRotationReady)
            .sorted { lhs, rhs in
                if lhs.activeAnimalCount != rhs.activeAnimalCount {
                    return lhs.activeAnimalCount < rhs.activeAnimalCount
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var underutilizedPastures: [DashboardPastureItem] {
        pastures
            .filter(\.isUnderutilized)
            .sorted { lhs, rhs in
                let leftUtilization = lhs.metrics.utilizationPercent ?? 0
                let rightUtilization = rhs.metrics.utilizationPercent ?? 0
                if leftUtilization != rightUtilization { return leftUtilization < rightUtilization }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var pasturesMissingStockingData: [DashboardPastureItem] {
        pastures
            .filter { pasture in
                pasture.acres <= 0 || pasture.metrics.targetAcresPerHead == nil
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var pastureAssignedAnimalCount: Int {
        activeAnimals.filter { $0.location == .pasture && $0.pastureID != nil }.count
    }

    private var workingPenAnimalCount: Int {
        overview?.workingPenCount ?? activeAnimals.filter { $0.location == .workingPen }.count
    }

    private var unassignedAnimalCount: Int {
        overview?.unassignedAnimalCount ?? activeAnimals.filter { $0.location == .pasture && $0.pastureID == nil }.count
    }

    private var pastureAssignmentRateText: String {
        guard !activeAnimals.isEmpty else { return "No active animals" }
        let percentage = Double(pastureAssignedAnimalCount) / Double(activeAnimals.count)
        return percentage.formatted(.percent.precision(.fractionLength(0)))
    }

    private var averageUtilizationText: String {
        let utilizationValues = pastures.compactMap { $0.metrics.utilizationPercent }
        guard !utilizationValues.isEmpty else { return "Missing data" }
        let average = utilizationValues.reduce(0, +) / Double(utilizationValues.count)
        return average.formatted(.percent.precision(.fractionLength(0)))
    }

    private var pasturesWithUtilizationCount: Int {
        pastures.filter { $0.metrics.utilizationPercent != nil }.count
    }

    private var pasturesWithCapacityCount: Int {
        pastures.filter { $0.capacityHead != nil }.count
    }

    private var activeFieldChecks: [FieldCheckSessionSummary] {
        fieldChecksModel.activeSessions.sorted { $0.startedAt > $1.startedAt }
    }

    private var openFindingCount: Int {
        fieldChecksModel.openFindings.count
    }

    private var flaggedCheckAnimalCount: Int {
        fieldChecksModel.sessions.reduce(0) { $0 + $1.flaggedAnimalCount }
    }

    private var missingCheckAnimalCount: Int {
        fieldChecksModel.sessions.reduce(0) { $0 + $1.missingAnimalCount }
    }

    private var completedChecksLast30Days: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return fieldChecksModel.sessions.filter { session in
            guard session.isCompleted else { return false }
            return session.startedAt >= cutoff
        }.count
    }

    private var latestCompletedCheckDescription: String {
        guard let latest = fieldChecksModel.sessions
            .filter(\.isCompleted)
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first else {
            return "No completed checks recorded."
        }

        return "Latest completed: \(latest.displayTitle) · \(latest.startedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var herdMixText: String {
        let groupedAnimals = Dictionary(grouping: activeAnimals) { animal in
            animal.animalType
        }
        let countsByType = groupedAnimals.mapValues { animals in
            animals.count
        }
        let orderedTypes: [(title: String, type: AnimalType)] = [
            ("Cows", AnimalType.cow),
            ("Heifers", AnimalType.heifer),
            ("Calves", AnimalType.calf),
            ("Bulls", AnimalType.bull),
            ("Steers", AnimalType.steer)
        ]

        var parts: [String] = []
        for item in orderedTypes {
            let count = countsByType[item.type, default: 0]
            guard count > 0 else { continue }
            parts.append("\(item.title) \(count)")
        }

        return parts.isEmpty ? "No active animals." : parts.joined(separator: " · ")
    }

    private var sexMixText: String {
        let groupedAnimals = Dictionary(grouping: activeAnimals) { animal in
            animal.sex
        }
        let countsBySex = groupedAnimals.mapValues { animals in
            animals.count
        }
        let orderedSexes: [(title: String, sex: Sex)] = [
            ("Female", Sex.female),
            ("Male", Sex.male),
            ("Unknown", Sex.unknown)
        ]

        var parts: [String] = []
        for item in orderedSexes {
            let count = countsBySex[item.sex, default: 0]
            guard count > 0 else { continue }
            parts.append("\(item.title) \(count)")
        }

        return parts.isEmpty ? "No active animals." : parts.joined(separator: " · ")
    }

    private var workingPenStatusSubtitle: String {
        guard let activeSessionSummary else { return "No active working session." }
        return activeSessionDescription(activeSessionSummary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                podcastsStyleHeader
                overviewSection
                alertsSection
                herdCompositionSection
                locationStatusSection
                careStatusSection
                pastureStatusSection
                fieldCheckStatusSection
                workStatusSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            addMenu
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $isStartingFieldCheck) {
            FieldCheckSessionDetailView()
        }
        .refreshable {
            loadDashboardData()
        }
        .task {
            loadDashboardData()
        }
        .onAppear {
            loadDashboardData()
        }
        .onChange(of: configurationSignature) { _, _ in
            loadDashboardData()
        }
        .onChange(of: viewModel.isPresentingAddAnimal) { _, isPresented in
            if !isPresented { loadDashboardData() }
        }
        .onChange(of: viewModel.isPresentingAddPasture) { _, isPresented in
            if !isPresented { loadDashboardData() }
        }
        .onChange(of: viewModel.isPresentingNewWorkingSession) { _, isPresented in
            if !isPresented { loadDashboardData() }
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
                fieldChecksModel.errorMessage = nil
            }
        } message: {
            Text(dashboardErrorMessage ?? "Unknown error")
        }
    }

    private var podcastsStyleHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Dashboard")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 16)

            Menu {
                Button {
                    onShowSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                settingsMenuLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
        }
    }

    private var settingsMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 46, height: 46)
            .background(Circle().fill(.regularMaterial))
    }

    private var addMenu: some View {
        Menu {
            Button {
                viewModel.isPresentingAddAnimal = true
            } label: {
                Label("Add Animal", systemImage: "tag")
            }

            Button {
                viewModel.isPresentingAddPasture = true
            } label: {
                Label("Add Pasture", systemImage: "leaf")
            }

            Button {
                viewModel.isPresentingNewWorkingSession = true
            } label: {
                Label("New Working Session", systemImage: "wrench.and.screwdriver")
            }

            Button {
                isStartingFieldCheck = true
            } label: {
                Label("Start Pasture Check", systemImage: "checklist")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Add")
    }

    @ViewBuilder
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    isOverviewExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Overview")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(overviewSummaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isOverviewExpanded ? "chevron.up" : "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.tertiary)
                }
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)

            if isOverviewExpanded {
                if snapshot == nil {
                    DashboardSection(title: "") {
                        DashboardLoadingRow(title: "Loading herd overview…")
                    }
                } else {
                    DashboardMetricsGrid(
                        items: metricItems,
                        onNavigate: navigate
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        DashboardSection(title: "Alerts") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading alerts…")
            } else if alerts.isEmpty {
                DashboardStatusRow(
                    title: "No active alerts",
                    subtitle: "Configured herd, treatment, pregnancy, and pasture warnings are clear.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    trailingText: nil,
                    showsChevron: false
                )
            } else {
                ForEach(alerts) { alert in
                    alertRow(alert)
                }
            }
        }
    }

    @ViewBuilder
    private var herdCompositionSection: some View {
        DashboardSection(title: "Herd Composition") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading herd composition…")
            } else {
                DashboardStatusRow(
                    title: "Animal type mix",
                    subtitle: herdMixText,
                    systemImage: "pawprint.fill",
                    tint: .blue,
                    trailingText: (overview?.activeAnimalCount ?? 0).formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Sex mix",
                    subtitle: sexMixText,
                    systemImage: "person.2.fill",
                    tint: .indigo,
                    trailingText: nil,
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var locationStatusSection: some View {
        DashboardSection(title: "Location Status") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading location status…")
            } else {
                DashboardStatusRow(
                    title: "Pasture assignment",
                    subtitle: "\(pastureAssignedAnimalCount.formatted()) assigned · \(workingPenAnimalCount.formatted()) in working pen · \(unassignedAnimalCount.formatted()) unassigned",
                    systemImage: "mappin.and.ellipse",
                    tint: unassignedAnimalCount > 0 ? .orange : .green,
                    trailingText: pastureAssignmentRateText,
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Working pen",
                    subtitle: workingPenStatusSubtitle,
                    systemImage: "wrench.adjustable.fill",
                    tint: workingPenAnimalCount > 0 ? .orange : .gray,
                    trailingText: workingPenAnimalCount.formatted(),
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var careStatusSection: some View {
        DashboardSection(title: "Care Status") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading care status…")
            } else {
                DashboardStatusRow(
                    title: "Calving watch",
                    subtitle: "Pregnant animals currently inside the watch window.",
                    systemImage: "figure.2.and.child.holdinghands",
                    tint: (overview?.calvingWatchCount ?? 0) > 0 ? .pink : .gray,
                    trailingText: (overview?.calvingWatchCount ?? 0).formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Pregnancy check status",
                    subtitle: "Threshold: \(configuration.pregnancyCheckIntervalDays) days since last check.",
                    systemImage: "stethoscope",
                    tint: (overview?.overduePregnancyCheckCount ?? 0) > 0 ? .orange : .green,
                    trailingText: (overview?.overduePregnancyCheckCount ?? 0).formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Treatment status",
                    subtitle: "Threshold: \(configuration.treatmentIntervalDays) days since last treatment.",
                    systemImage: "pills.fill",
                    tint: (overview?.overdueTreatmentCount ?? 0) > 0 ? .red : .green,
                    trailingText: (overview?.overdueTreatmentCount ?? 0).formatted(),
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var pastureStatusSection: some View {
        DashboardSection(title: "Pasture Status") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading pasture status…")
            } else if pastures.isEmpty {
                DashboardStatusRow(
                    title: "No pastures",
                    subtitle: "Add pastures to track stocking, grazing pressure, and rotation status.",
                    systemImage: "leaf.fill",
                    tint: .gray,
                    trailingText: nil,
                    showsChevron: false
                )
            } else {
                DashboardStatusRow(
                    title: "Average utilization",
                    subtitle: "Based on \(pasturesWithUtilizationCount.formatted()) of \(pastures.count.formatted()) pastures with usable stocking data.",
                    systemImage: "gauge.with.dots.needle.67percent",
                    tint: .blue,
                    trailingText: averageUtilizationText,
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Capacity data coverage",
                    subtitle: "\(pasturesWithCapacityCount.formatted()) pastures have calculated or configured capacity.",
                    systemImage: "ruler.fill",
                    tint: pasturesMissingStockingData.isEmpty ? .green : .brown,
                    trailingText: "\(pasturesMissingStockingData.count.formatted()) missing",
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Over capacity",
                    subtitle: "Pastures currently above configured carrying capacity.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: overstockedPastures.isEmpty ? .green : .red,
                    trailingText: overstockedPastures.count.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Rotation-ready status",
                    subtitle: "Rested pastures below the upper utilization threshold.",
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: rotationReadyPastures.isEmpty ? .gray : .green,
                    trailingText: rotationReadyPastures.count.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Low-use status",
                    subtitle: "Underutilized pastures below the lower utilization threshold.",
                    systemImage: "tray.and.arrow.down.fill",
                    tint: underutilizedPastures.isEmpty ? .gray : .teal,
                    trailingText: underutilizedPastures.count.formatted(),
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var fieldCheckStatusSection: some View {
        DashboardSection(title: "Field Check Status") {
            if !fieldChecksModel.hasLoaded {
                DashboardLoadingRow(title: "Loading pasture-check status…")
            } else {
                DashboardStatusRow(
                    title: "Checks in progress",
                    subtitle: activeFieldChecks.isEmpty ? "No pasture checks are currently open." : "Open pasture checks are part of the current field-check snapshot.",
                    systemImage: "checklist",
                    tint: activeFieldChecks.isEmpty ? .green : .purple,
                    trailingText: activeFieldChecks.count.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Finding alerts",
                    subtitle: "Unresolved fence, water, health, missing-animal, or other field notes.",
                    systemImage: "exclamationmark.bubble.fill",
                    tint: openFindingCount > 0 ? .red : .green,
                    trailingText: openFindingCount.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Flagged animal count",
                    subtitle: "Animals marked for attention during pasture checks.",
                    systemImage: "flag.fill",
                    tint: flaggedCheckAnimalCount > 0 ? .orange : .gray,
                    trailingText: flaggedCheckAnimalCount.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Missing animal count",
                    subtitle: "Animals marked missing from expected pasture check rosters.",
                    systemImage: "questionmark.app.fill",
                    tint: missingCheckAnimalCount > 0 ? .brown : .gray,
                    trailingText: missingCheckAnimalCount.formatted(),
                    showsChevron: false
                )

                DashboardStatusRow(
                    title: "Completed checks, 30 days",
                    subtitle: latestCompletedCheckDescription,
                    systemImage: "calendar.badge.checkmark",
                    tint: completedChecksLast30Days > 0 ? .blue : .gray,
                    trailingText: completedChecksLast30Days.formatted(),
                    showsChevron: false
                )
            }
        }
    }

    @ViewBuilder
    private var workStatusSection: some View {
        DashboardSection(title: "Work Status") {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading work status…")
            } else if activeSessionSummary == nil && workingPenAnimalCount == 0 {
                DashboardStatusRow(
                    title: "No active work",
                    subtitle: "The working pen is clear and there is no in-progress processing session.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    trailingText: nil,
                    showsChevron: false
                )
            } else {
                if let session = activeSessionSummary {
                    DashboardStatusRow(
                        title: "Active working session",
                        subtitle: activeSessionDescription(session),
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange,
                        trailingText: "\(session.completedQueueItems)/\(session.totalQueueItems)",
                        showsChevron: false
                    )
                }

                DashboardStatusRow(
                    title: "Working pen population",
                    subtitle: "Animals staged away from pasture for current or pending work.",
                    systemImage: "wrench.adjustable.fill",
                    tint: workingPenAnimalCount > 0 ? .orange : .green,
                    trailingText: workingPenAnimalCount.formatted(),
                    showsChevron: false
                )
            }
        }
    }

    private var metricItems: [DashboardMetric] {
        let overview = viewModel.snapshot?.overview

        return [
            DashboardMetric(
                title: "Active",
                value: overview?.activeAnimalCount ?? 0,
                tint: .blue,
                iconLucide: "beef",
                destination: .animalList(.active)
            ),
            DashboardMetric(
                title: "Pastures",
                value: overview?.pastureCount ?? 0,
                tint: .green,
                iconSystem: "leaf.fill",
                destination: .pastureList
            ),
            DashboardMetric(
                title: "Working Pen",
                value: overview?.workingPenCount ?? 0,
                tint: .orange,
                iconSystem: "wrench.fill",
                destination: .animalList(.workingPen)
            ),
            DashboardMetric(
                title: "Unassigned",
                value: overview?.unassignedAnimalCount ?? 0,
                tint: (overview?.unassignedAnimalCount ?? 0) > 0 ? .orange : .gray,
                iconLucide: "map-pin-off",
                destination: .animalList(.unassigned)
            ),
            DashboardMetric(
                title: "Preg Checks",
                value: overview?.overduePregnancyCheckCount ?? 0,
                tint: (overview?.overduePregnancyCheckCount ?? 0) > 0 ? .orange : .green,
                iconSystem: "stethoscope",
                destination: .animalList(.overduePregChecks)
            ),
            DashboardMetric(
                title: "Treatments",
                value: overview?.overdueTreatmentCount ?? 0,
                tint: (overview?.overdueTreatmentCount ?? 0) > 0 ? .red : .green,
                iconSystem: "pills.fill",
                destination: .animalList(.overdueTreatments)
            ),
            DashboardMetric(
                title: "Calving Watch",
                value: overview?.calvingWatchCount ?? 0,
                tint: .pink,
                iconSystem: "figure.2.and.child.holdinghands",
                destination: .animalList(.calvingWatch)
            ),
            DashboardMetric(
                title: "Alerts",
                value: viewModel.snapshot?.alerts.count ?? 0,
                tint: alerts.isEmpty ? .green : .red,
                iconSystem: alerts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                destination: nil
            )
        ]
    }

    private var overviewSummaryText: String {
        guard let overview else { return "Loading herd snapshot…" }
        return "\(overview.activeAnimalCount.formatted()) active · \(overview.pastureCount.formatted()) pastures · \(alerts.count.formatted()) alerts"
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

    private var dashboardErrorMessage: String? {
        viewModel.errorMessage ?? fieldChecksModel.errorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { dashboardErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                    fieldChecksModel.errorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func alertRow(_ alert: DashboardAlert) -> some View {
        if let destination = alert.destination {
            NavigationLink(value: route(for: destination)) {
                DashboardAlertStatusRow(alert: alert, colorForSeverity: color)
            }
            .buttonStyle(.plain)
        } else {
            DashboardAlertStatusRow(alert: alert, colorForSeverity: color)
        }
    }

    private func loadDashboardData() {
        viewModel.load(configuration: configuration, using: repository)
        fieldChecksModel.load(using: fieldCheckRepository)
    }

    private func activeSessionDescription(_ session: DashboardWorkingSessionSummary) -> String {
        var components = [session.protocolName]
        if let sourcePastureName = session.sourcePastureName, !sourcePastureName.isEmpty {
            components.append(sourcePastureName)
        }
        components.append(session.date.formatted(date: .abbreviated, time: .shortened))
        return components.joined(separator: " · ")
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

private struct DashboardSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct DashboardStatusRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let trailingText: String?
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct DashboardAlertStatusRow: View {
    let alert: DashboardAlert
    let colorForSeverity: (DashboardAlertSeverity) -> Color

    var body: some View {
        HStack(spacing: 14) {
            icon
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(colorForSeverity(alert.severity)))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let message = alert.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if alert.destination != nil {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let base = UIImage(lucideId: alert.icon) {
            Image(uiImage: base.scaled(to: CGSize(width: 18, height: 18)))
                .renderingMode(.template)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
        }
    }
}

private struct DashboardLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

private struct DashboardFilteredPastureListView: View {
    let title: String
    let emptyMessage: String
    let pastures: [DashboardPastureItem]

    var body: some View {
        List {
            if pastures.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pastures) { pasture in
                    NavigationLink(value: DashboardRoute.pasture(pasture.id)) {
                        pastureRow(pasture)
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    private func pastureRow(_ pasture: DashboardPastureItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                Label("Incomplete", systemImage: "ruler")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Text("\(pasture.activeAnimalCount) head")

                if pasture.acres > 0 {
                    Text("• \(pasture.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                } else {
                    Text("• missing acres")
                        .foregroundStyle(.orange)
                }

                if let capacity = pasture.capacityHead {
                    Text("• cap \(Int(capacity))")
                } else {
                    Text("• missing capacity")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
