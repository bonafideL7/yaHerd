//
//  TagColorEditorView.swift
//  yaHerd
//

import SwiftUI

struct TagColorEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationState.self) private var navigation
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let existing: TagColorSnapshot?
    let originatingSelection: TagColorSettingsMutationGuard?

    @State private var name: String
    @State private var prefix: String
    @State private var color: Color
    @State private var prefixEdited = false
    @State private var saveErrorMessage: String?

    init(existing: TagColorSnapshot?, originatingSelection: TagColorSettingsMutationGuard?) {
        self.existing = existing
        self.originatingSelection = originatingSelection
        _name = State(initialValue: existing?.name ?? "")
        _prefix = State(initialValue: existing?.prefix ?? "")
        _color = State(initialValue: existing?.color ?? .yellow)
    }

    private var isCurrentSelection: Bool {
        originatingSelection?.isCurrent(in: herdSelection) == true
    }

    private var staleSelectionMessage: String {
        "The selected Herd changed. Reopen Tag Colors before making changes."
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
                        if tagColorLibrary.colors.contains(where: { $0.id == existing.id && $0.isDefault }) {
                            Label("Current Default Tag Color", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityAddTraits(.isSelected)
                        } else {
                            Button {
                                guard let didSave = originatingSelection?.performIfCurrent(
                                    in: herdSelection,
                                    { tagColorLibrary.setDefaultColor(id: existing.id) }
                                ) else {
                                    saveErrorMessage = staleSelectionMessage
                                    return
                                }
                                guard didSave else {
                                    saveErrorMessage = tagColorLibrary.lastErrorMessage
                                        ?? "The default tag color could not be updated."
                                    return
                                }
                            } label: {
                                Label("Set as Default Tag Color", systemImage: "checkmark.circle")
                            }
                            .disabled(!isCurrentSelection)
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
                        guard isCurrentSelection else {
                            saveErrorMessage = staleSelectionMessage
                            return
                        }
                        if let existing {
                            do {
                                guard let current = try tagColorLibrary.readCurrentDefinition(id: existing.id),
                                      current.name == existing.name,
                                      current.prefix == existing.prefix,
                                      current.rgba == existing.rgba else {
                                    saveErrorMessage = "This tag color changed or was removed. Your draft is retained; reopen it before saving."
                                    return
                                }
                            } catch {
                                saveErrorMessage = UserVisibleErrorMessage.make(error)
                                return
                            }
                        }
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

                        guard let didSave = originatingSelection?.performIfCurrent(
                            in: herdSelection,
                            { tagColorLibrary.upsert(def) }
                        ) else {
                            saveErrorMessage = staleSelectionMessage
                            return
                        }
                        guard didSave else {
                            saveErrorMessage = tagColorLibrary.lastErrorMessage
                                ?? "The tag color could not be saved."
                            return
                        }

                        if navigation.presentedSheet == .settings {
                            navigation.dismissSheet()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(!isCurrentSelection || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                "Unable to Save Tag Color",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }
}
