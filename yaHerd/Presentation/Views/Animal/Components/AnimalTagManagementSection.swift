//
//  AnimalTagManagementSection.swift
//

import SwiftUI

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
