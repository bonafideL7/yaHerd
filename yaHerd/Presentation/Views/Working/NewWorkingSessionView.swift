//
//  NewWorkingSessionView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct NewWorkingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Pasture.name) private var pastures: [Pasture]
    @Query(sort: \WorkingProtocolTemplate.name) private var templates: [WorkingProtocolTemplate]

    @State private var date: Date = .now
    @State private var sourcePasture: Pasture?
    @State private var selectedTemplate: WorkingProtocolTemplate?

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
                    Picker("Template", selection: $selectedTemplate) {
                        Text("Custom")
                            .tag(Optional<WorkingProtocolTemplate>(nil))
                        ForEach(templates) { template in
                            Text(template.name)
                                .tag(Optional(template))
                        }
                    }
                    .onChange(of: selectedTemplate) { _, newValue in
                        if let t = newValue {
                            protocolName = t.name
                            items = t.items
                        }
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
                PastureTilePickerView { pasture in
                    sourcePasture = pasture
                }
            }
            .onAppear {
                if selectedTemplate == nil, protocolName.isEmpty {
                    if let first = templates.first {
                        selectedTemplate = first
                        protocolName = first.name
                        items = first.items
                    } else {
                        protocolName = "Working"
                        items = [WorkingProtocolItem(name: "7-way")]
                    }
                }
            }
            .alert("Can’t Create", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
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
            let repository = SwiftDataWorkingRepository(context: context)
            let useCase = CreateWorkingSessionUseCase(repository: repository)
            _ = try useCase.execute(
                date: date,
                sourcePasture: sourcePasture,
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
