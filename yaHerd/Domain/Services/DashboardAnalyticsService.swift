import Foundation

struct DashboardAnalyticsService {
    private let calendar: Calendar
    private let healthRecordClassifier: DashboardHealthRecordClassifier

    init(
        calendar: Calendar = .current,
        healthRecordClassifier: DashboardHealthRecordClassifier = DashboardHealthRecordClassifier()
    ) {
        self.calendar = calendar
        self.healthRecordClassifier = healthRecordClassifier
    }

    func makeAnalytics(in records: DashboardRecords, now: Date) -> DashboardAnalytics {
        DashboardAnalytics(
            lifecycleMetrics: lifecycleMetrics(in: records, now: now),
            seasonalCalvingCounts: seasonalCalvingCounts(in: records, now: now),
            offspringByDam: offspringByDam(in: records),
            monthlyMedicalRecords: monthlyMedicalRecords(in: records, now: now),
            pinkEyeCasesByYear: pinkEyeCasesByYear(in: records, now: now),
            statusOutcomesByYear: statusOutcomesByYear(in: records, now: now)
        )
    }

    private func visibleAnimalsForAnalytics(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        records.animals.filter { !$0.isArchived }
    }

    private func lifecycleMetrics(in records: DashboardRecords, now: Date) -> [DashboardLifecycleMetric] {
        let year = calendar.component(.year, from: now)
        let animals = visibleAnimalsForAnalytics(in: records)

        return [
            DashboardLifecycleMetric(
                label: "Born YTD",
                value: animals.filter { calendar.component(.year, from: $0.birthDate) == year }.count,
                systemImage: "figure.2.and.child.holdinghands"
            ),
            DashboardLifecycleMetric(
                label: "Sold YTD",
                value: animals.filter { animal in
                    guard let saleDate = animal.saleDate else { return false }
                    return calendar.component(.year, from: saleDate) == year
                }.count,
                systemImage: "dollarsign.circle.fill"
            ),
            DashboardLifecycleMetric(
                label: "Deceased YTD",
                value: animals.filter { animal in
                    guard let deathDate = animal.deathDate else { return false }
                    return calendar.component(.year, from: deathDate) == year
                }.count,
                systemImage: "xmark.octagon.fill"
            ),
            DashboardLifecycleMetric(
                label: "Health Records YTD",
                value: animals.flatMap(\.healthRecords).filter { record in
                    calendar.component(.year, from: record.date) == year
                }.count,
                systemImage: "cross.case.fill"
            )
        ]
    }

    private func seasonalCalvingCounts(in records: DashboardRecords, now: Date) -> [DashboardSeasonalCalvingCount] {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentSeason: DashboardCalvingSeason = currentMonth <= 6 ? .spring : .fall

        let animals = visibleAnimalsForAnalytics(in: records)
        let seasons = recentCalvingSeasons(endingYear: currentYear, endingSeason: currentSeason, count: 8)
        let birthCounts = Dictionary(grouping: animals) { animal in
            seasonKey(for: animal.birthDate)
        }.mapValues(\.count)

        return seasons.map { season in
            DashboardSeasonalCalvingCount(
                seasonID: season.id,
                seasonLabel: "\(season.season.label) \(season.year)",
                year: season.year,
                season: season.season,
                count: birthCounts[season.id, default: 0]
            )
        }
    }

    private func recentCalvingSeasons(
        endingYear: Int,
        endingSeason: DashboardCalvingSeason,
        count: Int
    ) -> [(id: String, year: Int, season: DashboardCalvingSeason)] {
        var year = endingYear
        var season = endingSeason
        var seasons: [(id: String, year: Int, season: DashboardCalvingSeason)] = []

        for _ in 0..<count {
            seasons.append((id: "\(year)-\(season.rawValue)", year: year, season: season))
            if season == .fall {
                season = .spring
            } else {
                season = .fall
                year -= 1
            }
        }

        return seasons.reversed()
    }

