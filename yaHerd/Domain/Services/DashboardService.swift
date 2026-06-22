import Foundation

struct DashboardService {
    func makeSnapshot(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date = .now
    ) -> DashboardSnapshot {
        let searchableAnimals = sortedAnimalItems(from: activeAnimals(in: records))
        let pastures = sortedPastureItems(from: records.pastures, configuration: configuration)

        return DashboardSnapshot(
            activeSession: activeSession(in: records),
            alerts: alerts(in: records, configuration: configuration, now: now),
            overview: overview(in: records, configuration: configuration, now: now),
            analytics: analytics(in: records, now: now),
            searchableAnimals: searchableAnimals,
            pastures: pastures
        )
    }

    func makeAnimalList(
        kind: DashboardAnimalListKind,
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date = .now
    ) -> [DashboardAnimalItem] {
        let animals: [DashboardAnimalRecord]

        switch kind {
        case .active:
            animals = activeAnimals(in: records)
        case .workingPen:
            animals = activeAnimals(in: records).filter { $0.location == .workingPen }
        case .unassigned:
            animals = unassignedAnimals(in: records)
        }

        return sortedAnimalItems(from: animals)
    }

    func filterPastures(
        _ items: [DashboardPastureItem],
        filter: DashboardPastureFilter
    ) -> [DashboardPastureItem] {
        switch filter {
        case .all:
            return items
        case .underutilized:
            return items.filter { $0.isUnderutilized }
        case .rotationReady:
            return items.filter { $0.isRotationReady }
        }
    }


