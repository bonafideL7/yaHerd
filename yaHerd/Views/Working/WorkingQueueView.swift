//
//  WorkingQueueView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingQueueView: View {
    @Bindable var session: WorkingSession

    private var orderedItems: [WorkingQueueItem] {
        session.queueItems.sorted { $0.queueOrder < $1.queueOrder }
    }

    var body: some View {
        List {
            Section {
                ForEach(orderedItems) { item in
                    NavigationLink {
                        WorkingChuteView(session: session, queueItem: item)
                    } label: {
                        WorkingQueueRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkingQueueRow: View {
    let item: WorkingQueueItem

    private var animal: Animal? { item.animal }

    private var statusIcon: String {
        switch item.status {
        case .queued: return "circle"
        case .inProgress: return "circle.dashed"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(item.status == .done ? .green : item.status == .skipped ? .orange : .secondary)

            if let animal {
                TagColorDot(tagColor: animal.tagColor ?? .yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tag \(animal.tagNumber)")
                        .font(.headline)
                    Text(animal.designation.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Missing animal")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}