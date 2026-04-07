//
//  WorkingSessionAnimalsView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

/// Review and edit per-animal work data captured in a session.
struct WorkingSessionAnimalsView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Bindable var session: WorkingSession

    private var orderedItems: [WorkingQueueItem] {
        session.queueItems.sorted { $0.queueOrder < $1.queueOrder }
    }

    var body: some View {
        List {
            if orderedItems.isEmpty {
                ContentUnavailableView(
                    "No animals",
                    systemImage: "list.bullet",
                    description: Text("Collect animals into the working pen to start a queue.")
                )
            } else {
                ForEach(orderedItems) { item in
                    NavigationLink {
                        WorkingSessionAnimalEditView(session: session, queueItem: item)
                    } label: {
                        row(for: item)
                    }
                }
            }
        }
        .navigationTitle("Animals")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for item: WorkingQueueItem) -> some View {
        if let animal = item.animal {
            HStack(spacing: 12) {
                let def = tagColorLibrary.resolvedDefinition(for: animal)
                VStack(alignment: .leading, spacing: 6) {
                    AnimalTagView(
                        tagNumber: animal.tagNumber,
                        color: def.color,
                        colorName: def.name
                    )
                    Text(item.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if item.status == .skipped {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Missing animal")
                .foregroundStyle(.secondary)
        }
    }
}
