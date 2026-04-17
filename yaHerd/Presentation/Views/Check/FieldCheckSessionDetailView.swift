import SwiftUI

struct FieldCheckSessionDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var model = FieldCheckSessionDetailViewModel()
    @State private var rosterFilter: FieldCheckRosterFilter = .remaining
    @State private var rosterSearchText = ""
    @State private var showingAddFinding = false
    @State private var showingAddNewborn = false

    let sessionID: UUID

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

    private var sortedNewborns: [FieldCheckNewbornSnapshot] {
        (model.detail?.newborns ?? []).sorted { $0.recordedAt > $1.recordedAt }
    }

    private var suggestedFindingTypes: [FieldCheckFindingType] {
        [.pinkEye, .limping, .newbornPresent, .missingAnimal, .waterIssue, .fenceIssue]
    }

    private var damOptions: [FieldCheckAnimalCheckSnapshot] {
        (model.detail?.animalChecks ?? [])
            .filter { $0.animalID != nil && $0.animalSex != .male }
            .sorted { left, right in
                left.displayTagNumber.localizedStandardCompare(right.displayTagNumber) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if let detail = model.detail {
                List {
                    summarySection(detail)

                    if detail.countMode != .quick && detail.countMode != .observationOnly {
                        rosterSection(detail)
                    }

                    if detail.countMode != .observationOnly {
                        quickCountSection(detail)
                    }

                    findingsSection(detail)
                    newbornSection(detail)
                    notesSection
                    completionSection(detail)
                }
                .searchable(
                    text: $rosterSearchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search roster"
                )
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
        .task(id: sessionID) {
            model.load(sessionID: sessionID, using: repository)
        }
        .onDisappear {
            model.persistNotes(sessionID: sessionID, using: repository)
        }
        .sheet(isPresented: $showingAddFinding) {
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: suggestedFindingTypes,
                    animals: model.detail?.animalChecks ?? []
                ) { input in
                    model.addFinding(sessionID: sessionID, input: input, using: repository)
                }
            }
        }
        .sheet(isPresented: $showingAddNewborn) {
            NavigationStack {
                FieldCheckNewbornEditorView(damOptions: damOptions) { input in
                    model.addNewborn(sessionID: sessionID, input: input, using: repository)
                }
            }
        }
        .alert("Can’t Update Check", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func summarySection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section("Summary") {
            LabeledContent("Pasture") {
                Text(detail.pastureName ?? "—")
            }

            LabeledContent("Count Method") {
                Text(detail.countMode.label)
                    .fontWeight(.semibold)
            }

            if detail.countMode != .observationOnly {
                LabeledContent("Expected") {
                    Text("\(detail.expectedHeadCountSnapshot)")
                }

                LabeledContent("Seen") {
                    Text("\(detail.totalSeen)")
                        .fontWeight(.semibold)
                }

                if detail.countMode != .quick {
                    LabeledContent("Individually Verified") {
                        Text("\(detail.individuallyVerifiedCount)")
                    }
                }

                if detail.countMode == .quick || detail.countMode == .mixed {
                    LabeledContent(detail.countMode == .quick ? "Quick Tagged" : "Quick Tagged Remainder") {
                        Text("\(detail.quickTaggedCount)")
                    }
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
                            model.setAnimalCheckCounted(
                                sessionID: sessionID,
                                animalCheckID: check.id,
                                isCounted: !check.wasCounted,
                                using: repository
                            )
                        },
                        onToggleNeedsAttention: {
                            model.setAnimalCheckNeedsAttention(
                                sessionID: sessionID,
                                animalCheckID: check.id,
                                needsAttention: !check.needsAttention,
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
        } header: {
            Text("Roster")
        } footer: {
            if detail.countMode == .mixed {
                Text("Use the roster for verified animals and quick count for the remainder.")
            } else {
                Text("Each animal can be marked counted once, which prevents accidental double counting.")
            }
        }
    }

    @ViewBuilder
    private func quickCountSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section(detail.countMode == .individual ? "Untagged Count" : "Quick Count") {
            if detail.countMode == .quick || detail.countMode == .mixed {
                Stepper(
                    value: quickTaggedBinding(detail),
                    in: 0...10_000
                ) {
                    LabeledContent(detail.countMode == .quick ? "Tagged Seen" : "Tagged Remainder") {
                        Text("\(detail.quickTaggedCount)")
                    }
                }
            }

            Stepper(
                value: quickUntaggedBinding(detail),
                in: 0...10_000
            ) {
                LabeledContent("Untagged Seen") {
                    Text("\(detail.quickUntaggedCount)")
                }
            }
        }
    }

    @ViewBuilder
    private func findingsSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
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
                            model.addFinding(sessionID: sessionID, input: input, using: repository)
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
                            model.updateFindingStatus(
                                sessionID: sessionID,
                                findingID: finding.id,
                                status: status,
                                using: repository
                            )
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            model.deleteFinding(sessionID: sessionID, findingID: finding.id, using: repository)
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
    private func newbornSection(_ detail: FieldCheckSessionDetailSnapshot) -> some View {
        Section("Newborns") {
            if sortedNewborns.isEmpty {
                Text("No newborns recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedNewborns) { newborn in
                    FieldCheckNewbornRow(
                        newborn: newborn,
                        onConvert: {
                            _ = model.convertNewbornToAnimal(sessionID: sessionID, newbornID: newborn.id, using: repository)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            model.deleteNewborn(sessionID: sessionID, newbornID: newborn.id, using: repository)
                        }
                    }
                }
            }

            Button {
                showingAddNewborn = true
            } label: {
                Label("Add Newborn", systemImage: "figure.and.child.holdinghands")
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
                    model.reopenSession(sessionID: sessionID, using: repository)
                }
            } else {
                Button {
                    model.completeSession(sessionID: sessionID, using: repository)
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
                model.updateQuickCounts(
                    sessionID: sessionID,
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
                model.updateQuickCounts(
                    sessionID: sessionID,
                    quickTaggedCount: detail.quickTaggedCount,
                    quickUntaggedCount: newValue,
                    using: repository
                )
            }
        )
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
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
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

private struct FieldCheckNewbornRow: View {
    let newborn: FieldCheckNewbornSnapshot
    let onConvert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(newborn.isTagged ? (newborn.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tagged Newborn" : newborn.tagNumber) : "Untagged Newborn")
                    .fontWeight(.semibold)
                Spacer()
                if newborn.convertedAnimalID != nil {
                    FieldCheckBadge(title: "Added", tint: .green)
                }
            }

            HStack(spacing: 8) {
                if let damDisplayTagNumber = newborn.damDisplayTagNumber {
                    Text("Dam \(damDisplayTagNumber)")
                }
                if let sex = newborn.sex {
                    Text(sex.label)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !newborn.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(newborn.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let convertedAnimalID = newborn.convertedAnimalID {
                NavigationLink {
                    AnimalDetailView(animalID: convertedAnimalID)
                } label: {
                    Label("Open Animal", systemImage: "arrow.right.circle")
                }
                .font(.footnote)
            } else {
                Button {
                    onConvert()
                } label: {
                    Label("Add to Herd", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
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

private struct FieldCheckNewbornEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let damOptions: [FieldCheckAnimalCheckSnapshot]
    let onSave: (FieldCheckNewbornInput) -> Void

    @State private var recordedAt: Date = .now
    @State private var selectedDamID: UUID?
    @State private var sex: Sex = .unknown
    @State private var isTagged = false
    @State private var tagNumber = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Newborn") {
                DatePicker("Observed", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])

                Picker("Dam", selection: $selectedDamID) {
                    Text("Unknown").tag(Optional<UUID>.none)
                    ForEach(damOptions) { animal in
                        Text(animal.displayTagNumber).tag(animal.animalID)
                    }
                }

                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }

                Toggle("Tagged", isOn: $isTagged)

                if isTagged {
                    TextField("Tag number", text: $tagNumber)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .navigationTitle("Add Newborn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        FieldCheckNewbornInput(
                            recordedAt: recordedAt,
                            sex: sex == .unknown ? nil : sex,
                            isTagged: isTagged,
                            tagNumber: tagNumber,
                            notes: notes,
                            damID: selectedDamID
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
