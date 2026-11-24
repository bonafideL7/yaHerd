import SwiftUI

struct FieldCheckAnimalDetailView: View {
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    private var animalRepository: any AnimalDetailRepository { fieldCheckDependencies.animalRepository }
    private var fieldCheckRepository: any FieldCheckAnimalDetailRepository { fieldCheckDependencies.animalDetailRepository }
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    @State private var model = FieldCheckAnimalDetailViewModel()
    @State private var originatingHerdID: UUID?
    @State private var originatingHerdSelectionRevision: UInt64?
    @State private var isLineageExpanded = false
    @State private var showingAddOffspring = false
    @State private var showingAddFinding = false
    @State private var editingFinding: FieldCheckFindingSnapshot?

    let sessionID: UUID
    let animalID: UUID

    private var displayedTagNumber: String {
        guard isPresentingOriginatingHerd else { return "" }
        return model.animalDetail?.displayTagNumber ?? ""
    }

    private var displayedTagColorID: UUID? {
        guard isPresentingOriginatingHerd else { return nil }
        return model.animalDetail?.displayTagColorID
    }

    private var isPresentingOriginatingHerd: Bool {
        model.isOriginatingSelectionCurrent(
            herdSelection,
            originatingHerdID: originatingHerdID,
            originatingSelectionRevision: originatingHerdSelectionRevision
        )
    }

