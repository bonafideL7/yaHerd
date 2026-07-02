import SwiftUI

struct FieldCheckFindingEditorView: View {
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
        _severity = State(initialValue: FieldCheckFindingRules.defaultSeverity(for: suggestedTypes.first ?? .generalObservation))
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
            
            Section {
                FieldCheckLinkedAnimalSelectorRow(
                    animals: animalOptions,
                    selectedAnimalID: $selectedAnimalID
                )
            } header: {
                Text("Animal")
            } footer: {
                if requiresLinkedAnimal {
                    Text("Select the missing animal so the roster entry is marked missing automatically.")
                } else {
                    Text("Use the linked animal selector when a finding should be tied to a specific roster entry.")
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

}
