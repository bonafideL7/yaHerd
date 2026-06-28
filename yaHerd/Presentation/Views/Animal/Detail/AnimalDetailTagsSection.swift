//
//  AnimalDetailTagsSection.swift
//

import SwiftUI

struct AnimalDetailTagsSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let detail: AnimalDetailSnapshot

    var body: some View {
        Section("Tags") {
            if detail.activeTags.isEmpty {
                Text("No active tags")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.activeTags) { tag in
                    tagRow(for: tag)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
                }
            }

            if !detail.inactiveTags.isEmpty {
                DisclosureGroup("Retired Tags (\(detail.inactiveTags.count))") {
                    ForEach(detail.inactiveTags) { tag in
                        retiredTagRow(for: tag)
                    }
                }
            }
        }
    }

    private func tagRow(for tag: AnimalTagSnapshot) -> some View {
        HStack {
            tagBadge(for: tag)
            Spacer()
            if tag.isPrimary {
                Label("Primary", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func retiredTagRow(for tag: AnimalTagSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            tagBadge(for: tag)
                .opacity(0.65)

            if let removedAt = tag.removedAt {
                Text("Retired \(removedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: definition.color,
            colorName: definition.name,
            size: .compact
        )
    }
}
