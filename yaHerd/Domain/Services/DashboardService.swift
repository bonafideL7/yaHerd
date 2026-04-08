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
            overview: overview(in: records),
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
            animals = activeAnimals(in: records).filter { $0.location == .pasture && $0.pastureID == nil }
        case .overduePregChecks:
            animals = records.animals.filter { animal in
                guard animal.isActiveInHerd else { return false }
                guard let lastCheckDate = animal.lastPregnancyCheckDate else { return false }
                let days = Calendar.current.dateComponents([.day], from: lastCheckDate, to: now).day ?? 0
                return days > configuration.pregnancyCheckIntervalDays
            }
        case .overdueTreatments:
            animals = records.animals.filter { animal in
                guard !animal.isArchived else { return false }
                guard let lastTreatmentDate = animal.lastTreatmentDate else { return false }
                let days = Calendar.current.dateComponents([.day], from: lastTreatmentDate, to: now).day ?? 0
                return days > configuration.treatmentIntervalDays
            }
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
        case .overstocked:
            return items.filter { $0.isOverstocked }
        case .underutilized:
            return items.filter { $0.isUnderutilized }
        }
    }

    private func overview(in records: DashboardRecords) -> DashboardOverview {
        let active = activeAnimals(in: records)

        return DashboardOverview(
            activeAnimalCount: active.count,
            workingPenCount: active.filter { $0.location == .workingPen }.count,
            unassignedAnimalCount: active.filter { $0.location == .pasture && $0.pastureID == nil }.count,
            pastureCount: records.pastures.count
        )
    }

    private func activeAnimals(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        records.animals.filter { $0.isActiveInHerd }
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
                    sex: animal.sex,
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
                        fallbackCapacityHead: Double(configuration.fallbackPastureCapacity)
                    ),
                    lastGrazedDate: pasture.lastGrazedDate
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
        let active = activeAnimals(in: records)

        let unassigned = active.filter { animal in
            animal.pastureID == nil && animal.location == .pasture
        }
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

        let overduePregnancyChecks = active.filter { animal in
            guard let lastCheckDate = animal.lastPregnancyCheckDate else { return false }
            let days = Calendar.current.dateComponents([.day], from: lastCheckDate, to: now).day ?? 0
            return days > configuration.pregnancyCheckIntervalDays
        }
        if !overduePregnancyChecks.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(overduePregnancyChecks.count) animals overdue for pregnancy check",
                    message: "Last check exceeds \(configuration.pregnancyCheckIntervalDays) days.",
                    icon: "stethoscope",
                    severity: .warning,
                    destination: .animalList(.overduePregChecks)
                )
            )
        }

        let calvingOverdueAnimals = active.filter { animal in
            guard animal.lastPregnancyStatus == .pregnant else { return false }
            guard let expectedCalvingDate = animal.expectedCalvingDate else { return false }
            return now > expectedCalvingDate
        }
        for animal in calvingOverdueAnimals {
            guard let expectedCalvingDate = animal.expectedCalvingDate else { continue }
            alerts.append(
                DashboardAlert(
                    title: "Calving possibly overdue for \(animal.displayTagNumber)",
                    message: "Expected around \(expectedCalvingDate.formatted(date: .abbreviated, time: .omitted))",
                    icon: "baby",
                    severity: .critical,
                    destination: .animal(animal.id)
                )
            )
        }

        let overdueTreatments = records.animals.filter { animal in
            guard !animal.isArchived else { return false }
            guard let lastTreatmentDate = animal.lastTreatmentDate else { return false }
            let days = Calendar.current.dateComponents([.day], from: lastTreatmentDate, to: now).day ?? 0
            return days > configuration.treatmentIntervalDays
        }
        if !overdueTreatments.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(overdueTreatments.count) animals overdue for treatments",
                    message: "Treatments older than \(configuration.treatmentIntervalDays) days.",
                    icon: "pill",
                    severity: .warning,
                    destination: .animalList(.overdueTreatments)
                )
            )
        }

        if configuration.enablePastureOverstockWarnings {
            let overstockedPastures = sortedPastureItems(from: records.pastures, configuration: configuration)
                .filter { $0.isOverstocked }

            for pasture in overstockedPastures {
                let capacity = pasture.capacityHead.map { Int($0) } ?? configuration.fallbackPastureCapacity
                alerts.append(
                    DashboardAlert(
                        title: "Overstock warning in \(pasture.name)",
                        message: "\(pasture.activeAnimalCount) animals > capacity \(capacity)",
                        icon: "alert-triangle",
                        severity: .warning,
                        destination: .pasture(pasture.id)
                    )
                )
            }
        }

        return alerts.sorted { lhs, rhs in
            lhs.severityOrder > rhs.severityOrder
        }
    }
}
