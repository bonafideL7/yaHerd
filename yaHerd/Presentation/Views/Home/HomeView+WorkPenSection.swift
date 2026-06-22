import SwiftUI

extension HomeView {
    var workPenSection: some View {
        HomeSection(title: "Work Pen") {
            if snapshot == nil {
                HomeLoadingRow(title: "Loading work pen…")
            } else {
                if activeSession == nil {
                    Button {
                        isPresentingNewWorkingSession = true
                    } label: {
                        HomeListRow(
                            title: "Start working session",
                            subtitle: "Collect animals, apply a protocol, and track completion.",
                            systemImage: "plus.circle.fill",
                            tint: .blue,
                            count: nil,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                }

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
