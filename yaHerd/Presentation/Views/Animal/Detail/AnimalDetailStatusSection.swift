//
//  AnimalDetailStatusSection.swift
//

import SwiftUI

struct AnimalDetailStatusSection: View {
    let detail: AnimalDetailSnapshot
    let onBeginEditingStatus: (AnimalStatus) -> Void

    var body: some View {
        Section("Status") {
            currentStatusRow
            statusReferenceRow
            archivedStateRows
            statusSpecificRows
            AnimalDetailStatusActionButtons(detail: detail, onBeginEditingStatus: onBeginEditingStatus)
        }
    }

    private var currentStatusRow: some View {
        HStack {
            Text("Current Status")
            Spacer()
            Label(detail.status.label, systemImage: detail.status.systemImage)
                .fontWeight(.semibold)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
    }

    @ViewBuilder
    private var statusReferenceRow: some View {
        if let statusReferenceName = detail.statusReferenceName {
            LabeledContent("Status Reference") {
                Text(statusReferenceName)
                    .fontWeight(.medium)
            }
        }
    }

    @ViewBuilder
    private var archivedStateRows: some View {
        if detail.isArchived {
            HStack {
                Text("Record State")
                Spacer()
                Label("Archived", systemImage: "archivebox.fill")
                    .foregroundStyle(.orange)
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }

            if let archivedAt = detail.archivedAt {
                LabeledContent("Archived On") {
                    Text(archivedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    @ViewBuilder
    private var statusSpecificRows: some View {
        switch detail.status {
        case .active:
            EmptyView()
        case .sold:
            LabeledContent("Sale Date") {
                Text(formattedDate(detail.saleDate))
            }

            LabeledContent("Sale Price") {
                Text(formattedSalePrice)
            }

            if let reasonSold = detail.reasonSold, !reasonSold.isEmpty {
                LabeledContent("Reason Sold") {
                    Text(reasonSold)
                        .multilineTextAlignment(.trailing)
                }
            }
        case .dead:
            LabeledContent("Death Date") {
                Text(formattedDate(detail.deathDate))
            }

            if let causeOfDeath = detail.causeOfDeath, !causeOfDeath.isEmpty {
                LabeledContent("Cause of Death") {
                    Text(causeOfDeath)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var formattedSalePrice: String {
        detail.salePrice?.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")) ?? "—"
    }

    private func formattedDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    }
}

private struct AnimalDetailStatusActionButtons: View {
    let detail: AnimalDetailSnapshot
    let onBeginEditingStatus: (AnimalStatus) -> Void

    var body: some View {
        switch detail.status {
        case .active:
            statusButton("Mark Sold", status: .sold)
            statusButton("Mark Dead", status: .dead)
        case .sold:
            statusButton("Return to Active", status: .active)
            statusButton("Correct to Dead", status: .dead)
        case .dead:
            statusButton("Correct to Active", status: .active)
            statusButton("Correct to Sold", status: .sold)
        }
    }

    private func statusButton(_ title: String, status: AnimalStatus) -> some View {
        Button {
            onBeginEditingStatus(status)
        } label: {
            Label(title, systemImage: status.systemImage)
        }
    }
}
