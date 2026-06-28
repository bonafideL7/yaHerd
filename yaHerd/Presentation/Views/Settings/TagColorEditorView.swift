//
//  TagColorEditorView.swift
//  yaHerd
//

import SwiftUI

struct TagColorEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let existing: TagColorSnapshot?

    @State private var name: String
    @State private var prefix: String
    @State private var color: Color
    @State private var prefixEdited = false

    init(existing: TagColorSnapshot?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _prefix = State(initialValue: existing?.prefix ?? "")
        _color = State(initialValue: existing?.color ?? .yellow)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, newValue in
                            guard !prefixEdited else { return }
                            prefix = TagColorLibraryStore.defaultPrefix(for: newValue)
                        }

                    TextField("Prefix", text: $prefix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: prefix) { _, _ in
                            prefixEdited = true
                            prefix = prefix.uppercased()
                        }

                    ColorPicker("Color", selection: $color, supportsOpacity: true)
                }

                Section("Preview") {
                    let computedPrefix: String = {
                        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedPrefix.isEmpty {
                            return TagColorLibraryStore.defaultPrefix(for: name)
                        }
                        return trimmedPrefix.uppercased()
                    }()

                    HStack(spacing: 10) {
                        TagColorTagIcon(color: color, accessibilityLabel: "Tag color preview")
                        Text("\(computedPrefix)09")
                            .font(.headline)
                    }
                }

                if let existing {
                    Section {
                        if existing.isDefault {
                            Label("Default tag color", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                tagColorLibrary.setDefaultColor(id: existing.id)
                            } label: {
                                Label("Set as Default Tag Color", systemImage: "checkmark.circle")
                            }
                        }
                    } footer: {
                        Text("New tags use the default color unless another color is selected.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Color" : "Edit Color")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }

                        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalPrefix = trimmedPrefix.isEmpty
                            ? TagColorLibraryStore.defaultPrefix(for: trimmedName)
                            : trimmedPrefix.uppercased()

                        let def = TagColorSnapshot(
                            id: existing?.id ?? UUID(),
                            name: trimmedName,
                            prefix: finalPrefix,
                            rgba: RGBAColor(color: color)
                        )

                        tagColorLibrary.upsert(def)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
