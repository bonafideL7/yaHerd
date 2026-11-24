//
//  TagColorLibraryView.swift
//  yaHerd
//

import SwiftUI

/// An open settings screen belongs to one selection incarnation, not merely a
/// Herd UUID. Returning to the same Herd cannot revive controls from that screen.
@MainActor
struct TagColorSettingsMutationGuard {
    let herdID: UUID
    let selectionRevision: UInt64

    init?(selection: AppCurrentHerdSelection) {
        guard let herdID = selection.currentHerdID else { return nil }
        self.herdID = herdID
        self.selectionRevision = selection.selectionRevision
    }

    func isCurrent(in selection: AppCurrentHerdSelection) -> Bool {
        herdID == selection.currentHerdID
            && selectionRevision == selection.selectionRevision
    }

    func performIfCurrent<Result>(
        in selection: AppCurrentHerdSelection,
        _ mutation: () -> Result
    ) -> Result? {
        guard isCurrent(in: selection) else { return nil }
        return mutation()
    }
}

struct TagColorLibraryView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    @State private var showingAdd = false
    @State private var editingColor: TagColorSnapshot?
    @State private var originatingSelection: TagColorSettingsMutationGuard?
    @State private var hasCapturedOpeningSelection = false

    private var isCurrentSelection: Bool {
        originatingSelection?.isCurrent(in: herdSelection) == true
    }

    var body: some View {
        List {
            Section {
                ForEach(tagColorLibrary.colors) { def in
                    Button {
                        guard isCurrentSelection else { return }
                        editingColor = def
                    } label: {
                        HStack(spacing: 12) {
                            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(def.name)

                                    if def.isDefault {
                                        Label("Default", systemImage: "checkmark.circle.fill")
                                            .labelStyle(.titleAndIcon)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(def.prefix)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(def.prefix)01")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !def.isDefault {
                            Button {
                                performMutation {
                                    _ = tagColorLibrary.setDefaultColor(id: def.id)
                                }
                            } label: {
                                Label("Set Default", systemImage: "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if !def.isDefault {
                            Button {
                                performMutation {
                                    _ = tagColorLibrary.setDefaultColor(id: def.id)
                                }
                            } label: {
                                Label("Set as Default", systemImage: "checkmark.circle")
                            }
                        }

                        Button {
                            guard isCurrentSelection else { return }
                            editingColor = def
                        } label: {
                            Label("Edit Color", systemImage: "pencil")
                        }
                    }
                    .disabledWhenDataReadOnly()
                    .disabled(!isCurrentSelection)
                }
                .onDelete { offsets in
                    performMutation {
                        tagColorLibrary.delete(at: offsets)
                    }
                }
                .onMove { source, destination in
                    performMutation {
                        tagColorLibrary.move(from: source, to: destination)
                    }
                }
            } footer: {
                Text("The default color is used for new tags and for legacy tags that do not have a stored color.")
            }
        }
        .navigationTitle("Tag Colors")
        .settingsSaveAndCloseToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .disabledWhenDataReadOnly()
                    .disabled(!isCurrentSelection)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        guard isCurrentSelection else { return }
                        showingAdd = true
                    } label: {
                        Label("Add Color", systemImage: "plus")
                    }

                    Button {
                        performMutation {
                            tagColorLibrary.restoreDefaultColors()
                        }
                    } label: {
                        Label("Restore Default Colors", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabledWhenDataReadOnly()
                .disabled(!isCurrentSelection)
            }
        }
        .sheet(isPresented: $showingAdd) {
            TagColorEditorView(existing: nil, originatingSelection: originatingSelection)
        }
        .sheet(item: $editingColor) { def in
            TagColorEditorView(existing: def, originatingSelection: originatingSelection)
        }
        .task {
            guard !hasCapturedOpeningSelection else { return }
            hasCapturedOpeningSelection = true
            originatingSelection = TagColorSettingsMutationGuard(selection: herdSelection)
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            // Never present an old-Herd editor after a selection transition.
            showingAdd = false
            editingColor = nil
        }
    }

    private func performMutation(_ mutation: () -> Void) {
        _ = originatingSelection?.performIfCurrent(in: herdSelection, mutation)
    }
}
