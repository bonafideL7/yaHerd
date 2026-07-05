import SwiftUI

struct FieldCheckSessionDetailView: View {
    @Environment(\.fieldCheckSessionDetailRepository) private var repository
    @State private var model = FieldCheckSessionDetailViewModel()
    @State private var rosterFilter: FieldCheckRosterFilter = .remaining
    @State private var rosterSearchText = ""
    @State private var showingAddFinding = false
    @State private var showingAddTrackedAnimal = false
    @State private var showingCompletedRoster = false
    @State private var editingFinding: FieldCheckFindingSnapshot?
    @State private var showingFinishConfirmation = false
    @State private var showingQuickCount = false
    @State private var showingFindings = false
    @State private var showingNotes = false
    @State private var pendingFindingAnimalID: UUID?
    @State private var selectedAnimalID: UUID?
    @State private var selectedPane: FieldCheckSessionPane

    private let sessionID: UUID

    init(
        sessionID: UUID,
        opensFindings: Bool = false,
        opensFlaggedRoster: Bool = false,
        opensRemainingRoster: Bool = false,
        opensMissingRoster: Bool = false
    ) {
        self.sessionID = sessionID

        let initialPane: FieldCheckSessionPane = opensFindings ? .findings : .roster

        let initialRosterFilter: FieldCheckRosterFilter
        if opensFlaggedRoster {
            initialRosterFilter = .flagged
        } else if opensMissingRoster {
            initialRosterFilter = .missing
        } else if opensRemainingRoster {
            initialRosterFilter = .remaining
        } else {
            initialRosterFilter = .remaining
        }

        _selectedPane = State(initialValue: initialPane)
        _rosterFilter = State(initialValue: initialRosterFilter)
        _showingFindings = State(initialValue: false)
    }

    private var navigationSubtitleText: String {
        guard let detail = model.detail else { return "" }
        return detail.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var filteredAnimalChecks: [FieldCheckAnimalCheckSnapshot] {
        guard let detail = model.detail else { return [] }
        let quickCountedIDs = quickCountedAnimalCheckIDs(for: detail)
        let checks = sortedAnimalChecks(detail.animalChecks)
            .filter { check in
                let isEffectivelySeen = check.wasCounted || quickCountedIDs.contains(check.id)

                switch rosterFilter {
                case .all:
                    return true
                case .remaining:
                    return !isEffectivelySeen && !check.isMissing
                case .seen:
                    return isEffectivelySeen
                case .missing:
                    return check.isMissing
                case .flagged:
                    return check.needsAttention
                }
            }

        let query = rosterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return checks }

        return checks.filter { check in
            check.displayTagNumber.localizedCaseInsensitiveContains(query)
            || check.animalName.localizedCaseInsensitiveContains(query)
        }
    }

