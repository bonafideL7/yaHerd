import SwiftUI

struct FieldCheckSessionDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var model = FieldCheckSessionDetailViewModel()
    @State private var setupModel = FieldCheckSessionSetupViewModel()
    @State private var rosterFilter: FieldCheckRosterFilter = .remaining
    @State private var rosterSearchText = ""
    @State private var showingAddFinding = false
    @State private var currentSessionID: UUID?
    @State private var selectedPastureID: UUID?
    @State private var startedAt: Date = .now
    @State private var selectedPane: FieldCheckSessionPane = .summary

    private let suggestedPastureID: UUID?

    init(sessionID: UUID) {
        self.suggestedPastureID = nil
        _currentSessionID = State(initialValue: sessionID)
        _selectedPastureID = State(initialValue: nil)
    }

    init(suggestedPastureID: UUID? = nil) {
        self.suggestedPastureID = suggestedPastureID
        _currentSessionID = State(initialValue: nil)
        _selectedPastureID = State(initialValue: suggestedPastureID)
    }

    private var repository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
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
                case .counted:
                    return check.wasCounted
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
        [.pinkEye, .limping, .missingAnimal, .waterIssue, .fenceIssue]
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
        .task(id: currentSessionID) {
            setupModel.load(using: repository)

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
            startDetailsSection
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

            completionSection(detail)
        }
        .searchable(
            text: $rosterSearchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search roster"
        )
    }

    @ViewBuilder
    private var startDetailsSection: some View {
        Section(currentSessionID == nil ? "Start Details" : "Started") {
            LabeledContent("Pasture") {
                if currentSessionID == nil {
                    Picker("Pasture", selection: $selectedPastureID) {
                        Text("Select").tag(Optional<UUID>.none)
                        ForEach(setupModel.pastures) { pasture in
                            Text(pasture.name).tag(Optional(pasture.id))
                        }
                    }
                    .labelsHidden()
                } else {
                    Text(model.detail?.pastureName ?? "—")
                }
            }

            LabeledContent("Started") {
                if currentSessionID == nil {
                    DatePicker(
                        "Started",
                        selection: $startedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                } else {
                    Text((model.detail?.startedAt ?? startedAt).formatted(date: .abbreviated, time: .shortened))
                }
            }

            if currentSessionID == nil {
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
                .disabled(selectedPastureID == nil)
            }
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

            LabeledContent("Quick Tagged") {
                Text("\(detail.quickTaggedCount)")
            }

            LabeledContent("Quick Untagged") {
                Text("\(detail.quickUntaggedCount)")
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
                        check: check,
                        onToggleCounted: {
                            guard let currentSessionID else { return }
                            model.setAnimalCheckCounted(
                                sessionID: currentSessionID,
                                animalCheckID: check.id,
                                isCounted: !check.wasCounted,
                                using: repository
                            )
                        },
                        onToggleNeedsAttention: {
                            guard let currentSessionID else { return }
                            model.setAnimalCheckNeedsAttention(
                                sessionID: currentSessionID,
                                animalCheckID: check.id,
                                needsAttention: !check.needsAttention,
                                using: repository
                            )
                        },
                        onToggleMissing: {
                            guard let currentSessionID else { return }
                            model.setAnimalCheckMissing(
                                sessionID: currentSessionID,
                                animalCheckID: check.id,
                                isMissing: !check.isMissing,
                                using: repository
                            )
                        }
                    )
                }
            }
        } header: {
            Text("Roster")
        } footer: {
            Text("Each animal can be marked counted once, which prevents accidental double counting. Use quick counts for tagged or untagged animals you do not verify individually.")
        }
    }

    @ViewBuilder
    private func quickCountSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section {
            Stepper(
                value: quickTaggedBinding(detail),
                in: 0...10_000
            ) {
                LabeledContent("Tagged Quick Count") {
                    Text("\(detail.quickTaggedCount)")
                }
            }

            Stepper(
                value: quickUntaggedBinding(detail),
                in: 0...10_000
            ) {
                LabeledContent("Untagged Quick Count") {
                    Text("\(detail.quickUntaggedCount)")
                }
            }
        } header: {
            Text("Quick Count")
        } footer: {
            Text("Use these totals for animals seen without individual roster verification.")
        }
    }

    @ViewBuilder
    private var findingsSection: some View {
        Section("Findings") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedFindingTypes) { type in
                        Button {
                            let input = FieldCheckFindingInput(
                                recordedAt: .now,
                                type: type,
                                severity: defaultSeverity(for: type),
                                status: .open,
                                note: "",
                                animalID: nil
                            )
                            guard let currentSessionID else { return }
                            model.addFinding(sessionID: currentSessionID, input: input, using: repository)
                        } label: {
                            Label(type.label, systemImage: type.systemImage)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

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

            Button {
                showingAddFinding = true
            } label: {
                Label("Add Finding", systemImage: "plus")
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
        Section {
            if detail.isCompleted {
                LabeledContent("Completed") {
                    Text((detail.completedAt ?? .now).formatted(date: .abbreviated, time: .shortened))
                }

                Button("Reopen Check") {
                    guard let currentSessionID else { return }
                    model.reopenSession(sessionID: currentSessionID, using: repository)
                }
            } else {
                Button {
                    guard let currentSessionID else { return }
                    model.completeSession(sessionID: currentSessionID, using: repository)
                } label: {
                    Label("Complete Check", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func quickTaggedBinding(_ detail: FieldCheckSessionDetailSnapshot) -> Binding<Int> {
        Binding(
            get: { detail.quickTaggedCount },
            set: { newValue in
                guard let currentSessionID else { return }
                model.updateQuickCounts(
                    sessionID: currentSessionID,
                    quickTaggedCount: newValue,
                    quickUntaggedCount: detail.quickUntaggedCount,
                    using: repository
                )
            }
        )
    }

    private func quickUntaggedBinding(_ detail: FieldCheckSessionDetailSnapshot) -> Binding<Int> {
        Binding(
            get: { detail.quickUntaggedCount },
            set: { newValue in
                guard let currentSessionID else { return }
                model.updateQuickCounts(
                    sessionID: currentSessionID,
                    quickTaggedCount: detail.quickTaggedCount,
                    quickUntaggedCount: newValue,
                    using: repository
                )
            }
        )
    }

    private func startSession() {
        do {
            let sessionID = try setupModel.createSession(
                pastureID: selectedPastureID,
                startedAt: startedAt,
                notes: model.notesDraft,
                using: repository
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

    private func defaultSeverity(for type: FieldCheckFindingType) -> FieldCheckFindingSeverity {
        switch type {
        case .injury, .medicalAttention, .calvingInProgress:
            return .critical
        case .pinkEye, .limping, .missingAnimal, .waterIssue, .fenceIssue:
            return .warning
        default:
            return .info
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

private struct FieldCheckAnimalCheckRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let check: FieldCheckAnimalCheckSnapshot
    let onToggleCounted: () -> Void
    let onToggleNeedsAttention: () -> Void
    let onToggleMissing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                let definition = tagColorLibrary.resolvedDefinition(tagColorID: check.displayTagColorID)
                AnimalTagView(
                    tagNumber: check.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name,
                    size: .compact
                )

                VStack(alignment: .leading, spacing: 4) {
                    if !check.animalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(check.animalName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if check.wasCounted {
                            FieldCheckBadge(title: "Counted", tint: .green)
                        }
                        if check.needsAttention {
                            FieldCheckBadge(title: "Flagged", tint: .orange)
                        }
                        if check.isMissing {
                            FieldCheckBadge(title: "Missing", tint: .orange)
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    onToggleCounted()
                } label: {
                    Label(check.wasCounted ? "Counted" : "Count", systemImage: check.wasCounted ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(check.wasCounted ? .green : .accentColor)

                Button {
                    onToggleNeedsAttention()
                } label: {
                    Label("Flag", systemImage: check.needsAttention ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)

                Button {
                    onToggleMissing()
                } label: {
                    Label("Missing", systemImage: check.isMissing ? "questionmark.circle.fill" : "questionmark.circle")
                }
                .buttonStyle(.bordered)
            }

            if let animalID = check.animalID {
                NavigationLink {
                    AnimalDetailView(animalID: animalID)
                } label: {
                    Label("Open Animal", systemImage: "arrow.right.circle")
                        .font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FieldCheckFindingRow: View {
    let finding: FieldCheckFindingSnapshot
    var showsAnimalLink = true
    var onStatusChange: ((FieldCheckFindingStatus) -> Void)? = nil

    private var tint: Color {
        switch finding.severity {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(finding.type.label, systemImage: finding.type.systemImage)
                    .fontWeight(.semibold)
                Spacer()
                FieldCheckBadge(title: finding.status.label, tint: tint)
            }

            if let animalDisplayTagNumber = finding.animalDisplayTagNumber {
                if showsAnimalLink, let animalID = finding.animalID {
                    NavigationLink {
                        AnimalDetailView(animalID: animalID)
                    } label: {
                        Text(animalDisplayTagNumber)
                            .font(.subheadline)
                    }
                } else {
                    Text(animalDisplayTagNumber)
                        .font(.subheadline)
                }
            }

            if let pastureName = finding.pastureName {
                Text(pastureName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !finding.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(finding.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let onStatusChange {
                Menu("Update Status") {
                    ForEach(FieldCheckFindingStatus.allCases) { status in
                        Button(status.label) {
                            onStatusChange(status)
                        }
                    }
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FieldCheckBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct FieldCheckFindingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let suggestedTypes: [FieldCheckFindingType]
    let animals: [FieldCheckAnimalCheckSnapshot]
    let onSave: (FieldCheckFindingInput) -> Void

    @State private var recordedAt: Date = .now
    @State private var type: FieldCheckFindingType
    @State private var severity: FieldCheckFindingSeverity
    @State private var status: FieldCheckFindingStatus = .open
    @State private var note = ""
    @State private var selectedAnimalID: UUID?

    init(
        suggestedTypes: [FieldCheckFindingType],
        animals: [FieldCheckAnimalCheckSnapshot],
        onSave: @escaping (FieldCheckFindingInput) -> Void
    ) {
        self.suggestedTypes = suggestedTypes
        self.animals = animals
        self.onSave = onSave
        _type = State(initialValue: suggestedTypes.first ?? .generalObservation)
        _severity = State(initialValue: .warning)
    }

    private var animalOptions: [FieldCheckAnimalCheckSnapshot] {
        animals
            .filter { $0.animalID != nil }
            .sorted { left, right in
                left.displayTagNumber.localizedStandardCompare(right.displayTagNumber) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section("Finding") {
                DatePicker("Observed", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])

                Picker("Type", selection: $type) {
                    ForEach(FieldCheckFindingType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                Picker("Severity", selection: $severity) {
                    ForEach(FieldCheckFindingSeverity.allCases) { severity in
                        Text(severity.label).tag(severity)
                    }
                }

                Picker("Status", selection: $status) {
                    ForEach(FieldCheckFindingStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
            }

            Section("Animal") {
                Picker("Linked Animal", selection: $selectedAnimalID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(animalOptions) { animal in
                        Text(animal.displayTagNumber).tag(animal.animalID)
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .navigationTitle("Add Finding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        FieldCheckFindingInput(
                            recordedAt: recordedAt,
                            type: type,
                            severity: severity,
                            status: status,
                            note: note,
                            animalID: selectedAnimalID
                        )
                    )
                    dismiss()
                }
            }
        }
    }
}

private enum FieldCheckRosterFilter: String, CaseIterable, Identifiable {
    case all
    case remaining
    case counted
    case flagged
    case missing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .remaining:
            return "Remaining"
        case .counted:
            return "Counted"
        case .flagged:
            return "Flagged"
        case .missing:
            return "Missing"
        }
    }
}

private enum FieldCheckSessionPane: String, CaseIterable, Identifiable {
    case summary
    case roster
    case quickCount
    case findings
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary:
            return "Summary"
        case .roster:
            return "Roster"
        case .quickCount:
            return "Quick Count"
        case .findings:
            return "Findings"
        case .notes:
            return "Notes"
        }
    }

    static let defaultPane: FieldCheckSessionPane = .roster
}
