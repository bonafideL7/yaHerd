import SwiftUI

extension HomeView {
    @ViewBuilder
    var workPenSection: some View {
        treatmentSection

        if snapshot == nil || hasWorkingPenRows {
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
                        WorkingSessionsView()
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
            }
        }
    }

    var treatmentSection: some View {
        HomeSection(title: "Treatments") {
            NavigationLink {
                TreatmentTemplatesView()
            } label: {
                HomeListRow(
                    title: "Treatments",
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
}