    private var trimmedRosterSearchText: String {
        rosterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rosterEmptyTitle: String {
        if !trimmedRosterSearchText.isEmpty { return "No Matching Animals" }

        switch rosterFilter {
        case .all:
            return "No Animals"
        case .remaining:
            return "No Animals Not Seen"
        case .seen:
            return "No Seen Animals"
        case .missing:
            return "No Missing Animals"
        case .flagged:
            return "No Flagged Animals"
        }
    }

    private var rosterEmptySystemImage: String {
        if !trimmedRosterSearchText.isEmpty { return "magnifyingglass" }
        return rosterFilter.systemImage
    }

    private var rosterEmptyDescription: String {
        if !trimmedRosterSearchText.isEmpty {
            return "No roster entries match the current search and filter."
        }

        switch rosterFilter {
        case .all:
            return "This check does not have any roster entries."
        case .remaining:
            return "Every roster animal is seen, counted by type, or marked missing."
        case .seen:
            return "No animals have been marked seen or counted by type yet."
        case .missing:
            return "No animals are marked missing in this check."
        case .flagged:
            return "No animals are flagged for attention in this check."
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

    private var isRosterSearchFiltering: Bool {
        selectedPane == .roster && !trimmedRosterSearchText.isEmpty
    }

    private var listOrQuickCountToolbarTitle: String {
        selectedPane == .roster ? "Quick Count" : "Animal List"
    }

    private var listOrQuickCountToolbarSystemImage: String {
        selectedPane == .roster ? "plus.forwardslash.minus" : "list.bullet"
    }

    private var listOrQuickCountToolbarTarget: FieldCheckSessionPane {
        selectedPane == .roster ? .quickCount : .roster
    }

    var body: some View {
        Group {
            if let detail = model.detail {
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
        .navigationTitle(model.detail?.displayTitle ?? "Check")
        .navigationBarTitleDisplayMode(.inline)
        .applyFieldCheckNavigationSubtitle(navigationSubtitleText)
        .toolbar {
            if let detail = model.detail {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if detail.isCompleted {
                        Menu {
                            Button {
                                model.reopenSession(sessionID: sessionID, using: repository)
                            } label: {
                                Label("Reopen Check", systemImage: "lock.open")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Check Actions")
                    } else {
                        Button {
                            selectPane(listOrQuickCountToolbarTarget)
                        } label: {
                            Label(listOrQuickCountToolbarTitle, systemImage: listOrQuickCountToolbarSystemImage)
                        }
                        .accessibilityLabel(listOrQuickCountToolbarTitle)

                        Button {
                            selectPane(.findings)
                        } label: {
                            Label("Findings", systemImage: "exclamationmark.bubble")
                        }
                        .accessibilityLabel("Findings")

                        Button {
                            selectPane(.notes)
                        } label: {
                            Label("Notes", systemImage: "note.text")
                        }
                        .accessibilityLabel("Notes")

                        Button {
                            finishSession(from: detail)
                        } label: {
                            Text(detail.remainingExpectedCount == 0 && detail.countVariance == 0 ? "Finish" : "Review")
                        }
                        .tint(detail.remainingExpectedCount == 0 && detail.countVariance == 0 ? Color.accentColor : Color.orange)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.detail?.isCompleted == false {
                Color.clear
                    .frame(height: 104)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.detail?.isCompleted == false && !isRosterSearchFiltering {
                FieldCheckFloatingActionMenu(
                    onAddFinding: {
                        pendingFindingAnimalID = nil
                        showingAddFinding = true
                    },
                    onAddAnimal: {
                        showingAddTrackedAnimal = true
                    },
                    onAddNote: {
                        selectPane(.notes)
                    }
                )
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
        .navigationDestination(isPresented: animalDetailPresentedBinding) {
            if let selectedAnimalID {
                FieldCheckAnimalDetailView(sessionID: sessionID, animalID: selectedAnimalID)
            }
        }
        .task(id: sessionID) {
            model.load(sessionID: sessionID, using: repository)
            syncSelectedPane()
        }
        .onDisappear {
            if model.detail?.isCompleted == false {
                model.persistNotes(sessionID: sessionID, using: repository)
            }
        }
        .sheet(isPresented: $showingAddFinding, onDismiss: { pendingFindingAnimalID = nil }) {
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: suggestedFindingTypes,
                    animals: model.detail?.animalChecks ?? [],
                    initialAnimalID: pendingFindingAnimalID
                ) { input in
                    guard model.detail?.isCompleted == false else { return }
                    model.addFinding(sessionID: sessionID, input: input, using: repository)
                }
            }
        }
        .sheet(isPresented: $showingAddTrackedAnimal) {
            if let detail = model.detail {
                NavigationStack {
                    FieldCheckTrackedAnimalPickerView(session: detail) { animalID in
                        guard model.detail?.isCompleted == false else { return false }
                        return model.addTrackedAnimalToSession(
                            sessionID: sessionID,
                            animalID: animalID,
                            using: repository
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingQuickCount) {
            if let detail = model.detail {
                NavigationStack {
                    quickCountSheetContent(detail)
                }
            }
        }
        .sheet(isPresented: $showingFindings) {
            if let detail = model.detail {
                NavigationStack {
                    findingsSheetContent(detail)
                }
            }
        }
        .sheet(isPresented: $showingNotes, onDismiss: {
            model.persistNotes(sessionID: sessionID, using: repository)
        }) {
            if let detail = model.detail {
                NavigationStack {
                    notesSheetContent(detail)
                }
            }
        }
        .sheet(item: $editingFinding) { finding in
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: suggestedFindingTypes,
                    animals: model.detail?.animalChecks ?? [],
                    finding: finding
                ) { input in
                    guard model.detail?.isCompleted == false else { return }
                    model.updateFinding(
                        sessionID: sessionID,
                        findingID: finding.id,
                        input: input,
                        using: repository
                    )
                }
            }
        }
        .alert("Can’t Update Check", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Finish Check?",
            isPresented: $showingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish Anyway") {
                completeCurrentSession()
            }
            Button("Keep Checking", role: .cancel) {}
        } message: {
            Text(finishConfirmationMessage)
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        if detail.isCompleted {
            completedReviewContent(detail)
        } else {
            activeCheckContent(detail)
        }
    }

    private func activeCheckContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        List {
            if !isRosterSearchFiltering {
                progressHeaderSection(detail)
                archivedPastureSection(detail)
            }

            switch selectedPane {
            case .roster:
                rosterSection(detail)
            case .quickCount:
                quickCountMainSection(detail)
            case .findings:
                findingsMainSection(detail)
            case .notes:
                notesMainSection(detail)
            }
        }
        .refreshable {
            model.refresh(sessionID: sessionID, using: repository)
        }
        .modifier(FieldCheckRosterSearchModifier(isActive: selectedPane == .roster, text: $rosterSearchText))
    }

    private func completedReviewContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        List {
            completedReviewHeaderSection(detail)
            archivedPastureSection(detail)
            completedFindingsSection(detail)
            completedNotesSection(detail)
            completedRosterSnapshotSection(detail)
            completedCountBreakdownSection(detail)
        }
        .refreshable {
            model.refresh(sessionID: sessionID, using: repository)
        }
    }

    @ViewBuilder
    private func archivedPastureSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        if detail.isPastureArchived {
            Section {
                Label {
                    Text("This check is linked to a deleted pasture. Historical roster, counts, findings, and notes remain available.")
                } icon: {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let archivedAt = detail.pastureArchivedAt {
                    LabeledContent("Archived") {
                        Text(archivedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionPaneSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        if availablePanes.count > 1 {
            Section {
                Picker("Check View", selection: $selectedPane) {
                    ForEach(availablePanes) { pane in
                        Text(pane.label).tag(pane)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Image(systemName: selectedPane.systemImage)
                        .foregroundStyle(.secondary)

                    Text(workModeValue(for: selectedPane, detail: detail))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func rosterSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        let visibleAnimalChecks = filteredAnimalChecks
        let quickCountedIDs = quickCountedAnimalCheckIDs(for: detail)

        Section {
            FieldCheckRosterFilterRow(
                selectedFilter: $rosterFilter,
                visibleCount: visibleAnimalChecks.count,
                totalCount: detail.animalChecks.count,
                hasSearchText: !trimmedRosterSearchText.isEmpty,
                onReset: resetRosterFilters
            )

            if visibleAnimalChecks.isEmpty {
                ContentUnavailableView(
                    rosterEmptyTitle,
                    systemImage: rosterEmptySystemImage,
                    description: Text(rosterEmptyDescription)
                )

                if rosterFilter != .all || !trimmedRosterSearchText.isEmpty {
                    Button {
                        resetRosterFilters()
                    } label: {
                        Label("Show All Animals", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(visibleAnimalChecks) { check in
                    FieldCheckAnimalCheckRow(
                        sessionID: detail.id,
                        check: check,
                        isEditable: true,
                        isCountedByQuickCount: quickCountedIDs.contains(check.id),
                        onToggleCounted: {
                            model.setAnimalCheckCounted(
                                sessionID: sessionID,
                                animalCheckID: check.id,
                                isCounted: !check.wasCounted,
                                using: repository
                            )
                        },
                        onToggleMissing: {
                            model.setAnimalCheckMissing(
                                sessionID: sessionID,
                                animalCheckID: check.id,
                                isMissing: !check.isMissing,
                                using: repository
                            )
                        },
                        onAddFinding: { animalID in
                            pendingFindingAnimalID = animalID
                            showingAddFinding = true
                        },
                        onOpenAnimal: { animalID in
                            selectedAnimalID = animalID
                        }
                    )
                }
            }
        } header: {
            Text(trimmedRosterSearchText.isEmpty ? "Animal Checklist" : "Search Results")
        } footer: {
            if trimmedRosterSearchText.isEmpty {
                Text("Default view shows animals not yet seen by tag. Use search to jump directly to a tag number.")
            }
        }
    }

    @ViewBuilder
    private func quickCountMainSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
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
            Text("Counts by type are reflected in the animal checklist so counted animals do not stay in the Not Seen list.")
        }
    }

    @ViewBuilder
    private func findingsMainSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            if sortedFindings.isEmpty {
                ContentUnavailableView(
                    "No Findings",
                    systemImage: "exclamationmark.bubble",
                    description: Text("Use the floating add button to record an issue during this check.")
                )
            } else {
                ForEach(sortedFindings) { finding in
                    findingRow(finding, allowsEditing: true)
                }
            }
        } header: {
            Text("Findings")
        }
    }

    @ViewBuilder
    private func notesMainSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            TextField("Session notes", text: $model.notesDraft, axis: .vertical)
                .lineLimit(4...8)
        } header: {
            Text("Notes")
        } footer: {
            Text("Notes save when you leave this check or switch away from the notes view.")
        }
    }

    @ViewBuilder
    private func quickCountSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showingQuickCount) {
                FieldCheckAnimalQuickCountCounter(
                    remainingRosterChecks: remainingRosterChecks(for: detail),
                    animalTypeCounts: quickAnimalTypeCountsBinding(detail)
                )

                LabeledContent("Breakdown") {
                    Text(quickTypeSummary(for: detail))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            } label: {
                ChecklistDisclosureLabel(
                    title: "Count by Type",
                    subtitle: "Bulk count without leaving the checklist",
                    value: "\(detail.totalSeen)/\(detail.expectedHeadCountSnapshot)",
                    systemImage: "plus.forwardslash.minus",
                    tint: .accentColor
                )
            }
        } footer: {
            if showingQuickCount {
                Text("Count is capped to animals still to check by type.")
            }
        }
    }

    @ViewBuilder
    private func findingsSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showingFindings) {
                Button {
                    showingAddFinding = true
                } label: {
                    Label("Add Finding", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                if sortedFindings.isEmpty {
                    ContentUnavailableView(
                        "No Findings",
                        systemImage: "exclamationmark.bubble",
                        description: Text("Findings added during this check will appear here.")
                    )
                } else {
                    ForEach(sortedFindings) { finding in
                        findingRow(finding, allowsEditing: true)
                    }
                }
            } label: {
                ChecklistDisclosureLabel(
                    title: "Findings",
                    subtitle: detail.openFindingsCount == 0 ? "No open findings" : "Open issues recorded during this check",
                    value: detail.openFindingsCount == 0 ? "None" : "\(detail.openFindingsCount)",
                    systemImage: "exclamationmark.bubble",
                    tint: detail.openFindingsCount == 0 ? Color.secondary : Color.orange
                )
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showingNotes) {
                TextField("Session notes", text: $model.notesDraft, axis: .vertical)
                    .lineLimit(3...6)
            } label: {
                ChecklistDisclosureLabel(
                    title: "Notes",
                    subtitle: detail.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No notes yet" : "Notes added",
                    value: detail.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty" : "Added",
                    systemImage: "note.text",
                    tint: .secondary
                )
            }
        }
    }

    private func quickCountSheetContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        List {
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
            } footer: {
                Text("Count is capped to animals still to check by type.")
            }
        }
        .navigationTitle("Count by Type")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    showingQuickCount = false
                }
            }
        }
    }

    private func findingsSheetContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        List {
            Section {
                Button {
                    showingFindings = false
                    showingAddFinding = true
                } label: {
                    Label("Add Finding", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                if sortedFindings.isEmpty {
                    ContentUnavailableView(
                        "No Findings",
                        systemImage: "exclamationmark.bubble",
                        description: Text("Findings added during this check will appear here.")
                    )
                } else {
                    ForEach(sortedFindings) { finding in
                        findingRow(finding, allowsEditing: true)
                    }
                }
            }
        }
        .navigationTitle("Findings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    showingFindings = false
                }
            }
        }
    }

    private func notesSheetContent(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Form {
            Section {
                TextField("Session notes", text: $model.notesDraft, axis: .vertical)
                    .lineLimit(6...12)
            } footer: {
                Text("Notes are saved when this sheet closes.")
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    showingNotes = false
                }
            }
        }
    }

    private func completedReviewHeaderSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            FieldCheckCompletedReviewHeader(detail: detail)
        }
    }

    @ViewBuilder
    private func completedFindingsSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            if sortedFindings.isEmpty {
                ContentUnavailableView(
                    "No Findings",
                    systemImage: "checkmark.circle",
                    description: Text("No findings were recorded for this check.")
                )
            } else {
                ForEach(sortedFindings) { finding in
                    FieldCheckFindingRow(
                        finding: finding,
                        showsPastureName: false,
                        onStatusChange: { status in
                            model.updateFindingStatus(
                                sessionID: sessionID,
                                findingID: finding.id,
                                status: status,
                                using: repository
                            )
                        }
                    )
                }
            }
        } header: {
            Text("Findings")
        } footer: {
            if !sortedFindings.isEmpty {
                Text("Only finding status can be updated after completion. Reopen this check to edit details or add findings.")
            }
        }
    }

    @ViewBuilder
    private func completedNotesSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            let trimmedNotes = detail.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNotes.isEmpty {
                Text("No notes recorded.")
                    .foregroundStyle(.secondary)
            } else {
                Text(trimmedNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Notes")
        }
    }

    @ViewBuilder
    private func completedRosterSnapshotSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        let issueChecks = completedIssueAnimalChecks(for: detail)
        let allChecks = sortedAnimalChecks(detail.animalChecks)

        Section {
            if issueChecks.isEmpty {
                ContentUnavailableView(
                    "No Roster Issues",
                    systemImage: "checkmark.circle",
                    description: Text("No missing, flagged, or added animals were recorded.")
                )
            } else {
                ForEach(issueChecks) { check in
                    FieldCheckAnimalCheckRow(
                        sessionID: detail.id,
                        check: check,
                        isEditable: false,
                        onToggleCounted: {},
                        onToggleMissing: {},
                        onOpenAnimal: { animalID in
                            selectedAnimalID = animalID
                        }
                    )
                }
            }

            if !allChecks.isEmpty {
                DisclosureGroup(isExpanded: $showingCompletedRoster) {
                    ForEach(allChecks) { check in
                        FieldCheckAnimalCheckRow(
                            sessionID: detail.id,
                            check: check,
                            isEditable: false,
                            onToggleCounted: {},
                            onToggleMissing: {},
                            onOpenAnimal: { animalID in
                                selectedAnimalID = animalID
                            }
                        )
                    }
                } label: {
                    Label("All Roster Entries", systemImage: "tag")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            Text("Roster Snapshot")
        } footer: {
            Text("This is the roster state saved with the completed check.")
        }
    }

    @ViewBuilder
    private func completedCountBreakdownSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            LabeledContent("Seen") {
                Text("\(detail.totalSeen) / \(detail.expectedHeadCountSnapshot)")
                    .fontWeight(.semibold)
            }

            LabeledContent("Difference") {
                if detail.countVariance == 0 {
                    Text("Matched")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(detail.countVariance > 0 ? "+" : "")\(detail.countVariance)")
                        .foregroundStyle(.orange)
                }
            }

            LabeledContent("Seen by Tag") {
                Text("\(detail.individuallyVerifiedCount)")
            }

            LabeledContent("Count Breakdown") {
                Text(quickTypeSummary(for: detail))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Count")
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: FieldCheckFindingSnapshot, allowsEditing: Bool) -> some View {
        let row = FieldCheckFindingRow(
            finding: finding,
            showsPastureName: false,
            onEdit: allowsEditing ? {
                editingFinding = finding
            } : nil,
            onStatusChange: { status in
                model.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: finding.id,
                    status: status,
                    using: repository
                )
            }
        )

        if allowsEditing {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        model.deleteFinding(sessionID: sessionID, findingID: finding.id, using: repository)
                    }
                }
        } else {
            row
        }
    }

