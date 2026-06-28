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
            }
        }
    }
}
