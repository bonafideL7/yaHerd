import SwiftUI

struct PregnancyCheckAddView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animalID: UUID

    @State private var model = PregnancyCheckAddViewModel()
    @State private var showingSirePicker = false
    @State private var showingError = false

    private var repository: any AnimalRepository {
        dependencies.animalRepository
    }

    init(animalID: UUID) {
        self.animalID = animalID
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Check Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date)

                Picker("Result", selection: Binding(get: { model.result }, set: { model.result = $0 })) {
                    ForEach(PregnancyResult.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized)
                    }
                }

                TextField("Technician", text: Binding(get: { model.technician }, set: { model.technician = $0 }))

                if model.result == .pregnant {
                    HStack {
                        Text("Est. days")
                        Spacer()
                        TextField("", text: Binding(get: { model.estimatedDaysText }, set: { model.estimatedDaysText = $0 }))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 120)
                    }

                    DatePicker("Due Date", selection: Binding(get: { model.dueDate }, set: { model.dueDate = $0 }), displayedComponents: .date)

                    Button {
                        showingSirePicker = true
                    } label: {
                        HStack {
                            Text("Sire")
                            Spacer()
                            if let selectedSire = model.selectedSire {
                                let def = tagColorLibrary.resolvedDefinition(tagColorID: selectedSire.displayTagColorID)
                                AnimalTagView(
                                    tagNumber: selectedSire.displayTagNumber,
                                    color: def.color,
                                    colorName: def.name,
                                    size: .compact
                                )
                            } else {
                                Text("Choose")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Pregnancy Check")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(animalID: animalID, using: repository) {
                            dismiss()
                        } else {
                            showingError = true
                        }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .onChange(of: model.estimatedDaysText) { _, _ in
            model.recalcDueDate()
        }
        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeAnimalID: animalID,
                suggestedSexes: [.male]
            ) { picked in
                model.selectedSire = picked
            }
        }
    }
}