    private func progressHeaderSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            FieldCheckProgressHeader(detail: detail)
        }
    }

    private func selectPane(_ pane: FieldCheckSessionPane) {
        if selectedPane == .notes && pane != .notes {
            model.persistNotes(sessionID: sessionID, using: repository)
        }

        if pane != .roster {
            rosterSearchText = ""
        }

        selectedPane = pane
    }

    private func quickCountedAnimalCheckIDs(for detail: FieldCheckSessionDetailSnapshot) -> Set<UUID> {
        var remainingCounts = detail.quickAnimalTypeCounts
        var ids: Set<UUID> = []

        for check in sortedAnimalChecks(detail.animalChecks) {
            guard check.wasExpectedAtStart, !check.wasCounted, !check.isMissing else { continue }
            let availableCount = remainingCounts[check.animalType, default: 0]
            guard availableCount > 0 else { continue }

            ids.insert(check.id)
            remainingCounts[check.animalType] = availableCount - 1
        }

        return ids
    }

    private func resetRosterFilters() {
        rosterSearchText = ""
        rosterFilter = .all
    }

    private func quickAnimalTypeCountsBinding(_ detail: FieldCheckSessionDetailSnapshot) -> Binding<[AnimalType: Int]> {
        Binding(
            get: { detail.quickAnimalTypeCounts },
            set: { newValue in
                model.updateQuickAnimalTypeCounts(
                    sessionID: sessionID,
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

    private func workModeValue(for pane: FieldCheckSessionPane, detail: FieldCheckSessionDetailSnapshot) -> String {
        switch pane {
        case .roster:
            let count = detail.animalChecks.filter { !$0.wasCounted && !$0.isMissing }.count
            return count == 1 ? "1 not seen by tag" : "\(count) not seen by tag"
        case .quickCount:
            return "\(detail.totalSeen)/\(detail.expectedHeadCountSnapshot) seen"
        case .findings:
            let count = detail.openFindingsCount
            return count == 1 ? "1 open" : "\(count) open"
        case .notes:
            return detail.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty" : "Added"
        }
    }

    private func sortedAnimalChecks(_ checks: [FieldCheckAnimalCheckSnapshot]) -> [FieldCheckAnimalCheckSnapshot] {
        checks.sorted { left, right in
            left.displayTagNumber.localizedStandardCompare(right.displayTagNumber) == .orderedAscending
        }
    }

    private func completedIssueAnimalChecks(for detail: FieldCheckSessionDetailSnapshot) -> [FieldCheckAnimalCheckSnapshot] {
        sortedAnimalChecks(detail.animalChecks).filter { check in
            check.isMissing || check.needsAttention || !check.wasExpectedAtStart
        }
    }

    private func shouldConfirmFinish(_ detail: FieldCheckSessionDetailSnapshot) -> Bool {
        detail.remainingExpectedCount > 0 || detail.countVariance != 0
    }

    private var finishConfirmationMessage: String {
        guard let detail = model.detail else { return "Finish this pasture check?" }

        var messages: [String] = []
        if detail.remainingExpectedCount > 0 {
            let noun = detail.remainingExpectedCount == 1 ? "animal is" : "animals are"
            messages.append("\(detail.remainingExpectedCount) \(noun) still not seen.")
        }

        if detail.countVariance != 0 {
            messages.append("The count difference is \(detail.countVariance > 0 ? "+" : "")\(detail.countVariance).")
        }

        messages.append("You can reopen the check later if needed.")
        return messages.joined(separator: " ")
    }

    private func finishSession(from detail: FieldCheckSessionDetailSnapshot) {
        if shouldConfirmFinish(detail) {
            showingFinishConfirmation = true
        } else {
            completeCurrentSession()
        }
    }

    private func completeCurrentSession() {
        model.completeSession(sessionID: sessionID, using: repository)
    }

    private var errorMessage: String? {
        model.errorMessage
    }

    private func syncSelectedPane() {
        let availablePanes = availablePanes
        guard !availablePanes.isEmpty else {
            selectedPane = FieldCheckSessionPane.defaultPane
            return
        }

        if !availablePanes.contains(selectedPane) {
            selectedPane = FieldCheckSessionPane.defaultPane
        }
    }

    private var animalDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedAnimalID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedAnimalID = nil
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
}

private struct FieldCheckFloatingActionMenu: View {
    let onAddFinding: () -> Void
    let onAddAnimal: () -> Void
    let onAddNote: () -> Void

    var body: some View {
        Menu {
            Button {
                onAddFinding()
            } label: {
                Label("Add Finding", systemImage: "exclamationmark.bubble")
            }

            Button {
                onAddAnimal()
            } label: {
                Label("Add Animal", systemImage: "tag.badge.plus")
            }

            Button {
                onAddNote()
            } label: {
                Label("Note", systemImage: "note.text")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Quick actions")
    }
}


private struct FieldCheckRosterFilterRow: View {
    @Binding var selectedFilter: FieldCheckRosterFilter
    let visibleCount: Int
    let totalCount: Int
    let hasSearchText: Bool
    let onReset: () -> Void

    private var countText: String {
        guard totalCount > 0 else { return "No animals" }
        return visibleCount == totalCount ? "\(totalCount) animals" : "\(visibleCount) of \(totalCount)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Roster Filter", selection: $selectedFilter) {
                    ForEach(FieldCheckRosterFilter.allCases) { filter in
                        Label(filter.label, systemImage: filter.systemImage)
                            .tag(filter)
                    }
                }

                if selectedFilter != .all || hasSearchText {
                    Section {
                        Button {
                            onReset()
                        } label: {
                            Label("Show All Animals", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            } label: {
                Label(selectedFilter.label, systemImage: selectedFilter.systemImage)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 12)

            Text(countText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Roster filter, \(selectedFilter.label), \(countText)")
    }
}

private struct FieldCheckRosterSearchModifier: ViewModifier {
    let isActive: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search roster"
            )
        } else {
            content
        }
    }
}

private struct FieldCheckProgressHeader: View {
    let detail: FieldCheckSessionDetailSnapshot

    private var remainingText: String {
        let count = detail.remainingExpectedCount
        return count == 1 ? "1 to check" : "\(count) to check"
    }

    private var differenceText: String {
        guard detail.countVariance != 0 else { return "matched" }
        return "diff \(detail.countVariance > 0 ? "+" : "")\(detail.countVariance)"
    }

    private var statusParts: [String] {
        var parts: [String] = [remainingText, differenceText]
        if detail.openFindingsCount > 0 {
            parts.append(detail.openFindingsCount == 1 ? "1 finding" : "\(detail.openFindingsCount) findings")
        }
        return parts
    }

    private var statusTint: Color {
        detail.remainingExpectedCount == 0 && detail.countVariance == 0 ? Color.secondary : Color.orange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(detail.totalSeen)/\(detail.expectedHeadCountSnapshot)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("seen")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(statusParts.joined(separator: " • "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            if detail.remainingExpectedCount > 0 || detail.countVariance != 0 {
                Image(systemName: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}


private struct ChecklistDisclosureLabel: View {
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FieldCheckWorkModeButton: View {
    let pane: FieldCheckSessionPane
    let value: String
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        isSelected ? .accentColor : .secondary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: pane.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)

                    Text(pane.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(12)
            .glassEffect(.regular.tint(tint.opacity(isSelected ? 0.14 : 0.06)).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct FieldCheckCompletedReviewHeader: View {
    let detail: FieldCheckSessionDetailSnapshot

    private var completionDateText: String {
        (detail.completedAt ?? detail.startedAt).formatted(date: .abbreviated, time: .shortened)
    }

    private var differenceText: String {
        detail.countVariance == 0 ? "Matched" : "\(detail.countVariance > 0 ? "+" : "")\(detail.countVariance)"
    }

    private var differenceTint: Color {
        detail.countVariance == 0 ? Color.green : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed")
                        .font(.headline)

                    Text(completionDateText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                FieldCheckBadge(title: "Done", tint: .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(detail.totalSeen) / \(detail.expectedHeadCountSnapshot)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()

                Text("Seen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], alignment: .leading, spacing: 10) {
                FieldCheckReviewMetricTile(title: "Difference", value: differenceText, tint: differenceTint)
                FieldCheckReviewMetricTile(title: "Missing", value: "\(detail.missingAnimalCount)", tint: detail.missingAnimalCount > 0 ? .orange : .secondary)
                FieldCheckReviewMetricTile(title: "Flagged", value: "\(detail.flaggedAnimalCount)", tint: detail.flaggedAnimalCount > 0 ? .orange : .secondary)
                FieldCheckReviewMetricTile(title: "Open Findings", value: "\(detail.openFindingsCount)", tint: detail.openFindingsCount > 0 ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FieldCheckReviewMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