    private var isSessionEditable: Bool {
        dataAccessMode.allowsDataMutations
            && isPresentingOriginatingHerd
            && model.sessionDetail?.isCompleted == false
            && model.sessionDetail?.isPastureArchived == false
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

    var body: some View {
        Group {
            if originatingHerdSelectionRevision != nil && !isPresentingOriginatingHerd {
                ContentUnavailableView(
                    "Herd Changed",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Reopen this animal in the selected Herd to continue.")
                )
            } else if isPresentingOriginatingHerd, let detail = model.animalDetail {
                Form {
                    if let animalCheck = model.animalCheck {
                        fieldCheckStatusSection(animalCheck, isEditable: isSessionEditable)
                        fieldCheckFindingsSection(isEditable: isSessionEditable)
                    }

                    AnimalDetailOffspringSection(
                        detail: detail,
                        canAddOffspring: isSessionEditable && model.preparedOffspringEditor != nil,
                        onAddOffspring: {
                            showingAddOffspring = true
                        }
                    )
                    AnimalDetailDistinguishingFeaturesSection(detail: detail)
                    AnimalDetailLineageSection(isExpanded: $isLineageExpanded, detail: detail)
                }
            } else if model.hasLoaded {
                ContentUnavailableView("Animal Not Found", systemImage: "tag")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Animal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !displayedTagNumber.isEmpty {
                ToolbarItem(placement: .principal) {
                    let def = tagColorLibrary.resolvedDefinition(tagColorID: displayedTagColorID)
                    AnimalTagView(
                        tagNumber: displayedTagNumber,
                        color: def.color,
                        colorName: def.name,
                        size: .compact
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddOffspring, onDismiss: {
            guard isPresentingOriginatingHerd else { return }
            model.refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }) {
            if isPresentingOriginatingHerd, let preparedEditor = model.preparedOffspringEditor {
                AddAnimalView(
                    title: "Add Offspring",
                    initialDraft: preparedEditor.draft,
                    editorContext: preparedEditor.context
                ) { createdAnimal in
                    try await model.addTrackedAnimalToSession(
                        animalID: createdAnimal.id,
                        sessionID: sessionID,
                        fieldCheckRepository: fieldCheckRepository,
                        mayContinue: { isPresentingOriginatingHerd }
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddFinding) {
            if isPresentingOriginatingHerd {
                NavigationStack {
                    FieldCheckFindingEditorView(
                        suggestedTypes: [.pinkEye, .limping, .missingAnimal],
                        animals: model.sessionDetail?.animalChecks ?? [],
                        initialAnimalID: animalID
                    ) { input in
                        guard isSessionEditable else { return }
                        Task { @MainActor in
                            await model.addFinding(
                                animalID: animalID,
                                sessionID: sessionID,
                                input: input,
                                animalRepository: animalRepository,
                                fieldCheckRepository: fieldCheckRepository,
                                mayContinue: { isPresentingOriginatingHerd }
                            )
                        }
                    }
                }
            }
        }
        .sheet(item: $editingFinding) { finding in
            if isPresentingOriginatingHerd {
                NavigationStack {
                    FieldCheckFindingEditorView(
                        suggestedTypes: [.pinkEye, .limping, .missingAnimal],
                        animals: model.sessionDetail?.animalChecks ?? [],
                        finding: finding
                    ) { input in
                        guard isSessionEditable else { return }
                        Task { @MainActor in
                            await model.updateFinding(
                                animalID: animalID,
                                sessionID: sessionID,
                                findingID: finding.id,
                                input: input,
                                animalRepository: animalRepository,
                                fieldCheckRepository: fieldCheckRepository,
                                mayContinue: { isPresentingOriginatingHerd }
                            )
                        }
                    }
                }
            }
        }
        .refreshable {
            guard isPresentingOriginatingHerd else { return }
            model.refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }
        .task {
            guard originatingHerdID == nil else { return }
            originatingHerdID = herdSelection.currentHerdID
            originatingHerdSelectionRevision = herdSelection.selectionRevision
            guard isPresentingOriginatingHerd else { return }
            if !model.hasLoaded {
                model.load(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
            }
        }
        .alert("Can’t Update Animal", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .onChange(of: fieldCheckDependencies.mutationStream.fieldCheckRevision) { _, _ in
            guard isPresentingOriginatingHerd else { return }
            model.load(
                animalID: animalID, sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            guard !isPresentingOriginatingHerd else { return }
            showingAddOffspring = false
            showingAddFinding = false
            editingFinding = nil
        }
    }

    @ViewBuilder
    private func fieldCheckStatusSection(_ animalCheck: FieldCheckAnimalCheckSnapshot, isEditable: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fieldCheckStatusTitle(for: animalCheck))
                            .font(.headline)

                        Text(statusSummary(for: animalCheck))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    FieldCheckBadge(
                        title: fieldCheckStatusBadgeTitle(for: animalCheck),
                        tint: fieldCheckStatusTint(for: animalCheck)
                    )
                }

                if isEditable {
                    statusActions(for: animalCheck)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Check Status")
        } footer: {
            if isEditable {
                Text("Use Mark Missing only after checking the pasture and not finding this animal.")
            }
        }
    }

    @ViewBuilder
    private func statusActions(for animalCheck: FieldCheckAnimalCheckSnapshot) -> some View {
        if animalCheck.isMissing {
            Button {
                Task { @MainActor in
                    await model.setAnimalCheckCounted(
                        animalID: animalID,
                        sessionID: sessionID,
                        isCounted: true,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository,
                        mayContinue: { isPresentingOriginatingHerd }
                    )
                }
            } label: {
                Label("Mark Found", systemImage: "checkmark.circle")
                    .readableAccentForeground()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else if animalCheck.wasCounted {
            Button {
                Task { @MainActor in
                    await model.setAnimalCheckCounted(
                        animalID: animalID,
                        sessionID: sessionID,
                        isCounted: false,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository,
                        mayContinue: { isPresentingOriginatingHerd }
                    )
                }
            } label: {
                Label("Mark Not Seen", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        await model.setAnimalCheckCounted(
                            animalID: animalID,
                            sessionID: sessionID,
                            isCounted: true,
                            animalRepository: animalRepository,
                            fieldCheckRepository: fieldCheckRepository,
                            mayContinue: { isPresentingOriginatingHerd }
                        )
                    }
                } label: {
                    Label("Mark Seen", systemImage: "checkmark.circle")
                        .readableAccentForeground()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { @MainActor in
                        await model.setAnimalCheckMissing(
                            animalID: animalID,
                            sessionID: sessionID,
                            isMissing: true,
                            animalRepository: animalRepository,
                            fieldCheckRepository: fieldCheckRepository,
                            mayContinue: { isPresentingOriginatingHerd }
                        )
                    }
                } label: {
                    Label("Mark Missing", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private func fieldCheckFindingsSection(isEditable: Bool) -> some View {
        Section {
            if isEditable {
                Button {
                    showingAddFinding = true
                } label: {
                    Label("Add Finding", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if model.animalFindings.isEmpty {
                ContentUnavailableView(
                    "No Findings",
                    systemImage: "exclamationmark.bubble",
                    description: Text("Findings for this animal in this check will appear here.")
                )
            } else {
                ForEach(model.animalFindings) { finding in
                    animalFindingRow(finding, allowsEditing: isEditable)
                }
            }
        } header: {
            Text("Findings")
        } footer: {
            Text(isEditable ? "A Missing Animal finding marks this roster entry missing automatically." : "Finding status can still be updated after completion. Reopen the check to update this animal's roster status or add/edit/delete findings.")
        }
    }

    @ViewBuilder
    private func animalFindingRow(_ finding: FieldCheckFindingSnapshot, allowsEditing: Bool) -> some View {
        let row = FieldCheckFindingRow(
            finding: finding,
            showsAnimalDisplayTagNumber: false,
            showsPastureName: true,
            onEdit: allowsEditing ? {
                editingFinding = finding
            } : nil,
            onStatusChange: allowsEditing ? { status in
                Task { @MainActor in
                    await model.updateFindingStatus(
                        animalID: animalID,
                        sessionID: sessionID,
                        findingID: finding.id,
                        status: status,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository,
                        mayContinue: { isPresentingOriginatingHerd }
                    )
                }
            } : nil
        )

        if allowsEditing {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        Task { @MainActor in
                            await model.deleteFinding(
                                animalID: animalID,
                                sessionID: sessionID,
                                findingID: finding.id,
                                animalRepository: animalRepository,
                                fieldCheckRepository: fieldCheckRepository,
                                mayContinue: { isPresentingOriginatingHerd }
                            )
                        }
                    }
                }
        } else {
            row
        }
    }

    private func fieldCheckStatusTitle(for animalCheck: FieldCheckAnimalCheckSnapshot) -> String {
        if animalCheck.isMissing { return "Missing from pasture" }
        if animalCheck.wasCounted { return "Seen in this check" }
        return "Not seen yet"
    }

    private func fieldCheckStatusBadgeTitle(for animalCheck: FieldCheckAnimalCheckSnapshot) -> String {
        if animalCheck.isMissing { return "Missing" }
        if animalCheck.wasCounted { return "Seen" }
        return "Not Seen"
    }

    private func fieldCheckStatusTint(for animalCheck: FieldCheckAnimalCheckSnapshot) -> Color {
        if animalCheck.isMissing { return .orange }
        if animalCheck.wasCounted { return .green }
        return .secondary
    }

    private func statusSummary(for animalCheck: FieldCheckAnimalCheckSnapshot) -> String {
        var parts: [String] = []

        if animalCheck.isMissing {
            parts.append("Needs follow-up")
        } else if animalCheck.wasCounted {
            parts.append("Seen by tag")
        } else {
            parts.append("Still needs verification")
        }

        if animalCheck.needsAttention {
            parts.append("Flagged")
        }

        if !animalCheck.wasExpectedAtStart {
            parts.append("Added")
        }

        parts.append(animalCheck.animalType.label)
        return parts.joined(separator: " • ")
    }
}
