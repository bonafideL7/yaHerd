//
//  AddPastureGroupView.swift
//  yaHerd
//
//  Created by mm on 12/14/25.
//


import SwiftUI

struct AddPastureGroupView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var grazeDays = 7
    @State private var restDays = 21
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group Name", text: $name)
                
                Stepper("Graze Days: \(grazeDays)", value: $grazeDays, in: 1...30)
                Stepper("Rest Days: \(restDays)", value: $restDays, in: 7...90)
            }
            .navigationTitle("New Pasture Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Unable to Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            let useCase = CreatePastureGroupUseCase(repository: dependencies.pastureRepository)
            try useCase.execute(name: name, grazeDays: grazeDays, restDays: restDays)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
