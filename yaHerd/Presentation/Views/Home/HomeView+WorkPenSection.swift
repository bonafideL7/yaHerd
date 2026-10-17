import SwiftUI

extension HomeView {
    @ViewBuilder
    var workPenSection: some View {
        HomeSection(title: "Working Pen") {
                if snapshot == nil {
                    HomeLoadingRow(title: "Loading working pen…")
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
                        WorkingSessionsView { sessionID in
                            openWorkArea(.session(sessionID))
                        }
                    } label: {
                        HomeListRow(
                            title: "Working sessions",
                            subtitle: "Open active sessions or review completed work.",
                            systemImage: "clock.arrow.circlepath",
                            tint: .gray,
                            count: nil,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

            treatmentSection
        }
    }

    var treatmentSection: some View {
        NavigationLink {
            TreatmentTemplatesView()
        } label: {
            HomeListRow(
                title: "Treatment Sets",
                subtitle: "Maintain reusable treatment sets.",
                systemImage: "syringe.fill",
                tint: .indigo,
                count: nil,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }
}
