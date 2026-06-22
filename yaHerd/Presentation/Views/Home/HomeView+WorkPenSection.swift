import SwiftUI

extension HomeView {
    var workPenSection: some View {
        HomeSection(title: "Work Pen") {
            if snapshot == nil {
                HomeLoadingRow(title: "Loading work pen…")
            } else {
                if shouldShowWorkingPenAnimalsRow {
                    Button {
                        openAnimalList(.workingPen)
                    } label: {
                        HomeListRow(
                            title: "Animals staged in working pen",
                            subtitle: "Open the pre-filtered list before moving or clearing them.",
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: .orange,
                            count: workingPenCount,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    ProtocolTemplatesView()
                } label: {
                    HomeListRow(
                        title: "Protocol templates",
                        subtitle: "Maintain reusable treatment and processing templates.",
                        systemImage: "list.bullet.rectangle.fill",
                        tint: .indigo,
                        count: nil,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    HomeListRow(
                        title: "Working session history",
                        subtitle: "Review active and completed work sessions.",
                        systemImage: "clock.arrow.circlepath",
                        tint: .gray,
                        count: nil,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

}
