import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = false
    @AppStorage("syncMode") private var syncModeRawValue = SyncMode.localOnly.rawValue
    @AppStorage("homeDismissedSetupSuggestionIDs") private var dismissedSetupSuggestionIDsRaw = ""
    @AppStorage("homeSetupSuggestionsExpanded") private var isSetupSuggestionsExpanded = true

    @State private var viewModel = DashboardViewModel()
    @State private var fieldChecksModel = FieldChecksViewModel()
    @State private var dashboardRecords: DashboardRecords?
    @State private var recordsErrorMessage: String?
    @State private var protocolTemplates: [WorkingProtocolTemplateSummary]?
    @State private var workingErrorMessage: String?
    @Binding private var isPresentingAddAnimal: Bool
    @Binding private var isPresentingAddPasture: Bool
    @Binding private var isPresentingNewWorkingSession: Bool
    @Binding private var isStartingFieldCheck: Bool
    private let onShowSettings: () -> Void

    init(
        isPresentingAddAnimal: Binding<Bool>,
        isPresentingAddPasture: Binding<Bool>,
        isPresentingNewWorkingSession: Binding<Bool>,
        isStartingFieldCheck: Binding<Bool>,
        onShowSettings: @escaping () -> Void = {}
    ) {
        self._isPresentingAddAnimal = isPresentingAddAnimal
        self._isPresentingAddPasture = isPresentingAddPasture
        self._isPresentingNewWorkingSession = isPresentingNewWorkingSession
        self._isStartingFieldCheck = isStartingFieldCheck
        self.onShowSettings = onShowSettings
    }

    private var repository: any DashboardRepository {
        dependencies.dashboardRepository
    }

    private var fieldCheckRepository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
    }

    private var workingRepository: any WorkingRepository {
        dependencies.workingRepository
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

    private var activeSession: DashboardWorkingSessionSummary? {
        snapshot?.activeSession
    }

    private var flaggedCheckSessions: [FieldCheckSessionSummary] {
        fieldChecksModel.sessions
            .filter { $0.flaggedAnimalCount > 0 }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted {
                    return !left.isCompleted
                }
                return left.startedAt > right.startedAt
            }
    }

    private var flaggedCheckAnimalCount: Int {
        flaggedCheckSessions.reduce(0) { $0 + $1.flaggedAnimalCount }
    }

    private var pastureCheckDueItems: [HomePastureCheckDueItem] {
        guard let pastures = snapshot?.pastures else { return [] }

        let activePastureIDs = Set(fieldChecksModel.activeSessions.compactMap(\.pastureID))
        let latestCheckDateByPastureID = Dictionary(
            grouping: fieldChecksModel.sessions.compactMap { session -> (UUID, Date)? in
                guard session.isCompleted, let pastureID = session.pastureID else { return nil }
                return (pastureID, session.startedAt)
            },
            by: { $0.0 }
        ).mapValues { pairs in
            pairs.map(\.1).max() ?? .distantPast
        }
        let dueBeforeDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast

        return pastures
            .filter { pasture in
                !activePastureIDs.contains(pasture.id)
                && (latestCheckDateByPastureID[pasture.id] ?? .distantPast) < dueBeforeDate
            }
            .map { pasture in
                HomePastureCheckDueItem(
                    id: pasture.id,
                    name: pasture.name,
                    activeAnimalCount: pasture.activeAnimalCount,
                    lastCheckDate: latestCheckDateByPastureID[pasture.id]
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.lastCheckDate, rhs.lastCheckDate) {
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case (nil, _):
                    return true
                case (_, nil):
                    return false
                case let (left?, right?):
                    if left != right { return left < right }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                setupSuggestionsSection
                homeSummaryCardsSection
                continueSection
                fieldWorkSection
                workPenSection
                pastureOperationsSection
                recordsCleanupSection
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
        .navigationDestination(for: DashboardRoute.self, destination: routeDestination)
        .navigationDestination(isPresented: $isStartingFieldCheck) {
            FieldCheckSessionDetailView()
        }
        .task {
            loadHomeData()
        }
        .onAppear {
            loadHomeData()
        }
        .onChange(of: configurationSignature) { _, _ in
            loadHomeData()
        }
        .onChange(of: isPresentingAddAnimal) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .onChange(of: isPresentingAddPasture) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .onChange(of: isPresentingNewWorkingSession) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .sheet(isPresented: $isPresentingAddAnimal) {
            AddAnimalView()
        }
        .sheet(isPresented: $isPresentingAddPasture) {
            AddPastureView()
        }
        .sheet(isPresented: $isPresentingNewWorkingSession) {
            NewWorkingSessionView()
        }
        .alert("Home Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                fieldChecksModel.errorMessage = nil
                recordsErrorMessage = nil
                workingErrorMessage = nil
            }
        } message: {
            Text(homeErrorMessage ?? "Unknown error")
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
                isPresentingAddAnimal = true
            } label: {
                Label("Add Animal", systemImage: "tag")
            }

            Button {
                isPresentingAddPasture = true
            } label: {
                Label("Add Pasture", systemImage: "leaf")
            }

            Button {
                isPresentingNewWorkingSession = true
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

    private var activeCheckSessions: [FieldCheckSessionSummary] {
        fieldChecksModel.activeSessions.sorted { $0.startedAt > $1.startedAt }
    }

    private var missingCheckSessions: [FieldCheckSessionSummary] {
        fieldChecksModel.sessions
            .filter { $0.missingAnimalCount > 0 }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted {
                    return !left.isCompleted
                }
                return left.startedAt > right.startedAt
            }
    }

    private var missingCheckAnimalCount: Int {
        missingCheckSessions.reduce(0) { $0 + $1.missingAnimalCount }
    }

    private var workingPenCount: Int {
        overview?.workingPenCount ?? 0
    }

    private var workingPenAnimalRecords: [DashboardAnimalRecord] {
        activeAnimalRecords.filter { $0.location == .workingPen }
    }

    private var overstockedPastures: [DashboardPastureItem] {
        (snapshot?.pastures ?? [])
            .filter(\.isOverstocked)
            .sorted { lhs, rhs in
                let lhsOverage = Double(lhs.activeAnimalCount) - (lhs.capacityHead ?? 0)
                let rhsOverage = Double(rhs.activeAnimalCount) - (rhs.capacityHead ?? 0)
                if lhsOverage != rhsOverage { return lhsOverage > rhsOverage }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var rotationReadyPastures: [DashboardPastureItem] {
        (snapshot?.pastures ?? [])
            .filter(\.isRotationReady)
            .sorted { lhs, rhs in
                if lhs.activeAnimalCount != rhs.activeAnimalCount {
                    return lhs.activeAnimalCount < rhs.activeAnimalCount
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var underutilizedPastures: [DashboardPastureItem] {
        (snapshot?.pastures ?? [])
            .filter(\.isUnderutilized)
            .sorted { lhs, rhs in
                let leftUtilization = lhs.metrics.utilizationPercent ?? 0
                let rightUtilization = rhs.metrics.utilizationPercent ?? 0
                if leftUtilization != rightUtilization { return leftUtilization < rightUtilization }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var pasturesMissingStockingData: [DashboardPastureItem] {
        (snapshot?.pastures ?? [])
            .filter { pasture in
                pasture.acres <= 0 || pasture.metrics.targetAcresPerHead == nil
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeAnimalRecords: [DashboardAnimalRecord] {
        (dashboardRecords?.animals ?? [])
            .filter(\.isActiveInHerd)
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    private var unassignedAnimalRecords: [DashboardAnimalRecord] {
        activeAnimalRecords.filter { animal in
            animal.location == .pasture && animal.pastureID == nil
        }
    }

    private var missingTagNumberAnimals: [DashboardAnimalRecord] {
        activeAnimalRecords.filter { animal in
            animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var missingTagColorAnimals: [DashboardAnimalRecord] {
        activeAnimalRecords.filter { animal in
            animal.displayTagColorID == nil
        }
    }

    private var unknownSexAnimals: [DashboardAnimalRecord] {
        activeAnimalRecords.filter { animal in
            animal.sex == .unknown
        }
    }

    private var archivedActiveRecords: [DashboardAnimalRecord] {
        (dashboardRecords?.animals ?? [])
            .filter { $0.isArchived && $0.status == .active }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    private var fieldWorkCardCount: Int {
        let unfinishedChecks = activeCheckSessions.count
        let dueChecks = pastureCheckDueItems.count
        let openFindings = fieldChecksModel.openFindings.count
        return unfinishedChecks + dueChecks + openFindings + flaggedCheckAnimalCount + missingCheckAnimalCount
    }

    private var pastureOperationsCardCount: Int {
        let capacityTasks = overstockedPastures.count
        let receivingTasks = rotationReadyPastures.count + underutilizedPastures.count
        return capacityTasks + receivingTasks + pasturesMissingStockingData.count
    }

    private var recordsCleanupCardCount: Int {
        let animalIdentityIssues = missingTagNumberAnimals.count + missingTagColorAnimals.count + unknownSexAnimals.count
        return unassignedAnimalRecords.count + animalIdentityIssues + archivedActiveRecords.count
    }

    private var continueCardCount: Int {
        guard snapshot != nil && fieldChecksModel.hasLoaded else { return 0 }
        let hasCurrentWork = activeSession != nil
            || !activeCheckSessions.isEmpty
            || workingPenCount > 0
            || !fieldChecksModel.openFindings.isEmpty
        return hasCurrentWork ? 1 : 0
    }

    private var continueCardSubtitle: String {
        guard snapshot != nil && fieldChecksModel.hasLoaded else { return "Loading current work" }
        if activeSession != nil { return "Resume session" }
        if !activeCheckSessions.isEmpty { return "Finish check" }
        if workingPenCount > 0 { return "Clear pen" }
        if !fieldChecksModel.openFindings.isEmpty { return "Resolve finding" }
        return "Start work"
    }

    private var hasFieldWorkRows: Bool {
        shouldShowUnfinishedChecksRow
        || shouldShowOpenFindingsRow
        || flaggedCheckAnimalCount > 0
        || missingCheckAnimalCount > 0
        || !pastureCheckDueItems.isEmpty
    }

    private var shouldShowUnfinishedChecksRow: Bool {
        guard !activeCheckSessions.isEmpty else { return false }
        return !(activeSession == nil && activeCheckSessions.count == 1)
    }

    private var shouldShowWorkingPenAnimalsRow: Bool {
        guard workingPenCount > 0 else { return false }
        return !(activeSession == nil && activeCheckSessions.isEmpty)
    }

    private var shouldShowOpenFindingsRow: Bool {
        let openFindingCount = fieldChecksModel.openFindings.count
        guard openFindingCount > 0 else { return false }
        return !(activeSession == nil && activeCheckSessions.isEmpty && workingPenCount == 0 && openFindingCount == 1)
    }

    private var hasPastureOperationRows: Bool {
        !overstockedPastures.isEmpty
        || !rotationReadyPastures.isEmpty
        || !underutilizedPastures.isEmpty
        || !pasturesMissingStockingData.isEmpty
    }

    private var hasRecordsCleanupRows: Bool {
        !unassignedAnimalRecords.isEmpty
        || !missingTagNumberAnimals.isEmpty
        || !missingTagColorAnimals.isEmpty
        || !unknownSexAnimals.isEmpty
        || !archivedActiveRecords.isEmpty
    }

    private var hasSetupSuggestionRows: Bool {
        !visibleSetupSuggestionIDs.isEmpty
    }

    private var visibleSetupSuggestionIDs: [HomeSetupSuggestionID] {
        guard let dashboardRecords, fieldChecksModel.hasLoaded, let protocolTemplates else { return [] }

        var ids: [HomeSetupSuggestionID] = []
        let hasPastures = !dashboardRecords.pastures.isEmpty
        let hasActiveAnimals = dashboardRecords.animals.contains { $0.isActiveInHerd }

        if !hasPastures { ids.append(.addFirstPasture) }
        if !hasActiveAnimals { ids.append(.addFirstAnimal) }
        if hasPastures && fieldChecksModel.sessions.isEmpty { ids.append(.startFirstPastureCheck) }
        if protocolTemplates.isEmpty && hasPastures && hasActiveAnimals { ids.append(.createWorkingProtocol) }
        if !isDashboardEnabled { ids.append(.enableDashboard) }
        if customTagColorCount == 0 { ids.append(.customizeTagColors) }
        if !pasturesMissingStockingData.isEmpty { ids.append(.completePastureStockingData) }
        if syncMode == .localOnly { ids.append(.reviewSyncSetup) }

        return ids.filter { !dismissedSetupSuggestionIDs.contains($0.rawValue) }
    }

    private var dismissedSetupSuggestionIDs: Set<String> {
        Set(
            dismissedSetupSuggestionIDsRaw
                .split(separator: ",")
                .map { String($0) }
        )
    }

    private var customTagColorCount: Int {
        tagColorLibrary.colors.filter { !TagColorLibraryStore.defaultColorIDs.contains($0.id) }.count
    }

    private var syncMode: SyncMode {
        SyncMode(rawValue: syncModeRawValue) ?? .localOnly
    }

    @ViewBuilder
    private var homeSummaryCardsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                continueSummaryCard
                    .frame(maxWidth: .infinity)
                fieldWorkSummaryCard
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                pastureOperationsSummaryCard
                    .frame(maxWidth: .infinity)
                recordsCleanupSummaryCard
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var continueSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Continue",
            value: continueCardCount,
            subtitle: continueCardSubtitle,
            systemImage: continueCardCount > 0 ? "play.fill" : "plus",
            tint: continueCardCount > 0 ? .orange : .blue
        )

        if activeSession != nil {
            NavigationLink {
                WorkingSessionsView()
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if let session = activeCheckSessions.first {
            NavigationLink {
                FieldCheckSessionDetailView(sessionID: session.id, opensRemainingRoster: true)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if workingPenCount > 0 {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Working Pen",
                    emptyMessage: "No animals are currently staged in the working pen.",
                    animals: workingPenAnimalRecords
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if let finding = fieldChecksModel.openFindings.first {
            NavigationLink {
                FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                isStartingFieldCheck = true
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var fieldWorkSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Field Work",
            value: fieldWorkCardCount,
            subtitle: fieldWorkCardCount == 1 ? "1 field task" : "Field tasks",
            systemImage: "checklist",
            tint: fieldWorkCardCount > 0 ? .purple : .gray
        )

        NavigationLink {
            FieldChecksView(mode: .all)
        } label: {
            HomeSummaryCardView(card: card)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pastureOperationsSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Pasture Ops",
            value: pastureOperationsCardCount,
            subtitle: pastureOperationsCardCount == 1 ? "1 pasture task" : "Pasture tasks",
            systemImage: "arrow.triangle.2.circlepath",
            tint: pastureOperationsCardCount > 0 ? .green : .gray
        )

        if !overstockedPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Pastures Needing Relief",
                    emptyMessage: "No pastures are above configured capacity.",
                    pastures: overstockedPastures
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !rotationReadyPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Ready to Receive",
                    emptyMessage: "No pastures are rotation-ready.",
                    pastures: rotationReadyPastures
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !underutilizedPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Low-Use Pastures",
                    emptyMessage: "No pastures are currently underutilized.",
                    pastures: underutilizedPastures
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !pasturesMissingStockingData.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Missing Stocking Data",
                    emptyMessage: "All pastures have stocking data.",
                    pastures: pasturesMissingStockingData
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: DashboardRoute.pastureList) {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recordsCleanupSummaryCard: some View {
        let card = HomeSummaryCard(
            title: "Cleanup",
            value: recordsCleanupCardCount,
            subtitle: recordsCleanupCardCount == 1 ? "1 record issue" : "Record issues",
            systemImage: "wrench.and.screwdriver.fill",
            tint: recordsCleanupCardCount > 0 ? .brown : .gray
        )

        if !unassignedAnimalRecords.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Pasture",
                    emptyMessage: "No active pasture animals are missing pasture assignment.",
                    animals: unassignedAnimalRecords
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !missingTagNumberAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Tags",
                    emptyMessage: "No active animals are missing tag numbers.",
                    animals: missingTagNumberAnimals
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !missingTagColorAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Tag Color",
                    emptyMessage: "No active animals are missing tag color.",
                    animals: missingTagColorAnimals
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !unknownSexAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals With Unknown Sex",
                    emptyMessage: "No active animals have unknown sex.",
                    animals: unknownSexAnimals
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else if !archivedActiveRecords.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Archived Active Records",
                    emptyMessage: "No archived records are still marked active.",
                    animals: archivedActiveRecords
                )
            } label: {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: DashboardRoute.animalList(.active)) {
                HomeSummaryCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        HomeSection(title: "Continue") {
            if snapshot == nil || !fieldChecksModel.hasLoaded {
                HomeLoadingRow(title: "Loading current work…")
            } else if let activeSession {
                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    HomePrimaryActionRow(
                        title: "Resume working session",
                        subtitle: activeSessionSummary(activeSession),
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange,
                        actionTitle: "Resume"
                    )
                }
                .buttonStyle(.plain)
            } else if let session = activeCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensRemainingRoster: true)
                } label: {
                    HomePrimaryActionRow(
                        title: "Finish \(session.displayTitle) check",
                        subtitle: "\(session.individuallyVerifiedCount)/\(session.expectedHeadCountSnapshot) verified · \(session.remainingExpectedCount) remaining",
                        systemImage: "checklist",
                        tint: .purple,
                        actionTitle: "Continue"
                    )
                }
                .buttonStyle(.plain)
            } else if workingPenCount > 0 {
                NavigationLink {
                    HomeAnimalRecordListView(
                        title: "Working Pen",
                        emptyMessage: "No animals are currently staged in the working pen.",
                        animals: workingPenAnimalRecords
                    )
                } label: {
                    HomePrimaryActionRow(
                        title: "Clear the working pen",
                        subtitle: "\(workingPenCount) animals are still staged for work.",
                        systemImage: "arrowshape.turn.up.left.circle.fill",
                        tint: .orange,
                        actionTitle: "Open"
                    )
                }
                .buttonStyle(.plain)
            } else if let finding = fieldChecksModel.openFindings.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
                } label: {
                    HomePrimaryActionRow(
                        title: "Resolve field finding",
                        subtitle: finding.pastureName ?? "Open finding from a pasture check.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        actionTitle: "Resolve"
                    )
                }
                .buttonStyle(.plain)
            } else {
                HomeStatusRow(
                    title: "Nothing in progress",
                    subtitle: "Start a pasture check or working session from the plus button.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
        }
    }

    @ViewBuilder
    private var fieldWorkSection: some View {
        if snapshot == nil || !fieldChecksModel.hasLoaded || hasFieldWorkRows {
            HomeSection(title: "Field Work") {
                if snapshot == nil || !fieldChecksModel.hasLoaded {
                    HomeLoadingRow(title: "Loading field work…")
                } else {
                    fieldWorkRows
                }
            }
        }
    }

    @ViewBuilder
    private var fieldWorkRows: some View {
        if shouldShowUnfinishedChecksRow {
            NavigationLink {
                FieldChecksView(mode: .inProgress)
            } label: {
                HomeListRow(
                    title: "Checks not completed",
                    subtitle: "Finish remaining roster work before those counts go stale.",
                    systemImage: "checklist",
                    tint: .purple,
                    count: activeCheckSessions.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !pastureCheckDueItems.isEmpty {
            if pastureCheckDueItems.count == 1, let item = pastureCheckDueItems.first {
                NavigationLink {
                    FieldCheckSessionDetailView(suggestedPastureID: item.id)
                } label: {
                    HomeListRow(
                        title: "Check \(item.name)",
                        subtitle: item.lastCheckDescription,
                        systemImage: "calendar.badge.exclamationmark",
                        tint: .purple,
                        count: item.activeAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    HomePastureCheckDueListView(items: pastureCheckDueItems)
                } label: {
                    HomeListRow(
                        title: "Pasture checks due",
                        subtitle: "Start checks for pastures without a recent completed pass.",
                        systemImage: "calendar.badge.exclamationmark",
                        tint: .purple,
                        count: pastureCheckDueItems.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if shouldShowOpenFindingsRow {
            if fieldChecksModel.openFindings.count == 1, let finding = fieldChecksModel.openFindings.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
                } label: {
                    HomeListRow(
                        title: "Resolve open field finding",
                        subtitle: finding.pastureName ?? "Open finding from a pasture check.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        count: 1,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .openFindings)
                } label: {
                    HomeListRow(
                        title: "Open field findings",
                        subtitle: "Fence, water, health, and missing-animal notes from checks.",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: .red,
                        count: fieldChecksModel.openFindings.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if flaggedCheckAnimalCount > 0 {
            if flaggedCheckSessions.count == 1, let session = flaggedCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensFlaggedRoster: true)
                } label: {
                    HomeListRow(
                        title: "Flagged animals from checks",
                        subtitle: session.displayTitle,
                        systemImage: "flag.fill",
                        tint: .orange,
                        count: flaggedCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .flaggedAnimals)
                } label: {
                    HomeListRow(
                        title: "Flagged animals from checks",
                        subtitle: "Jump directly to animals marked for attention in the field.",
                        systemImage: "flag.fill",
                        tint: .orange,
                        count: flaggedCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if missingCheckAnimalCount > 0 {
            if missingCheckSessions.count == 1, let session = missingCheckSessions.first {
                NavigationLink {
                    FieldCheckSessionDetailView(sessionID: session.id, opensMissingRoster: true)
                } label: {
                    HomeListRow(
                        title: "Missing animals from checks",
                        subtitle: session.displayTitle,
                        systemImage: "questionmark.app.fill",
                        tint: .brown,
                        count: missingCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FieldChecksView(mode: .missingAnimals)
                } label: {
                    HomeListRow(
                        title: "Missing animals from checks",
                        subtitle: "Open check rosters filtered to animals marked missing.",
                        systemImage: "questionmark.app.fill",
                        tint: .brown,
                        count: missingCheckAnimalCount,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var workPenSection: some View {
        HomeSection(title: "Work Pen") {
            if snapshot == nil {
                HomeLoadingRow(title: "Loading work pen…")
            } else {
                if activeSession == nil {
                    Button {
                        isPresentingNewWorkingSession = true
                    } label: {
                        HomeListRow(
                            title: "Start working session",
                            subtitle: "Collect animals, apply a protocol, and track completion.",
                            systemImage: "plus.circle.fill",
                            tint: .blue,
                            count: nil,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                }

                if shouldShowWorkingPenAnimalsRow {
                    NavigationLink {
                        HomeAnimalRecordListView(
                            title: "Working Pen",
                            emptyMessage: "No animals are currently staged in the working pen.",
                            animals: workingPenAnimalRecords
                        )
                    } label: {
                        HomeListRow(
                            title: "Animals staged in working pen",
                            subtitle: "Open the pre-filtered list before moving or clearing them.",
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: .orange,
                            count: workingPenCount,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    ProtocolTemplatesView()
                } label: {
                    HomeListRow(
                        title: "Protocol templates",
                        subtitle: "Maintain reusable treatment and processing templates.",
                        systemImage: "list.bullet.rectangle.fill",
                        tint: .indigo,
                        count: nil,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    HomeListRow(
                        title: "Working session history",
                        subtitle: "Review active and completed work sessions.",
                        systemImage: "clock.arrow.circlepath",
                        tint: .gray,
                        count: nil,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var pastureOperationsSection: some View {
        if snapshot == nil || hasPastureOperationRows {
            HomeSection(title: "Pasture Operations") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading pasture operations…")
                } else {
                    pastureOperationRows
                }
            }
        }
    }

    @ViewBuilder
    private var pastureOperationRows: some View {
        if !overstockedPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Pastures Needing Relief",
                    emptyMessage: "No pastures are above configured capacity.",
                    pastures: overstockedPastures
                )
            } label: {
                HomeListRow(
                    title: "Pastures needing relief",
                    subtitle: "Move animals out of pastures over configured capacity.",
                    systemImage: "arrow.up.right.circle.fill",
                    tint: .red,
                    count: overstockedPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !rotationReadyPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Ready to Receive",
                    emptyMessage: "No pastures are rotation-ready.",
                    pastures: rotationReadyPastures
                )
            } label: {
                HomeListRow(
                    title: "Pastures ready to receive animals",
                    subtitle: "Rested pastures below the upper utilization threshold.",
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: .green,
                    count: rotationReadyPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !underutilizedPastures.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Low-Use Pastures",
                    emptyMessage: "No pastures are currently underutilized.",
                    pastures: underutilizedPastures
                )
            } label: {
                HomeListRow(
                    title: "Potential receiving pastures",
                    subtitle: "Underused pastures that may be candidates for a move.",
                    systemImage: "tray.and.arrow.down.fill",
                    tint: .teal,
                    count: underutilizedPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !pasturesMissingStockingData.isEmpty {
            NavigationLink {
                HomePastureListView(
                    title: "Missing Stocking Data",
                    emptyMessage: "All pastures have stocking data.",
                    pastures: pasturesMissingStockingData
                )
            } label: {
                HomeListRow(
                    title: "Pastures missing stocking data",
                    subtitle: "Add acreage or target acres/head so capacity decisions are meaningful.",
                    systemImage: "ruler.fill",
                    tint: .brown,
                    count: pasturesMissingStockingData.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recordsCleanupSection: some View {
        if dashboardRecords == nil || hasRecordsCleanupRows {
            HomeSection(title: "Records to Clean Up") {
                if dashboardRecords == nil {
                    HomeLoadingRow(title: "Loading record checks…")
                } else {
                    recordsCleanupRows
                }
            }
        }
    }

    @ViewBuilder
    private var recordsCleanupRows: some View {
        if !unassignedAnimalRecords.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Pasture",
                    emptyMessage: "No active pasture animals are missing pasture assignment.",
                    animals: unassignedAnimalRecords
                )
            } label: {
                HomeListRow(
                    title: "Animals missing pasture",
                    subtitle: "Assign active pasture animals before field work relies on location.",
                    systemImage: "mappin.slash.circle.fill",
                    tint: .brown,
                    count: unassignedAnimalRecords.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !missingTagNumberAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Tags",
                    emptyMessage: "No active animals are missing tag numbers.",
                    animals: missingTagNumberAnimals
                )
            } label: {
                HomeListRow(
                    title: "Animals missing tag numbers",
                    subtitle: "These records are harder to find during checks and working sessions.",
                    systemImage: "tag.slash.fill",
                    tint: .red,
                    count: missingTagNumberAnimals.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !missingTagColorAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals Missing Tag Color",
                    emptyMessage: "No active animals are missing tag color.",
                    animals: missingTagColorAnimals
                )
            } label: {
                HomeListRow(
                    title: "Animals missing tag color",
                    subtitle: "Add color data so field identification matches the physical tag.",
                    systemImage: "paintpalette.fill",
                    tint: .purple,
                    count: missingTagColorAnimals.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !unknownSexAnimals.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Animals With Unknown Sex",
                    emptyMessage: "No active animals have unknown sex.",
                    animals: unknownSexAnimals
                )
            } label: {
                HomeListRow(
                    title: "Animals with unknown sex",
                    subtitle: "Clean this up before breeding, calving, and filtering workflows depend on it.",
                    systemImage: "questionmark.circle.fill",
                    tint: .gray,
                    count: unknownSexAnimals.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !archivedActiveRecords.isEmpty {
            NavigationLink {
                HomeAnimalRecordListView(
                    title: "Archived Active Records",
                    emptyMessage: "No archived records still have active status.",
                    animals: archivedActiveRecords
                )
            } label: {
                HomeListRow(
                    title: "Archived records still marked active",
                    subtitle: "Review records that are hidden but still carry active status.",
                    systemImage: "archivebox.fill",
                    tint: .orange,
                    count: archivedActiveRecords.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var setupSuggestionsSection: some View {
        if hasSetupSuggestionRows {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) {
                        isSetupSuggestionsExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Setup Suggestions")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(setupSuggestionsSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: isSetupSuggestionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.tertiary)
                    }
                    .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)

                if isSetupSuggestionsExpanded {
                    VStack(spacing: 0) {
                        setupSuggestionRows
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var setupSuggestionsSummaryText: String {
        let count = visibleSetupSuggestionIDs.count
        return count == 1 ? "1 setup item" : "\(count) setup items"
    }

    @ViewBuilder
    private var setupSuggestionRows: some View {
        if visibleSetupSuggestionIDs.contains(.addFirstPasture) {
            HomeSuggestionButtonRow(
                title: "Add your first pasture",
                subtitle: "Pasture checks, stocking status, and rotation work need at least one pasture.",
                systemImage: "leaf.fill",
                tint: .green,
                actionTitle: "Add",
                onAction: { isPresentingAddPasture = true },
                onDismiss: { dismissSetupSuggestion(.addFirstPasture) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.addFirstAnimal) {
            HomeSuggestionButtonRow(
                title: "Add your first animal",
                subtitle: "Create the first herd record so field checks and working sessions have something to use.",
                systemImage: "tag.fill",
                tint: .blue,
                actionTitle: "Add",
                onAction: { isPresentingAddAnimal = true },
                onDismiss: { dismissSetupSuggestion(.addFirstAnimal) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.startFirstPastureCheck) {
            HomeSuggestionButtonRow(
                title: "Start your first pasture check",
                subtitle: "Build check history for pasture rosters, missing animals, and field findings.",
                systemImage: "checklist",
                tint: .purple,
                actionTitle: "Start",
                onAction: { isStartingFieldCheck = true },
                onDismiss: { dismissSetupSuggestion(.startFirstPastureCheck) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.createWorkingProtocol) {
            HomeSuggestionNavigationRow(
                title: "Create a working protocol",
                subtitle: "Set up reusable treatment or processing steps before the first working session.",
                systemImage: "list.clipboard.fill",
                tint: .orange,
                actionTitle: "Open",
                destination: { ProtocolTemplatesView() },
                onDismiss: { dismissSetupSuggestion(.createWorkingProtocol) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.enableDashboard) {
            HomeSuggestionNavigationRow(
                title: "Enable the Dashboard tab",
                subtitle: "Turn on herd-level summaries when you want a status screen separate from Home.",
                systemImage: "rectangle.3.group.fill",
                tint: .blue,
                actionTitle: "Open",
                destination: { DashboardRulesView() },
                onDismiss: { dismissSetupSuggestion(.enableDashboard) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.customizeTagColors) {
            HomeSuggestionNavigationRow(
                title: "Customize tag colors",
                subtitle: "Add ranch-specific colors or prefixes for faster field identification.",
                systemImage: "tag.fill",
                tint: .yellow,
                actionTitle: "Open",
                destination: { TagColorLibraryView() },
                onDismiss: { dismissSetupSuggestion(.customizeTagColors) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.completePastureStockingData) {
            HomeSuggestionNavigationRow(
                title: "Complete pasture stocking data",
                subtitle: "Add acreage and target acres/head so capacity and rotation guidance is useful.",
                systemImage: "ruler.fill",
                tint: .brown,
                actionTitle: "Open",
                destination: {
                    HomePastureListView(
                        title: "Missing Stocking Data",
                        emptyMessage: "All pastures have stocking data.",
                        pastures: pasturesMissingStockingData
                    )
                },
                onDismiss: { dismissSetupSuggestion(.completePastureStockingData) }
            )
        }

        if visibleSetupSuggestionIDs.contains(.reviewSyncSetup) {
            HomeSuggestionNavigationRow(
                title: "Set up sync",
                subtitle: "Data is currently stored on this device only.",
                systemImage: "icloud.slash.fill",
                tint: .cyan,
                actionTitle: "Open",
                destination: { SyncSettingsView() },
                onDismiss: { dismissSetupSuggestion(.reviewSyncSetup) }
            )
        }
    }

    private var homeErrorMessage: String? {
        viewModel.errorMessage ?? fieldChecksModel.errorMessage ?? recordsErrorMessage ?? workingErrorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { homeErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                    fieldChecksModel.errorMessage = nil
                    recordsErrorMessage = nil
                    workingErrorMessage = nil
                }
            }
        )
    }

    private func loadHomeData() {
        viewModel.load(configuration: configuration, using: repository)
        fieldChecksModel.load(using: fieldCheckRepository)

        do {
            dashboardRecords = try repository.fetchDashboardRecords()
            recordsErrorMessage = nil
        } catch {
            recordsErrorMessage = error.localizedDescription
        }

        do {
            protocolTemplates = try workingRepository.fetchTemplates()
            workingErrorMessage = nil
        } catch {
            workingErrorMessage = error.localizedDescription
        }
    }

    private func dismissSetupSuggestion(_ id: HomeSetupSuggestionID) {
        var ids = dismissedSetupSuggestionIDs
        ids.insert(id.rawValue)
        dismissedSetupSuggestionIDsRaw = ids.sorted().joined(separator: ",")
    }

    private func activeSessionSummary(_ session: DashboardWorkingSessionSummary) -> String {
        var components = [
            session.protocolName,
            "\(session.completedQueueItems)/\(session.totalQueueItems) complete"
        ]

        if let sourcePastureName = session.sourcePastureName, !sourcePastureName.isEmpty {
            components.append(sourcePastureName)
        }

        return components.joined(separator: " · ")
    }


    @ViewBuilder
    private func routeDestination(for route: DashboardRoute) -> some View {
        switch route {
        case .animal(let id):
            AnimalDetailView(animalID: id)
        case .pasture(let id):
            PastureDetailView(pastureID: id)
        case .animalList(let kind):
            DashboardAnimalListView(kind: kind, repository: repository)
        case .pastureList:
            DashboardPastureListView(repository: repository)
        }
    }
}

private enum HomeSetupSuggestionID: String {
    case addFirstPasture
    case addFirstAnimal
    case startFirstPastureCheck
    case createWorkingProtocol
    case enableDashboard
    case customizeTagColors
    case completePastureStockingData
    case reviewSyncSetup
}

private struct HomePastureCheckDueItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let activeAnimalCount: Int
    let lastCheckDate: Date?

    var lastCheckDescription: String {
        guard let lastCheckDate else {
            return "No recorded pasture check."
        }

        return "Last checked \(lastCheckDate.formatted(date: .abbreviated, time: .omitted))."
    }
}

private struct HomePastureCheckDueListView: View {
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


private struct HomeAnimalRecordListView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let title: String
    let emptyMessage: String
    let animals: [DashboardAnimalRecord]

    var body: some View {
        List {
            if animals.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(animals) { animal in
                    NavigationLink(value: DashboardRoute.animal(animal.id)) {
                        animalRow(animal)
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    private func animalRow(_ animal: DashboardAnimalRecord) -> some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
            let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)

            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name,
                    damTagNumber: animal.damDisplayTagNumber,
                    damTagColor: damDefinition.color,
                    damTagColorName: damDefinition.name,
                    damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                )

                HStack(spacing: 6) {
                    Text(animal.sex.label)
                    Text("•")
                    Text(animal.animalType.label)

                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pastureName = animal.pastureName, !pastureName.isEmpty {
                        Text("• \(pastureName)")
                    } else {
                        Text("• No Pasture")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HomePastureListView: View {
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

                if pasture.isOverstocked {
                    Label("Needs relief", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if pasture.isRotationReady {
                    Label("Ready", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if pasture.isUnderutilized {
                    Label("Low use", systemImage: "tray.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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

                if let lastGrazedDate = pasture.lastGrazedDate {
                    Text("• grazed \(lastGrazedDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let capacity = pasture.capacityHead, capacity > 0 {
                ProgressView(value: min(max(Double(pasture.activeAnimalCount), 0), capacity), total: capacity)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HomeSummaryCard: Identifiable {
    let id: String
    let title: String
    let value: Int
    let subtitle: String
    let systemImage: String
    let tint: Color

    init(
        title: String,
        value: Int,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) {
        self.id = title
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }
}

private struct HomeSummaryCardView: View {
    let card: HomeSummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: card.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(card.tint))

                Spacer(minLength: 8)

                Text(card.value.formatted())
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 2)

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

private struct HomeListRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let count: Int?
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

            if let count {
                Text(count.formatted())
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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


private struct HomePrimaryActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(tint))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Text(actionTitle)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(tint)
        }
        .padding(18)
        .contentShape(Rectangle())
    }
}

private struct HomeStatusRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

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

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct HomeSuggestionButtonRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HomeSuggestionCard(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            onDismiss: onDismiss
        ) {
            Button(action: onAction) {
                HomeSuggestionActionLabel(title: actionTitle)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(tint)
            .accessibilityLabel(actionTitle)
        }
    }
}

private struct HomeSuggestionNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let destination: Destination
    let onDismiss: () -> Void

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        actionTitle: String,
        @ViewBuilder destination: () -> Destination,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.destination = destination()
        self.onDismiss = onDismiss
    }

    var body: some View {
        HomeSuggestionCard(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            onDismiss: onDismiss
        ) {
            NavigationLink {
                destination
            } label: {
                HomeSuggestionActionLabel(title: actionTitle)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(tint)
            .accessibilityLabel(actionTitle)
        }
    }
}

private struct HomeSuggestionCard<Action: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let onDismiss: () -> Void
    let action: Action

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        onDismiss: @escaping () -> Void,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.onDismiss = onDismiss
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HomeSuggestionIcon(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(.quaternarySystemFill)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(title) suggestion")
            }

            HStack(spacing: 10) {
                action

                Spacer(minLength: 0)
            }
            .padding(.leading, 46)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct HomeSuggestionIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint))
            .accessibilityHidden(true)
    }
}

private struct HomeSuggestionActionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 4)
    }
}

private struct HomeLoadingRow: View {
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
