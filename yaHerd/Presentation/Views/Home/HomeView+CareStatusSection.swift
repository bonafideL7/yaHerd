import SwiftUI

extension HomeView {
    var careStatusSection: some View {
        HomeSection(title: "Care Status") {
            if snapshot == nil {
                HomeLoadingRow(title: "Loading care status…")
            } else {
                Button {
                    openAnimalList(.calvingWatch)
                } label: {
                    HomeListRow(
                        title: "Calving watch",
                        subtitle: "Pregnant animals currently inside the watch window.",
                        systemImage: "figure.2.and.child.holdinghands",
                        tint: calvingWatchAnimalRecords.isEmpty ? .gray : .pink,
                        count: calvingWatchAnimalRecords.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                Button {
                    openAnimalList(.overduePregnancyChecks)
                } label: {
                    HomeListRow(
                        title: "Pregnancy check status",
                        subtitle: "Threshold: \(configuration.pregnancyCheckIntervalDays) days since last check.",
                        systemImage: "stethoscope",
                        tint: overduePregnancyCheckAnimalRecords.isEmpty ? .green : .orange,
                        count: overduePregnancyCheckAnimalRecords.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                Button {
                    openAnimalList(.overdueTreatments)
                } label: {
                    HomeListRow(
                        title: "Treatment status",
                        subtitle: "Threshold: \(configuration.treatmentIntervalDays) days since last treatment.",
                        systemImage: "pills.fill",
                        tint: overdueTreatmentAnimalRecords.isEmpty ? .green : .red,
                        count: overdueTreatmentAnimalRecords.count,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

}
