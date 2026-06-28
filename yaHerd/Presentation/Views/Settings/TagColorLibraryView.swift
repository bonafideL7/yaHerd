//
//  TagColorLibraryView.swift
//  yaHerd
//

import SwiftUI

struct TagColorLibraryView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var showingAdd = false
    @State private var editingColor: TagColorSnapshot?

    var body: some View {
        List {
            Section {
                ForEach(tagColorLibrary.colors) { def in
                    Button {
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
                                tagColorLibrary.setDefaultColor(id: def.id)
                            } label: {
                                Label("Set Default", systemImage: "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if !def.isDefault {
                            Button {
                                tagColorLibrary.setDefaultColor(id: def.id)
                            } label: {
                                Label("Set as Default", systemImage: "checkmark.circle")
                            }
                        }

                        Button {
                            editingColor = def
                        } label: {
                            Label("Edit Color", systemImage: "pencil")
                        }
                    }
                }
                .onDelete(perform: tagColorLibrary.delete)
                .onMove(perform: tagColorLibrary.move)
            } footer: {
                Text("The default color is used for new tags and for legacy tags that do not have a stored color.")
            }
        }
        .navigationTitle("Tag Colors")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Color", systemImage: "plus")
                    }

                    Button {
                        tagColorLibrary.restoreDefaultColors()
                    } label: {
                        Label("Restore Default Colors", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            TagColorEditorView(existing: nil)
        }
        .sheet(item: $editingColor) { def in
            TagColorEditorView(existing: def)
        }
    }
}
