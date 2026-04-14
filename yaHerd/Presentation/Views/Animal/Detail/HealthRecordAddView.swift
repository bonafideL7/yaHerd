import SwiftUI
import SwiftData

struct HealthRecordAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let animalID: UUID

    @State private var model = HealthRecordAddViewModel()
    @State private var showingError = false

    private var repository: any AnimalRepository {
        SwiftDataAnimalRepository(context: context)
    }

    init(animal: Animal) {
        self.animalID = animal.publicID
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date)

                TextField("Treatment", text: Binding(get: { model.treatment }, set: { model.treatment = $0 }))

                TextField("Notes", text: Binding(get: { model.notes }, set: { model.notes = $0 }), axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Add Health Record")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(animalID: animalID, using: repository) {
                            dismiss()
                        } else {
                            showingError = true
                        }
                    }
                    .disabled(model.isSaveDisabled)
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
    }
}
