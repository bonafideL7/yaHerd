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
    }

    private var navigationSubtitleText: String {
        guard let detail = model.detail else { return "" }
        return detail.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var filteredAnimalChecks: [FieldCheckAnimalCheckSnapshot] {
        let checks = sortedAnimalChecks(model.detail?.animalChecks ?? [])
            .filter { check in
                switch rosterFilter {
                case .all:
                    return true
                case .remaining:
                    return !check.wasCounted && !check.isMissing
                case .seen:
                    return check.wasCounted
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
            return "Every roster animal is either seen by tag or marked missing."
        case .seen:
            return "No animals have been marked seen yet."
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
            if model.detail?.isCompleted == true {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            model.reopenSession(sessionID: sessionID, using: repository)
                        } label: {
                            Label("Reopen Check", systemImage: "lock.open")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Check Actions")
                }
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
        .sheet(isPresented: $showingAddFinding) {
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: suggestedFindingTypes,
                    animals: model.detail?.animalChecks ?? []
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
            progressHeaderSection(detail)
            archivedPastureSection(detail)
            sessionPaneSection(detail)

            switch selectedPane {
            case .roster:
                rosterSection(detail)
            case .quickCount:
                quickCountSection(detail)
            case .findings:
                findingsSection(detail)
            case .notes:
                notesSection(detail)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 10)], spacing: 10) {
                    ForEach(availablePanes) { pane in
                        FieldCheckWorkModeButton(
                            pane: pane,
                            value: workModeValue(for: pane, detail: detail),
                            isSelected: selectedPane == pane
                        ) {
                            selectedPane = pane
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Work")
            }
        }
    }

    @ViewBuilder
    private func rosterSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        let visibleAnimalChecks = filteredAnimalChecks

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
                        }
                    )
                }
            }

            Button {
                showingAddTrackedAnimal = true
            } label: {
                Label("Add Animal", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
        } header: {
            Text("Roster")
        } footer: {
            Text("Use Add Animal only when an existing herd animal has moved into this pasture.")
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
            Text("Count")
        } footer: {
            Text("Count is capped to animals still to check by type.")
        }
    }

    @ViewBuilder
    private func findingsSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
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
        } header: {
            Text("Findings")
        }
    }

    @ViewBuilder
    private func notesSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            TextField("Session notes", text: $model.notesDraft, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Notes")
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
                        onToggleMissing: {}
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
                            onToggleMissing: {}
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
            FieldCheckProgressHeader(
                detail: detail,
                onFinish: {
                    if shouldConfirmFinish(detail) {
                        showingFinishConfirmation = true
                    } else {
                        completeCurrentSession()
                    }
                }
            )
        }
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
    let onFinish: () -> Void

    private var remainingText: String {
        let count = detail.remainingExpectedCount
        return count == 1 ? "1 To Check" : "\(count) To Check"
    }

    private var differenceText: String {
        guard detail.countVariance != 0 else { return "Matched" }
        return "Difference \(detail.countVariance > 0 ? "+" : "")\(detail.countVariance)"
    }

    private var isReadyToFinish: Bool {
        detail.remainingExpectedCount == 0 && detail.countVariance == 0
    }

    private var finishActionTitle: String {
        isReadyToFinish ? "Finish Check" : "Review & Finish"
    }

    private var finishActionTint: Color {
        isReadyToFinish ? .accentColor : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(detail.totalSeen) / \(detail.expectedHeadCountSnapshot)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("Seen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                FieldCheckBadge(
                    title: detail.remainingExpectedCount == 0 ? "All Seen" : remainingText,
                    tint: detail.remainingExpectedCount == 0 ? .green : .orange
                )

                FieldCheckBadge(
                    title: differenceText,
                    tint: detail.countVariance == 0 ? .secondary : .orange
                )

                FieldCheckBadge(
                    title: detail.openFindingsCount == 1 ? "1 Finding" : "\(detail.openFindingsCount) Findings",
                    tint: detail.openFindingsCount == 0 ? .secondary : .orange
                )
            }

            if detail.remainingExpectedCount > 0 || detail.countVariance != 0 {
                Label(statusMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            finishButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var finishButton: some View {
        if isReadyToFinish {
            Button(action: onFinish) {
                Label(finishActionTitle, systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
            .tint(finishActionTint)
        } else {
            Button(action: onFinish) {
                Label(finishActionTitle, systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(finishActionTint)
        }
    }

    private var statusMessage: String {
        if detail.remainingExpectedCount > 0 {
            let noun = detail.remainingExpectedCount == 1 ? "animal" : "animals"
            return "\(detail.remainingExpectedCount) \(noun) still not seen."
        }

        return "Count difference: \(detail.countVariance > 0 ? "+" : "")\(detail.countVariance)."
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
        detail.countVariance == 0 ? .green : .orange
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