    private func analytics(in records: DashboardRecords, now: Date) -> DashboardAnalytics {
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
        let calendar = Calendar.current
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
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentSeason: DashboardCalvingSeason = currentMonth <= 6 ? .spring : .fall

        let animals = visibleAnimalsForAnalytics(in: records)
        let seasons = recentCalvingSeasons(endingYear: currentYear, endingSeason: currentSeason, count: 8)
        let birthCounts = Dictionary(grouping: animals) { animal in
            seasonKey(for: animal.birthDate, calendar: calendar)
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

        return seasons.reversed().map { $0 }
    }

    private func seasonKey(for date: Date, calendar: Calendar) -> String {
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
        let calendar = Calendar.current
        let monthStarts = recentMonthStarts(endingAt: now, count: 12, calendar: calendar)
        guard let firstMonth = monthStarts.first else { return [] }

        let animals = visibleAnimalsForAnalytics(in: records)
        let recentRecords = animals
            .flatMap(\.healthRecords)
            .filter { $0.date >= firstMonth }

        let topCategories = Dictionary(grouping: recentRecords) { record in
            treatmentCategory(for: record.treatment)
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
                        && treatmentCategory(for: record.treatment) == category
                }.count

                return DashboardMonthlyMedicalRecordCount(
                    monthStart: monthStart,
                    treatmentCategory: category,
                    count: count
                )
            }
        }
    }

    private func recentMonthStarts(endingAt date: Date, count: Int, calendar: Calendar) -> [Date] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let currentMonthStart = calendar.date(from: components) else { return [] }

        return (0..<count)
            .compactMap { offset in
                calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
            }
            .reversed()
            .map { $0 }
    }

    private func pinkEyeCasesByYear(in records: DashboardRecords, now: Date) -> [DashboardYearCount] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let years = Array((currentYear - 5)...currentYear)

        let animals = visibleAnimalsForAnalytics(in: records)
        let pinkEyeRecords = animals
            .flatMap(\.healthRecords)
            .filter { isPinkEyeRecord($0) }

        let counts = Dictionary(grouping: pinkEyeRecords) { record in
            calendar.component(.year, from: record.date)
        }.mapValues(\.count)

        return years.map { year in
            DashboardYearCount(year: year, count: counts[year, default: 0])
        }
    }

    private func statusOutcomesByYear(in records: DashboardRecords, now: Date) -> [DashboardStatusOutcomeYearCount] {
        let calendar = Calendar.current
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

    private func treatmentCategory(for treatment: String) -> String {
        let normalized = treatment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return "Unspecified" }

        if normalized.contains("pinkeye") || normalized.contains("pink eye") { return "Pink eye" }
        if normalized.contains("foot") || normalized.contains("hoof") { return "Foot/hoof" }
        if normalized.contains("vaccine") || normalized.contains("vaccination") || normalized.contains("shot") { return "Vaccination" }
        if normalized.contains("worm") || normalized.contains("parasite") { return "Deworming" }
        if normalized.contains("castrat") || normalized.contains("band") { return "Castration/banding" }
        if normalized.contains("antibiotic") || normalized.contains("biotic") { return "Antibiotic" }

        return treatment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: " ")
            .capitalized
    }

    private func isPinkEyeRecord(_ record: DashboardHealthRecord) -> Bool {
        let searchableText = [record.treatment, record.notes ?? ""]
            .joined(separator: " ")
            .lowercased()
        return searchableText.contains("pinkeye") || searchableText.contains("pink eye")
    }

    private func overview(
        in records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> DashboardOverview {
        let active = activeAnimals(in: records)
        let pastures = sortedPastureItems(from: records.pastures, configuration: configuration)

        return DashboardOverview(
            activeAnimalCount: active.count,
            workingPenCount: active.filter { $0.location == .workingPen }.count,
            unassignedAnimalCount: unassignedAnimals(in: records).count,
            pastureCount: records.pastures.count,
            underutilizedPastureCount: pastures.filter { $0.isUnderutilized }.count,
            rotationReadyPastureCount: pastures.filter { $0.isRotationReady }.count
        )
    }

    private func activeAnimals(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        records.animals.filter { $0.isActiveInHerd }
    }

    private func unassignedAnimals(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        activeAnimals(in: records).filter { animal in
            animal.location == .pasture && animal.pastureID == nil
        }
    }

    private func activeSession(in records: DashboardRecords) -> DashboardWorkingSessionSummary? {
        records.workingSessions
            .sorted { lhs, rhs in
                lhs.date > rhs.date
            }
            .first(where: { $0.isActive })
            .map { session in
                DashboardWorkingSessionSummary(
                    id: session.id,
                    date: session.date,
                    sourcePastureName: session.sourcePastureName,
                    protocolName: session.protocolName,
                    totalQueueItems: session.totalQueueItems,
                    completedQueueItems: session.completedQueueItems
                )
            }
    }

    private func sortedAnimalItems(from animals: [DashboardAnimalRecord]) -> [DashboardAnimalItem] {
        animals
            .map { animal in
                DashboardAnimalItem(
                    id: animal.id,
                    displayTagNumber: animal.displayTagNumber,
                    displayTagColorID: animal.displayTagColorID,
                    damDisplayTagNumber: animal.damDisplayTagNumber,
                    damDisplayTagColorID: animal.damDisplayTagColorID,
                    sex: animal.sex,
                    animalType: animal.animalType,
                    pastureID: animal.pastureID,
                    pastureName: animal.pastureName,
                    location: animal.location
                )
            }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    private func sortedPastureItems(
        from pastures: [DashboardPastureRecord],
        configuration: DashboardConfiguration
    ) -> [DashboardPastureItem] {
        pastures
            .map { pasture in
                DashboardPastureItem(
                    id: pasture.id,
                    name: pasture.name,
                    activeAnimalCount: pasture.activeAnimalCount,
                    metrics: PastureMetrics(
                        acreage: pasture.acreage,
                        usableAcreage: pasture.usableAcreage,
                        activeAnimals: pasture.activeAnimalCount,
                        targetAcresPerHead: pasture.targetAcresPerHead,
                        fallbackCapacityHead: nil
                    ),
                    lastGrazedDate: pasture.lastGrazedDate,
                    restDays: pasture.restDays
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func alerts(
        in records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardAlert] {
        var alerts: [DashboardAlert] = []

        let unassigned = unassignedAnimals(in: records)
        if !unassigned.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(unassigned.count) animals not assigned to a pasture",
                    message: "Assign them to avoid management issues.",
                    icon: "map-pin-off",
                    severity: .warning,
                    destination: .animalList(.unassigned)
                )
            )
        }

        return alerts.sorted { lhs, rhs in
            lhs.severityOrder > rhs.severityOrder
        }
    }
}
