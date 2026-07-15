import SwiftUI

struct FieldCheckAnimalDetailView: View {
    @Environment(\.animalDetailRepository) private var animalRepository
    @Environment(\.fieldCheckAnimalDetailRepository) private var fieldCheckRepository
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appDataAccessMode) private var dataAccessMode

    @State private var model = FieldCheckAnimalDetailViewModel()
    @State private var isLineageExpanded = false
    @State private var showingAddOffspring = false
    @State private var showingAddFinding = false
    @State private var editingFinding: FieldCheckFindingSnapshot?

    let sessionID: UUID
    let animalID: UUID

    private var displayedTagNumber: String {
        model.animalDetail?.displayTagNumber ?? ""
    }

    private var displayedTagColorID: UUID? {
        model.animalDetail?.displayTagColorID
    }

    private var isSessionEditable: Bool {
        dataAccessMode.allowsDataMutations && model.sessionDetail?.isCompleted == false
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
            if let detail = model.animalDetail {
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
            model.refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }) {
            if let preparedEditor = model.preparedOffspringEditor {
                AddAnimalView(
                    title: "Add Offspring",
                    initialDraft: preparedEditor.draft,
                    editorContext: preparedEditor.context
                ) { createdAnimal in
                    try model.addTrackedAnimalToSession(
                        animalID: createdAnimal.id,
                        sessionID: sessionID,
                        fieldCheckRepository: fieldCheckRepository
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddFinding) {
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: [.pinkEye, .limping, .missingAnimal],
                    animals: model.sessionDetail?.animalChecks ?? [],
                    initialAnimalID: animalID
                ) { input in
                    guard isSessionEditable else { return }
                    model.addFinding(
                        animalID: animalID,
                        sessionID: sessionID,
                        input: input,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository
                    )
                }
            }
        }
        .sheet(item: $editingFinding) { finding in
            NavigationStack {
                FieldCheckFindingEditorView(
                    suggestedTypes: [.pinkEye, .limping, .missingAnimal],
                    animals: model.sessionDetail?.animalChecks ?? [],
                    finding: finding
                ) { input in
                    guard isSessionEditable else { return }
                    model.updateFinding(
                        animalID: animalID,
                        sessionID: sessionID,
                        findingID: finding.id,
                        input: input,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository
                    )
                }
            }
        }
        .refreshable {
            model.refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }
        .task {
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
                model.setAnimalCheckCounted(
                    animalID: animalID,
                    sessionID: sessionID,
                    isCounted: true,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
            } label: {
                Label("Mark Found", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
        } else if animalCheck.wasCounted {
            Button {
                model.setAnimalCheckCounted(
                    animalID: animalID,
                    sessionID: sessionID,
                    isCounted: false,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
            } label: {
                Label("Mark Not Seen", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            HStack(spacing: 10) {
                Button {
                    model.setAnimalCheckCounted(
                        animalID: animalID,
                        sessionID: sessionID,
                        isCounted: true,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository
                    )
                } label: {
                    Label("Mark Seen", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(colorScheme == .dark ? .black : .white)

                Button {
                    model.setAnimalCheckMissing(
                        animalID: animalID,
                        sessionID: sessionID,
                        isMissing: true,
                        animalRepository: animalRepository,
                        fieldCheckRepository: fieldCheckRepository
                    )
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
                model.updateFindingStatus(
                    animalID: animalID,
                    sessionID: sessionID,
                    findingID: finding.id,
                    status: status,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
            } : nil
        )

        if allowsEditing {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        model.deleteFinding(
                            animalID: animalID,
                            sessionID: sessionID,
                            findingID: finding.id,
                            animalRepository: animalRepository,
                            fieldCheckRepository: fieldCheckRepository
                        )
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
