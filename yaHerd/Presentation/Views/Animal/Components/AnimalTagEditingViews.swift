//
//  AnimalTagEditingViews.swift
//

import SwiftUI

struct AnimalTagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    @State private var number: String
    @State private var colorID: UUID?
    @State private var isPrimary: Bool
    
    private let title: String
    private let saveButtonTitle: String
    private let showsPrimaryToggle: Bool
    private let onSave: (String, UUID?, Bool) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    
    init(
        initialNumber: String = "",
        initialColorID: UUID? = nil,
        initialIsPrimary: Bool = false,
        title: String = "Add Tag",
        saveButtonTitle: String = "Save",
        showsPrimaryToggle: Bool = false,
        onSave: @escaping (String, UUID?, Bool) -> Void
    ) {
        _number = State(initialValue: initialNumber)
        _colorID = State(initialValue: initialColorID)
        _isPrimary = State(initialValue: initialIsPrimary)
        self.title = title
        self.saveButtonTitle = saveButtonTitle
        self.showsPrimaryToggle = showsPrimaryToggle
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Number") {
                    TextField("Number", text: $number)
                        .keyboardType(.numberPad)
                        .font(.title2)
                }
                
                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tagColorLibrary.colors) { def in
                            let isSelected = def.id == colorID
                            
                            Circle()
                                .fill(def.color)
                                .frame(height: 44)
                                .overlay {
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 3)
                                    }
                                }
                                .onTapGesture {
                                    colorID = def.id
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button("Clear Color") {
                        colorID = nil
                    }
                    .foregroundStyle(.secondary)
                }
                
                if showsPrimaryToggle {
                    Section {
                        Toggle("Use as primary tag", isOn: $isPrimary)
                    } footer: {
                        Text("Primary tags become the animal's display tag.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        onSave(number.trimmingCharacters(in: .whitespacesAndNewlines), colorID, isPrimary)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AnimalTagManagementActions {
    let onEdit: (AnimalTagSnapshot) -> Void
    let onPromote: (UUID) -> Void
    let onRetire: (UUID) -> Void
}

struct AnimalTagManagementSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    let detail: AnimalDetailSnapshot
    let actions: AnimalTagManagementActions
    let onAddTag: () -> Void
    
    var body: some View {
        Section {
            ForEach(detail.activeTags) { tag in
                activeTagRow(for: tag)
            }
            
            if !detail.inactiveTags.isEmpty {
                DisclosureGroup("Retired Tags (\(detail.inactiveTags.count))") {
                    ForEach(detail.inactiveTags) { tag in
                        inactiveTagRow(for: tag)
                    }
                }
            }
            
            Button {
                onAddTag()
            } label: {
                HStack {
                    Text("Add Tag")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tap a tag to edit it, swipe right to promote an active tag to primary, or swipe left to retire a tag.")
        }
    }
    
    private func activeTagRow(for tag: AnimalTagSnapshot) -> some View {
        Button {
            actions.onEdit(tag)
        } label: {
            HStack {
                tagBadge(for: tag)
                Spacer()
                if tag.isPrimary {
                    Label("Primary", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !tag.isPrimary {
                Button {
                    actions.onPromote(tag.id)
                } label: {
                    Label("Make Primary", systemImage: "star")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                actions.onRetire(tag.id)
            } label: {
                Label("Retire", systemImage: "archivebox")
            }
        }
    }
    
    private func inactiveTagRow(for tag: AnimalTagSnapshot) -> some View {
        Button {
            actions.onEdit(tag)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                tagBadge(for: tag)
                    .opacity(0.65)
                
                if let removedAt = tag.removedAt {
                    Text("Retired \(removedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
    }
}


struct DraftAnimalTagManagementSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Binding var draftTags: [AnimalTagSnapshot]

    let actions: AnimalTagManagementActions
    let onAddTag: () -> Void

    private var activeTags: [AnimalTagSnapshot] {
        draftTags.filter(\.isActive)
    }

    private var inactiveTags: [AnimalTagSnapshot] {
        draftTags.filter { !$0.isActive }
    }

    var body: some View {
        Section {
            ForEach(activeTags) { tag in
                activeTagRow(for: tag)
            }

            if !inactiveTags.isEmpty {
                DisclosureGroup("Retired Tags (\(inactiveTags.count))") {
                    ForEach(inactiveTags) { tag in
                        inactiveTagRow(for: tag)
                    }
                }
            }

            Button {
                onAddTag()
            } label: {
                HStack {
                    Text("Add Tag")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tap a tag to edit it, swipe right to promote an active tag to primary, or swipe left to retire a tag.")
        }
    }

    private func activeTagRow(for tag: AnimalTagSnapshot) -> some View {
        Button {
            actions.onEdit(tag)
        } label: {
            HStack {
                tagBadge(for: tag)
                Spacer()
                if tag.isPrimary {
                    Label("Primary", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !tag.isPrimary {
                Button {
                    actions.onPromote(tag.id)
                } label: {
                    Label("Make Primary", systemImage: "star")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                actions.onRetire(tag.id)
            } label: {
                Label("Retire", systemImage: "archivebox")
            }
        }
    }

    private func inactiveTagRow(for tag: AnimalTagSnapshot) -> some View {
        Button {
            actions.onEdit(tag)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                tagBadge(for: tag)
                    .opacity(0.65)

                if let removedAt = tag.removedAt {
                    Text("Retired \(removedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
    }
}

struct PendingAnimalTagManagementSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?
    @Binding var pendingTags: [AnimalTagSnapshot]
    
    let onAddTag: () -> Void
    let onEditTag: (AnimalTagSnapshot) -> Void
    
    var body: some View {
        Section {
            ForEach(pendingTags) { tag in
                Button {
                    onEditTag(tag)
                } label: {
                    HStack(spacing: 12) {
                        tagBadge(for: tag)
                        Spacer()
                        if tag.isPrimary {
                            Label("Primary", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !tag.isPrimary {
                        Button {
                            makePrimary(tag.id)
                        } label: {
                            Label("Make Primary", systemImage: "star")
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTag(tag.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            
            Button {
                onAddTag()
            } label: {
                HStack {
                    Text("Add Tag")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tap a tag to edit it, swipe right to promote a pending tag to primary, or swipe left to remove it.")
        }
    }
    
    private func makePrimary(_ tagID: UUID) {
        pendingTags = pendingTags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.number,
                colorID: tag.colorID,
                isPrimary: tag.id == tagID,
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }
        
        syncPrimaryTag()
    }
    
    private func deleteTag(_ tagID: UUID) {
        pendingTags.removeAll { $0.id == tagID }
        
        if !pendingTags.contains(where: { $0.isPrimary }), let firstID = pendingTags.first?.id {
            makePrimary(firstID)
        } else {
            syncPrimaryTag()
        }
    }
    
    private func syncPrimaryTag() {
        if let primary = pendingTags.first(where: { $0.isPrimary }) {
            tagNumber = primary.normalizedNumber
            tagColorID = primary.colorID
        } else {
            tagNumber = ""
            tagColorID = nil
        }
    }
    
    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
    }
}
