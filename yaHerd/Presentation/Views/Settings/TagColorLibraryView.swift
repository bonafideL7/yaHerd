//
//  TagColorLibraryView.swift
//  yaHerd
//

import SwiftUI

struct TagColorLibraryView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var showingAdd = false
    @State private var editingColor: TagColorDefinition?

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
                                Text(def.name)
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
                }
                .onDelete(perform: tagColorLibrary.delete)
                .onMove(perform: tagColorLibrary.move)
            }
        }
        .navigationTitle("Tag Colors")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
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
