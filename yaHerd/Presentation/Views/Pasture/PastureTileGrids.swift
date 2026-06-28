import SwiftUI
import UniformTypeIdentifiers

struct PastureTileGrid: View {
    let items: [PastureSummary]
    let filter: PastureListFilter
    let totalCount: Int
    let onSelect: (PastureSummary) -> Void
    let onBeginManaging: () -> Void
    let onClearFilter: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if filter != .all {
                    PastureFilterSummaryRow(
                        filter: filter,
                        filteredCount: items.count,
                        totalCount: totalCount,
                        onClearFilter: onClearFilter
                    )
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { pasture in
                        PastureTileCard(pasture: pasture) {
                            onSelect(pasture)
                        }
                        .onLongPressGesture(minimumDuration: 0.35, perform: onBeginManaging)
                    }
                }
            }
            .padding(16)
        }
    }
}

struct PastureManageGrid: View {
    let items: [PastureSummary]
    @Binding var draggedPasture: PastureSummary?
    let onDelete: (PastureSummary) -> Void
    let onBeginDrag: (PastureSummary) -> Void
    let onMove: (Int, Int) -> Void
    let onCommitMove: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { pasture in
                        PastureTileCard(
                            pasture: pasture,
                            isManaging: true,
                            isDragging: draggedPasture?.id == pasture.id,
                            onDelete: { onDelete(pasture) },
                            onTap: {}
                        )
                        .onDrag {
                            onBeginDrag(pasture)
                            return NSItemProvider(object: pasture.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PastureTileDropDelegate(
                                pasture: pasture,
                                items: items,
                                draggedPasture: $draggedPasture,
                                movePasture: onMove,
                                commitPastureOrder: onCommitMove
                            )
                        )
                        .zIndex(draggedPasture?.id == pasture.id ? 1 : 0)
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct PastureTileDropDelegate: DropDelegate {
    let pasture: PastureSummary
    let items: [PastureSummary]
    @Binding var draggedPasture: PastureSummary?
    let movePasture: (Int, Int) -> Void
    let commitPastureOrder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedPasture,
              draggedPasture.id != pasture.id,
              let sourceIndex = items.firstIndex(where: { $0.id == draggedPasture.id }),
              let destinationIndex = items.firstIndex(where: { $0.id == pasture.id }) else {
            return
        }

        let destination = sourceIndex < destinationIndex ? destinationIndex + 1 : destinationIndex
        movePasture(sourceIndex, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedPasture != nil else { return false }

        commitPastureOrder()
        draggedPasture = nil
        return true
    }
}
