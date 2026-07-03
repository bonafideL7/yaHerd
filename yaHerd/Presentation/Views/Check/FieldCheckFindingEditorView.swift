import SwiftUI

struct FieldCheckFindingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let suggestedTypes: [FieldCheckFindingType]
    let animals: [FieldCheckAnimalCheckSnapshot]
    let finding: FieldCheckFindingSnapshot?
    let onSave: (FieldCheckFindingInput) -> Void

    @State private var recordedAt: Date
    @State private var type: FieldCheckFindingType
    @State private var severity: FieldCheckFindingSeverity
    @State private var status: FieldCheckFindingStatus
    @State private var note: String
    @State private var selectedAnimalID: UUID?

    init(
        suggestedTypes: [FieldCheckFindingType],
        animals: [FieldCheckAnimalCheckSnapshot],
        finding: FieldCheckFindingSnapshot? = nil,
        initialType: FieldCheckFindingType? = nil,
        initialAnimalID: UUID? = nil,
        onSave: @escaping (FieldCheckFindingInput) -> Void
    ) {
        self.suggestedTypes = suggestedTypes
        self.animals = animals
        self.finding = finding
        self.onSave = onSave

        let resolvedType = finding?.type ?? initialType ?? suggestedTypes.first ?? .generalObservation
        _recordedAt = State(initialValue: finding?.recordedAt ?? .now)
        _type = State(initialValue: resolvedType)
        _severity = State(initialValue: finding?.severity ?? FieldCheckFindingRules.defaultSeverity(for: resolvedType))
        _status = State(initialValue: finding?.status ?? .open)
        _note = State(initialValue: finding?.note ?? "")
        _selectedAnimalID = State(initialValue: finding?.animalID ?? initialAnimalID)
    }

    private var animalOptions: [FieldCheckAnimalCheckSnapshot] {
        animals
            .filter { $0.animalID != nil }
            .sorted { left, right in
                let leftKey = animalSortKey(for: left)
                let rightKey = animalSortKey(for: right)
                return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
            }
    }

    private var navigationTitle: String {
        finding == nil ? "Add Finding" : "Edit Finding"
    }

    private func animalSortKey(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            animal.displayTagNumber,
            trimmedName,
            animal.animalType.label,
            animal.animalSex.label
        ]
        .joined(separator: " ")
    }

    private var requiresLinkedAnimal: Bool {
        FieldCheckFindingRules.shouldMarkAnimalMissing(for: type)
    }

    private var canSave: Bool {
        !requiresLinkedAnimal || selectedAnimalID != nil
    }

    private var selectedAnimal: FieldCheckAnimalCheckSnapshot? {
        guard let selectedAnimalID else { return nil }
        return animalOptions.first { $0.animalID == selectedAnimalID }
    }

    private var selectedAnimalSummary: String {
        guard let selectedAnimal else { return "None" }

        let trimmedName = selectedAnimal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty
            ? selectedAnimal.displayTagNumber
            : "\(selectedAnimal.displayTagNumber) • \(trimmedName)"
        return "\(title) • \(selectedAnimal.animalType.label)"
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

            animalLinkSection

            if requiresLinkedAnimal && selectedAnimalID == nil {
                missingAnimalWarningSection
            }

            Section("Notes") {
                TextField("Notes", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ToolbarCancelButton { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                ToolbarSaveButton {
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
                .disabled(!canSave)
            }
        }
        .onChange(of: type) { _, newType in
            severity = FieldCheckFindingRules.defaultSeverity(for: newType)
        }
    }

    private var animalLinkSection: some View {
        Section {
            FieldCheckLinkedAnimalSelectorRow(
                animals: animalOptions,
                selectedAnimalID: $selectedAnimalID,
                allowsNone: !requiresLinkedAnimal
            )

            LabeledContent("Selected") {
                Text(selectedAnimalSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text("Animal")
        } footer: {
            if requiresLinkedAnimal {
                Text("A Missing Animal finding must be linked to a roster animal. Saving will mark that animal missing in this check.")
            } else {
                Text("Link an animal only when this finding belongs to a specific roster entry.")
            }
        }
    }

    private var missingAnimalWarningSection: some View {
        Section {
            Label {
                Text("Select the missing animal before saving.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }
}
