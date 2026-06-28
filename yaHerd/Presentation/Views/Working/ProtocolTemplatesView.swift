//
//  ProtocolTemplatesView.swift
//  yaHerd
//

import SwiftUI

struct ProtocolTemplatesView: View {
    @Environment(\.workingProtocolTemplatesRepository) private var repository
    @StateObject private var viewModel = WorkingProtocolTemplatesViewModel(repository: EmptyWorkingRepository())

    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        List {
            if viewModel.templates.isEmpty {
                ContentUnavailableView(
                    "No protocols",
                    systemImage: "list.bullet",
                    description: Text("Add a protocol template to reuse your predetermined shots.")
                )
            } else {
                ForEach(viewModel.templates) { template in
                    NavigationLink {
                        ProtocolTemplateDetailView(templateID: template.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                            Text("\(template.itemCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Protocols")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            viewModel.configure(repository: repository)
            viewModel.load()
        }
        .onChange(of: showingAdd) { _, isPresented in
            if !isPresented {
                viewModel.load()
            }
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil { showingError = true }
        }
        .sheet(isPresented: $showingAdd) {
            ProtocolTemplateAddView()
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            let useCase = DeleteWorkingProtocolTemplatesUseCase(repository: repository)
            try useCase.execute(offsets.map { viewModel.templates[$0].id })
            viewModel.load()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct ProtocolTemplateAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingProtocolTemplateCreator) private var repository

    @State private var name: String = ""
    @State private var items: [WorkingProtocolItem] = [WorkingProtocolItem(name: "")]
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Protocol name", text: $name)
                }

                Section("Items") {
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
                    .onDelete { idx in items.remove(atOffsets: idx) }

                    Button {
                        items.append(WorkingProtocolItem(name: ""))
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("New Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleaned = items
            .map { WorkingProtocolItem(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), defaultQuantity: $0.defaultQuantity) }
            .filter { !$0.name.isEmpty }
        guard !cleaned.isEmpty else { return }

        do {
            let useCase = CreateWorkingProtocolTemplateUseCase(repository: repository)
            _ = try useCase.execute(name: trimmed, items: cleaned)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct ProtocolTemplateDetailView: View {
    @Environment(\.workingProtocolTemplateEditorRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WorkingProtocolTemplateDetailViewModel

    @State private var nameDraft: String = ""
    @State private var items: [WorkingProtocolItem] = []
    @State private var errorMessage: String?
    @State private var showingError = false

    init(templateID: UUID) {
        _viewModel = StateObject(wrappedValue: WorkingProtocolTemplateDetailViewModel(templateID: templateID, repository: EmptyWorkingRepository()))
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Protocol name", text: $nameDraft)
            }

            Section("Items") {
                if items.isEmpty {
                    Text("No items")
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
                    items.append(WorkingProtocolItem(name: ""))
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .navigationTitle(nameDraft.isEmpty ? "Protocol" : nameDraft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ToolbarSaveButton { save() }
            }
            ToolbarItem(placement: .cancellationAction) {
                ToolbarCancelButton { dismiss() }
            }
        }
        .task {
            viewModel.configure(repository: repository)
            viewModel.load()
            seedFromSnapshot()
        }
        .onChange(of: viewModel.template?.id) { _, _ in
            seedFromSnapshot()
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
    }

    private func seedFromSnapshot() {
        guard let template = viewModel.template else { return }
        nameDraft = template.name
        items = template.items
    }

    private func save() {
        guard let template = viewModel.template else { return }
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let cleaned = items
            .map { WorkingProtocolItem(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), defaultQuantity: $0.defaultQuantity) }
            .filter { !$0.name.isEmpty }
        guard !cleaned.isEmpty else { return }

        do {
            let useCase = UpdateWorkingProtocolTemplateUseCase(repository: repository)
            try useCase.execute(templateID: template.id, name: trimmedName, items: cleaned)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
