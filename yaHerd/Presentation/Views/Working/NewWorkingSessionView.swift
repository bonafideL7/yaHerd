//
//  NewWorkingSessionView.swift
//  yaHerd
//

import SwiftUI

struct NewWorkingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

    @StateObject private var viewModel = NewWorkingSessionViewModel(animalRepository: EmptyAnimalRepository(), workingRepository: EmptyWorkingRepository())

    @State private var date: Date = .now
    @State private var sourcePasture: PastureOption?
    @State private var selectedTemplateID: UUID?

    @State private var protocolName: String = ""
    @State private var items: [WorkingProtocolItem] = []

    @State private var showingPasturePicker = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Date", selection: $date)

                    Button {
                        showingPasturePicker = true
                    } label: {
                        HStack {
                            Text("Source Pasture")
                            Spacer()
                            Text(sourcePasture?.name ?? "Choose")
                                .foregroundStyle(sourcePasture == nil ? .secondary : .primary)
                        }
                    }
                }

                Section("Protocol") {
                    Picker("Template", selection: $selectedTemplateID) {
                        Text("Custom")
                            .tag(Optional<UUID>(nil))
                        ForEach(viewModel.templates) { template in
                            Text(template.name)
                                .tag(Optional(template.id))
                        }
                    }
                    .onChange(of: selectedTemplateID) { _, newValue in
                        guard let id = newValue,
                              let template = viewModel.templateDetail(id: id) else { return }
                        protocolName = template.name
                        items = template.items
                    }

                    TextField("Protocol Name", text: $protocolName)

                    if items.isEmpty {
                        Text("No protocol items")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($items) { $item in
                            HStack {
                                TextField("Item", text: $item.name)
                                Spacer()
                                TextField("Qty", value: $item.defaultQuantity, format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 90)
                            }
                        }
                        .onDelete { idx in
                            items.remove(atOffsets: idx)
                        }
                    }

                    Button {
                        items.append(WorkingProtocolItem(name: "", defaultQuantity: nil))
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSession()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPasturePicker) {
                NavigationStack {
                    List(viewModel.pastures) { pasture in
                        Button {
                            sourcePasture = pasture
                            showingPasturePicker = false
                        } label: {
                            HStack {
                                Text(pasture.name)
                                Spacer()
                                if sourcePasture?.id == pasture.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .navigationTitle("Choose Pasture")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task {
                viewModel.configure(animalRepository: dependencies.animalRepository, workingRepository: dependencies.workingRepository)
                viewModel.load()
                seedDefaultsIfNeeded()
            }
            .alert("Can’t Create", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if newValue != nil { showingError = true }
            }
        }
    }

    private func seedDefaultsIfNeeded() {
        guard protocolName.isEmpty else { return }
        if let first = viewModel.templates.first,
           let detail = viewModel.templateDetail(id: first.id) {
            selectedTemplateID = first.id
            protocolName = detail.name
            items = detail.items
        } else {
            protocolName = "Working"
            items = [WorkingProtocolItem(name: "7-way")]
        }
    }

    private func createSession() {
        let trimmedName = protocolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Protocol name can’t be empty."
            showingError = true
            return
        }

        let cleanedItems = items
            .map { WorkingProtocolItem(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), defaultQuantity: $0.defaultQuantity) }
            .filter { !$0.name.isEmpty }

        guard !cleanedItems.isEmpty else {
            errorMessage = "Add at least one protocol item."
            showingError = true
            return
        }

        do {
            let useCase = CreateWorkingSessionUseCase(repository: dependencies.workingRepository)
            _ = try useCase.execute(
                date: date,
                sourcePastureID: sourcePasture?.id,
                protocolName: trimmedName,
                protocolItems: cleanedItems
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
