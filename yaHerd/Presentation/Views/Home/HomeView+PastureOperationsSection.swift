import SwiftUI

extension HomeView {
    @ViewBuilder
    var pastureOperationsSection: some View {
        if snapshot == nil || hasPastureOperationRows {
            HomeSection(title: "Pasture Operations") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading pasture operations…")
                } else {
                    pastureOperationRows
                }
            }
        }
    }

    @ViewBuilder
    var pastureOperationRows: some View {
        if !overstockedPastures.isEmpty {
            Button {
                openPastureList(.overstocked)
            } label: {
                HomeListRow(
                    title: "Pastures needing relief",
                    subtitle: "Move animals out of pastures over configured capacity.",
                    systemImage: "arrow.up.right.circle.fill",
                    tint: .red,
                    count: overstockedPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !rotationReadyPastures.isEmpty {
            Button {
                openPastureList(.rotationReady)
            } label: {
                HomeListRow(
                    title: "Pastures ready to receive animals",
                    subtitle: "Rested pastures below the upper utilization threshold.",
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: .green,
                    count: rotationReadyPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !underutilizedPastures.isEmpty {
            Button {
                openPastureList(.underutilized)
            } label: {
                HomeListRow(
                    title: "Potential receiving pastures",
                    subtitle: "Underused pastures that may be candidates for a move.",
                    systemImage: "tray.and.arrow.down.fill",
                    tint: .teal,
                    count: underutilizedPastures.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !pasturesMissingStockingData.isEmpty {
            Button {
                openPastureList(.missingStockingData)
            } label: {
                HomeListRow(
                    title: "Pastures missing stocking data",
                    subtitle: "Add acreage or target acres/head so capacity decisions are meaningful.",
                    systemImage: "ruler.fill",
                    tint: .brown,
                    count: pasturesMissingStockingData.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

}
