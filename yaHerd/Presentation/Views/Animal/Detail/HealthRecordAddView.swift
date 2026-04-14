//
//  HealthRecordAddView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct HealthRecordAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var animal: Animal

    @State private var date = Date()
    @State private var treatment = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

                TextField("Treatment", text: $treatment)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Add Health Record")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(treatment.isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            let repository = SwiftDataAnimalRepository(context: context)
            let useCase = AddHealthRecordUseCase(repository: repository)
            _ = try useCase.execute(
                animalID: animal.publicID,
                date: date,
                treatment: treatment,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