    private func seasonKey(for date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let season: DashboardCalvingSeason = month <= 6 ? .spring : .fall
        return "\(year)-\(season.rawValue)"
    }

    private func offspringByDam(in records: DashboardRecords) -> [DashboardOffspringDamMetric] {
        let animals = visibleAnimalsForAnalytics(in: records)
        let grouped = Dictionary(grouping: animals.filter(\.hasRecordedDam)) { animal in
            animal.damDisplayTagNumber ?? "Unknown"
        }

        return grouped
            .map { damTag, offspring in
                DashboardOffspringDamMetric(
                    damID: damTag,
                    damDisplayTagNumber: damTag,
                    offspringCount: offspring.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.offspringCount != rhs.offspringCount { return lhs.offspringCount > rhs.offspringCount }
                return lhs.damDisplayTagNumber.localizedStandardCompare(rhs.damDisplayTagNumber) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
    }

    private func monthlyMedicalRecords(in records: DashboardRecords, now: Date) -> [DashboardMonthlyMedicalRecordCount] {
        let monthStarts = recentMonthStarts(endingAt: now, count: 12)
        guard let firstMonth = monthStarts.first else { return [] }

        let animals = visibleAnimalsForAnalytics(in: records)
        let recentRecords = animals
            .flatMap(\.healthRecords)
            .filter { $0.date >= firstMonth }

        let topCategories = Dictionary(grouping: recentRecords) { record in
            healthRecordClassifier.category(for: record.treatment)
        }
        .map { category, records in (category: category, count: records.count) }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
        }
        .prefix(4)
        .map(\.category)

        return monthStarts.flatMap { monthStart in
            topCategories.map { category in
                let count = recentRecords.filter { record in
                    calendar.isDate(record.date, equalTo: monthStart, toGranularity: .month)
                        && healthRecordClassifier.category(for: record.treatment) == category
                }.count

                return DashboardMonthlyMedicalRecordCount(
                    monthStart: monthStart,
                    treatmentCategory: category,
                    count: count
                )
            }
        }
    }

    private func recentMonthStarts(endingAt date: Date, count: Int) -> [Date] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let currentMonthStart = calendar.date(from: components) else { return [] }

        return (0..<count)
            .compactMap { offset in
                calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
            }
            .reversed()
    }

    private func pinkEyeCasesByYear(in records: DashboardRecords, now: Date) -> [DashboardYearCount] {
        let currentYear = calendar.component(.year, from: now)
        let years = Array((currentYear - 5)...currentYear)

        let animals = visibleAnimalsForAnalytics(in: records)
        let pinkEyeRecords = animals
            .flatMap(\.healthRecords)
            .filter { healthRecordClassifier.isPinkEyeRecord($0) }

        let counts = Dictionary(grouping: pinkEyeRecords) { record in
            calendar.component(.year, from: record.date)
        }.mapValues(\.count)

        return years.map { year in
            DashboardYearCount(year: year, count: counts[year, default: 0])
        }
    }

    private func statusOutcomesByYear(in records: DashboardRecords, now: Date) -> [DashboardStatusOutcomeYearCount] {
        let currentYear = calendar.component(.year, from: now)
        let years = Array((currentYear - 5)...currentYear)

        let animals = visibleAnimalsForAnalytics(in: records)

        return years.flatMap { year in
            [
                DashboardStatusOutcomeYearCount(
                    year: year,
                    outcome: .sold,
                    count: animals.filter { animal in
                        guard let saleDate = animal.saleDate else { return false }
                        return calendar.component(.year, from: saleDate) == year
                    }.count
                ),
                DashboardStatusOutcomeYearCount(
                    year: year,
                    outcome: .dead,
                    count: animals.filter { animal in
                        guard let deathDate = animal.deathDate else { return false }
                        return calendar.component(.year, from: deathDate) == year
                    }.count
                )
            ]
        }
    }
}
