import SwiftUI

extension HomeView {
    @ViewBuilder
    var recordsCleanupSection: some View {
        if snapshot == nil || hasRecordsCleanupRows {
            HomeSection(title: "Records to Clean Up") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading record checks…")
                } else {
                    recordsCleanupRows
                }
            }
        }
    }

    @ViewBuilder
    var recordsCleanupRows: some View {
        if !unassignedAnimalRecords.isEmpty {
            Button {
                openAnimalList(.missingPasture)
            } label: {
                HomeListRow(
                    title: "Animals missing pasture",
                    subtitle: "Assign active pasture animals before field work relies on location.",
                    systemImage: "mappin.slash.circle.fill",
                    tint: .brown,
                    count: unassignedAnimalRecords.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !missingTagAnimals.isEmpty {
            Button {
                openAnimalList(.missingTags)
            } label: {
                HomeListRow(
                    title: "Animals missing tags",
                    subtitle: "These records are harder to find during checks and working sessions.",
                    systemImage: "tag.slash.fill",
                    tint: .red,
                    count: missingTagAnimals.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !unknownSexAnimals.isEmpty {
            Button {
                openAnimalList(.unknownSex)
            } label: {
                HomeListRow(
                    title: "Animals with unknown sex",
                    subtitle: "Clean this up before breeding, calving, and filtering workflows depend on it.",
                    systemImage: "questionmark.circle.fill",
                    tint: .gray,
                    count: unknownSexAnimals.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        if !archivedActiveRecords.isEmpty {
            Button {
                openAnimalList(.archivedActive)
            } label: {
                HomeListRow(
                    title: "Archived records still marked active",
                    subtitle: "Review records that are hidden but still carry active status.",
                    systemImage: "archivebox.fill",
                    tint: .orange,
                    count: archivedActiveRecords.count,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }
}
