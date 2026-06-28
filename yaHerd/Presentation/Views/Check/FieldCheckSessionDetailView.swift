import SwiftUI

struct FieldCheckSessionDetailView: View {
    @Environment(\.fieldCheckSessionDetailRepository) private var repository
    @Environment(\.fieldCheckSessionSetupRepository) private var setupRepository
    @Environment(\.pastureReferenceDataReader) private var pastureReferenceDataReader
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.colorScheme) private var colorScheme
    
    
    @State private var model = FieldCheckSessionDetailViewModel()
    @State private var setupModel = FieldCheckSessionSetupViewModel()
    @State private var rosterFilter: FieldCheckRosterFilter = .all
    @State private var rosterSearchText = ""
    @State private var showingAddFinding = false
    @State private var currentSessionID: UUID?
    @State private var selectedPastureID: UUID?
    @State private var startedAt: Date = .now
    @State private var selectedPane: FieldCheckSessionPane
    
    private let suggestedPastureID: UUID?
    
    init(
        sessionID: UUID,
        opensFindings: Bool = false,
        opensFlaggedRoster: Bool = false,
        opensRemainingRoster: Bool = false,
        opensMissingRoster: Bool = false
    ) {
        self.suggestedPastureID = nil
        _currentSessionID = State(initialValue: sessionID)
        _selectedPastureID = State(initialValue: nil)

        let initialPane: FieldCheckSessionPane
        if opensFindings {
            initialPane = .findings
        } else if opensFlaggedRoster || opensRemainingRoster || opensMissingRoster {
            initialPane = .roster
        } else {
            initialPane = .summary
        }

        let initialRosterFilter: FieldCheckRosterFilter
        if opensFlaggedRoster {
            initialRosterFilter = .flagged
        } else if opensMissingRoster {
            initialRosterFilter = .missing
        } else if opensRemainingRoster {
            initialRosterFilter = .remaining
        } else {
            initialRosterFilter = .all
        }

        _selectedPane = State(initialValue: initialPane)
        _rosterFilter = State(initialValue: initialRosterFilter)
    }
    
    init(suggestedPastureID: UUID? = nil) {
        self.suggestedPastureID = suggestedPastureID
        _currentSessionID = State(initialValue: nil)
        _selectedPastureID = State(initialValue: suggestedPastureID)
        _selectedPane = State(initialValue: .summary)
    }
    
    private var navigationSubtitleText: String {
        guard let detail = model.detail else { return "" }
        return detail.startedAt.formatted(date: .abbreviated, time: .shortened)
    }
    
    private var filteredAnimalChecks: [FieldCheckAnimalCheckSnapshot] {
        let checks = (model.detail?.animalChecks ?? [])
            .sorted { left, right in
                left.displayTagNumber.localizedStandardCompare(right.displayTagNumber) == .orderedAscending
            }
            .filter { check in
                switch rosterFilter {
                case .all:
                    return true
                case .remaining:
                    return !check.wasCounted && !check.isMissing
                case .flagged:
                    return check.needsAttention
                case .missing:
                    return check.isMissing
                }
            }
        
        let query = rosterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return checks }
        
        return checks.filter { check in
            check.displayTagNumber.localizedCaseInsensitiveContains(query)
            || check.animalName.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var sortedFindings: [FieldCheckFindingSnapshot] {
        (model.detail?.findings ?? []).sorted { $0.recordedAt > $1.recordedAt }
    }
    
    private var suggestedFindingTypes: [FieldCheckFindingType] {
        [.waterIssue, .fenceIssue]
    }
    
    private var availablePanes: [FieldCheckSessionPane] {
        FieldCheckSessionPane.allCases
    }
    
    var body: some View {
        Group {
            if currentSessionID == nil {
                setupContent
            } else if let detail = model.detail {
                detailContent(detail)
            } else if model.hasLoaded {
                ContentUnavailableView(
                    "Check unavailable",
                    systemImage: "checklist",
                    description: Text("The selected check could not be loaded.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.detail?.displayTitle ?? (currentSessionID == nil ? "Start Pasture Check" : "Check"))
        .navigationBarTitleDisplayMode(.inline)
        .applyFieldCheckNavigationSubtitle(navigationSubtitleText)
        .task(id: currentSessionID) {
            setupModel.load(using: pastureReferenceDataReader)
            
            if selectedPastureID == nil {
                selectedPastureID = suggestedPastureID
            }
            
            if let currentSessionID {
                model.load(sessionID: currentSessionID, using: repository)
                syncSelectedPane()
            }
        }
        .onDisappear {
            if let currentSessionID {
                model.persistNotes(sessionID: currentSessionID, using: repository)
            }
        }
        .sheet(isPresented: $showingAddFinding) {
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: suggestedFindingTypes,
                    animals: model.detail?.animalChecks ?? []
                ) { input in
                    guard let currentSessionID else { return }
                    model.addFinding(sessionID: currentSessionID, input: input, using: repository)
                }
            }
        }
        .alert("Can’t Update Check", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    @ViewBuilder
    private var setupContent: some View {
        Form {
            startDetailsSection
        }
    }
    
    @ViewBuilder
    private func detailContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        List {
            completionSection(detail)
            
            sessionPaneSection()
            
            switch selectedPane {
            case .summary:
                summarySection(detail)
            case .roster:
                rosterSection(detail)
            case .quickCount:
                quickCountSection(detail)
            case .findings:
                findingsSection
            case .notes:
                notesSection
            }
        }
        .searchable(
            text: $rosterSearchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search roster"
        )
    }
    
    @ViewBuilder
    private var startDetailsSection: some View {
        Section("Start Details") {
            LabeledContent("Pasture") {
                Picker("Pasture", selection: $selectedPastureID) {
                    Text("Select").tag(Optional<UUID>.none)
                    ForEach(setupModel.pastures) { pasture in
                        Text(pasture.name).tag(Optional(pasture.id))
                    }
                }
                .labelsHidden()
            }
            
            LabeledContent("Started") {
                DatePicker(
                    "Started",
                    selection: $startedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }
            
            Text("Roster verification, quick counts, findings, and notes are all available in the session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            TextField("Opening notes", text: $model.notesDraft, axis: .vertical)
                .lineLimit(3...5)
            
            Button {
                startSession()
            } label: {
                Label("Start Pasture Check", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .disabled(selectedPastureID == nil)
        }
    }
    
    @ViewBuilder
    private func sessionPaneSection() -> some View {
        if availablePanes.count > 1 {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availablePanes) { pane in
                            Button {
                                selectedPane = pane
                            } label: {
                                Text(pane.label)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .background {
                                Capsule()
                                    .fill(selectedPane == pane ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(selectedPane == pane ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
                            }
                            .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }
    
    private func summarySection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section("Summary") {
            LabeledContent("Expected") {
                Text("\(detail.expectedHeadCountSnapshot)")
            }
            
            LabeledContent("Seen") {
                Text("\(detail.totalSeen)")
                    .fontWeight(.semibold)
            }
            
            LabeledContent("Individually Verified") {
                Text("\(detail.individuallyVerifiedCount)")
            }
            
            LabeledContent("Quick Count") {
                Text("\(detail.quickAnimalTypeCounts.values.reduce(0, +))")
            }
            
            LabeledContent("Variance") {
                Text(detail.countVariance == 0 ? "Matched" : detail.countVariance > 0 ? "+\(detail.countVariance)" : "\(detail.countVariance)")
                    .foregroundStyle(detail.countVariance == 0 ? .green : .orange)
            }
            
            LabeledContent("Remaining") {
                Text("\(detail.remainingExpectedCount)")
                    .foregroundStyle(detail.remainingExpectedCount == 0 ? .green : .orange)
            }
            
            if detail.missingAnimalCount > 0 {
                LabeledContent("Marked Missing") {
                    Text("\(detail.missingAnimalCount)")
                        .foregroundStyle(.orange)
                }
            }
            
            if detail.openFindingsCount > 0 {
                LabeledContent("Open Findings") {
                    Text("\(detail.openFindingsCount)")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    @ViewBuilder
    private func rosterSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            Picker("Roster", selection: $rosterFilter) {
                ForEach(FieldCheckRosterFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            
            if filteredAnimalChecks.isEmpty {
                ContentUnavailableView(
                    "No Animals",
                    systemImage: "tag",
                    description: Text("No roster entries match the current filter.")
                )
            } else {
                ForEach(filteredAnimalChecks) { check in
                    FieldCheckAnimalCheckRow(
                        sessionID: detail.id,
                        check: check,
                        onToggleCounted: {
                            guard let currentSessionID else { return }
                            model.setAnimalCheckCounted(
                                sessionID: currentSessionID,
                                animalCheckID: check.id,
                                isCounted: !check.wasCounted,
                                using: repository
                            )
                        }
                    )
                }
            }
        } header: {
            Text("Roster")
        } footer: {
            Text("Each animal can be marked counted once, which prevents accidental double counting.")
        }
    }
    
    @ViewBuilder
    private func quickCountSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            FieldCheckAnimalQuickCountCounter(
                remainingRosterChecks: remainingRosterChecks(for: detail),
                animalTypeCounts: quickAnimalTypeCountsBinding(detail)
            )

            LabeledContent("Breakdown") {
                Text(quickTypeSummary(for: detail))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quick Count")
        } footer: {
            Text("Quick counts use the current remaining roster by animal type.")
        }
    }
    
    @ViewBuilder
    private var findingsSection: some View {
        Section("Findings") {
            
            Button {
                showingAddFinding = true
            } label: {
                HStack {
                    Text("Add Finding")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
            
            if sortedFindings.isEmpty {
                Text("No findings recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedFindings) { finding in
                    FieldCheckFindingRow(
                        finding: finding,
                        onStatusChange: { status in
                            guard let currentSessionID else { return }
                            model.updateFindingStatus(
                                sessionID: currentSessionID,
                                findingID: finding.id,
                                status: status,
                                using: repository
                            )
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            guard let currentSessionID else { return }
                            model.deleteFinding(sessionID: currentSessionID, findingID: finding.id, using: repository)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            TextField("Session notes", text: $model.notesDraft, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    
    @ViewBuilder
    private func completionSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        if detail.isCompleted {
            LabeledContent("Completed") {
                Text((detail.completedAt ?? .now).formatted(date: .abbreviated, time: .shortened))
            }
            
            Button("Reopen Check") {
                guard let currentSessionID else { return }
                model.reopenSession(sessionID: currentSessionID, using: repository)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    guard let currentSessionID else { return }
                    model.completeSession(sessionID: currentSessionID, using: repository)
                } label: {
                    Label("Complete Check", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                
                HStack(spacing: 12) {
                    Text("Seen \(detail.totalSeen)")
                        .font(.caption.weight(.semibold))
                    
                    Text("Expected \(detail.expectedHeadCountSnapshot)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
    
    private func quickAnimalTypeCountsBinding(_ detail: FieldCheckSessionDetailSnapshot) -> Binding<[AnimalType: Int]> {
        Binding(
            get: { detail.quickAnimalTypeCounts },
            set: { newValue in
                guard let currentSessionID else { return }
                model.updateQuickAnimalTypeCounts(
                    sessionID: currentSessionID,
                    counts: newValue,
                    using: repository
                )
            }
        )
    }

    private func remainingRosterChecks(for detail: FieldCheckSessionDetailSnapshot) -> [FieldCheckAnimalCheckSnapshot] {
        detail.animalChecks.filter { check in
            check.wasExpectedAtStart && !check.wasCounted && !check.isMissing
        }
    }

    private func quickTypeSummary(for detail: FieldCheckSessionDetailSnapshot) -> String {
        let counts = detail.quickAnimalTypeCounts
        let parts = AnimalType.allCases.compactMap { animalType -> String? in
            let count = counts[animalType, default: 0]
            guard count > 0 else { return nil }
            return "\(animalType.label) \(count)"
        }

        return parts.isEmpty ? "None" : parts.joined(separator: " • ")
    }

    private func startSession() {
        do {
            let sessionID = try setupModel.createSession(
                pastureID: selectedPastureID,
                startedAt: startedAt,
                notes: model.notesDraft,
                using: setupRepository
            )
            currentSessionID = sessionID
            selectedPane = FieldCheckSessionPane.defaultPane
            model.load(sessionID: sessionID, using: repository)
        } catch {
            setupModel.errorMessage = error.localizedDescription
        }
    }
    
    private var errorMessage: String? {
        model.errorMessage ?? setupModel.errorMessage
    }
    
    private func syncSelectedPane() {
        let availablePanes = availablePanes
        guard !availablePanes.isEmpty else {
            selectedPane = .summary
            return
        }
        
        if !availablePanes.contains(selectedPane) {
            selectedPane = FieldCheckSessionPane.defaultPane
        }
    }
    
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                    setupModel.errorMessage = nil
                }
            }
        )
    }
}
