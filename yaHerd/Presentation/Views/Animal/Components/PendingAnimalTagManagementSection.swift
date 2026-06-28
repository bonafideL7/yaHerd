//
//  PendingAnimalTagManagementSection.swift
//

import SwiftUI

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
            tagColorID = tagColorLibrary.resolvedColorID(primary.colorID)
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
