//
//  AnimalListToolbarContent.swift
//

import SwiftUI

struct AnimalListToolbarContent: ToolbarContent {
    let sortOrder: AnimalSortOrder
    let batchMode: Bool
    let canCollapseSections: Bool
    let onReverseSortDirection: () -> Void
    let onCollapseAllSections: () -> Void
    let onToggleBatchMode: () -> Void
    let onOpenSettings: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            auxiliaryButton
            actionButton
        }
    }

    @ViewBuilder
    private var auxiliaryButton: some View {
        if sortOrder.canReverseDirection && !batchMode {
            Button(action: onReverseSortDirection) {
                Image(systemName: sortOrder.reverseDirectionIcon)
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel(sortOrder.reverseDirectionAccessibilityLabel)
            .accessibilityHint("Reverses the current animal sort direction")
        } else if canCollapseSections && !batchMode {
            Button(action: onCollapseAllSections) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("Collapse All Sections")
            .accessibilityHint("Collapses every visible animal group")
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if batchMode {
            Button(action: onToggleBatchMode) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done Selecting")
        } else {
            Menu {
                Button(action: onToggleBatchMode) {
                    Label("Select Animals", systemImage: "checklist")
                }

                Divider()

                NavigationLink {
                    FieldChecksView(mode: .all)
                } label: {
                    Label("Pasture Checks", systemImage: "checklist")
                }

                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    Label("Working Sessions", systemImage: "wrench.and.screwdriver")
                }

                Divider()

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Animal list actions")
        }
    }
}
