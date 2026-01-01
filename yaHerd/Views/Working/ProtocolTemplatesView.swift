//
//  ProtocolTemplatesView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct ProtocolTemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkingProtocolTemplate.name) private var templates: [WorkingProtocolTemplate]
    @State private var showingAdd = false

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No protocols",
                    systemImage: "list.bullet",
                    description: Text("Add a protocol template to reuse your predetermined shots.")
                )
            } else {
                ForEach(templates) { template in
                    NavigationLink(value: template) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                            Text("\(template.items.count) items")
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
        .navigationDestination(for: WorkingProtocolTemplate.self) { template in
            ProtocolTemplateDetailView(template: template)
        }
        .sheet(isPresented: $showingAdd) {
            ProtocolTemplateAddView()
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            context.delete(templates[i])
        }
        try? context.save()
    }
}

private struct ProtocolTemplateAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String = ""
    @State private var items: [WorkingProtocolItem] = [WorkingProtocolItem(name: "")]

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
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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

        let template = WorkingProtocolTemplate(name: trimmed, items: cleaned)
        context.insert(template)
        try? context.save()
        dismiss()
    }
}

private struct ProtocolTemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: WorkingProtocolTemplate

    @State private var items: [WorkingProtocolItem] = []

    var body: some View {
        Form {
            Section("Name") {
                TextField("Protocol name", text: $template.name)
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
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            items = template.items
        }
    }

    private func save() {
        let cleaned = items
            .map { WorkingProtocolItem(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), defaultQuantity: $0.defaultQuantity) }
            .filter { !$0.name.isEmpty }
        template.items = cleaned
        try? context.save()
    }
}
