import SwiftUI
import SwiftData

struct PasturePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    let animalID: UUID
    let currentPastureID: UUID?

    @State private var model = PastureChangeViewModel()
    @State private var showingError = false

    private var repository: any AnimalRepository {
        SwiftDataAnimalRepository(context: context)
    }

    init(animal: Animal) {
        self.animalID = animal.publicID
        self.currentPastureID = animal.pasture?.publicID
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Assign Pasture") {
                    Picker(
                        "Pasture",
                        selection: Binding(
                            get: { model.selectedPastureID },
                            set: { model.selectedPastureID = $0 }
                        )
                    ) {
                        Text("None")
                            .tag(UUID?.none)

                        ForEach(pastures) { pasture in
                            Text(pasture.name)
                                .tag(Optional(pasture.publicID))
                        }
                    }
                }
            }
            .navigationTitle("Change Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.moveAnimal(animalID: animalID, using: repository) {
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
            .task {
                model.selectedPastureID = currentPastureID
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
