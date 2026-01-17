import Foundation
import SwiftData

struct DashboardService {

    static func generateAlerts(
        animals: [Animal],
        pastures: [Pasture],
        pregCheckIntervalDays: Int,
        treatmentIntervalDays: Int,
        enablePastureOverstockWarnings: Bool,
        pastureCapacity: Int
    ) -> [DashboardAlert] {

        var alerts: [DashboardAlert] = []
        let now = Date()

        // MARK: - 1. Unassigned animals
        let unassigned = animals.filter { animal in
            animal.pasture == nil && animal.status == .alive && animal.location == .pasture
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

        // MARK: - 2. Overdue Pregnancy Checks
        let overduePreg = animals.filter { animal in
            guard let last = animal.pregnancyChecks.sorted(by: { (a: PregnancyCheck, b: PregnancyCheck) in
                a.date > b.date
            }).first else { return false }

            let days = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
            return days > pregCheckIntervalDays && animal.status == .alive
        }

        if !overduePreg.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(overduePreg.count) animals overdue for pregnancy check",
                    message: "Last check exceeds \(pregCheckIntervalDays) days.",
                    icon: "stethoscope",
                    severity: .warning,
                    destination: .animalList(.overduePregChecks)
                )
            )
        }

        // MARK: - 3. Calving Windows (283-day gestation)
        let pregnant = animals.filter { animal in
            animal.pregnancyChecks.sorted(by: { (a: PregnancyCheck, b: PregnancyCheck) in
                a.date > b.date
            }).first?.result == .pregnant
        }

        for animal in pregnant {
            guard let last = animal.pregnancyChecks.sorted(by: { (a: PregnancyCheck, b: PregnancyCheck) in
                a.date > b.date
            }).first else { continue }

            let calvingDate: Date = {
                if let due = last.dueDate { return due }
                // fallback: 283-day gestation from check date
                return Calendar.current.date(byAdding: .day, value: 283, to: last.date) ?? last.date
            }()

            if now > calvingDate {
                alerts.append(
                    DashboardAlert(
                        title: "Calving possibly overdue for \(animal.tagNumber)",
                        message: "Expected around \(calvingDate.formatted(date: .abbreviated, time: .omitted))",
                        icon: "baby",
                        severity: .critical,
                        destination: .animal(animal)
                    )
                )
            }
        }

        // MARK: - 4. Overdue Treatments
        let overdueTreatments = animals.filter { animal in
            guard let last = animal.healthRecords.sorted(by: { (a: HealthRecord, b: HealthRecord) in
                a.date > b.date
            }).first else { return false }

            let days = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
            return days > treatmentIntervalDays
        }

        if !overdueTreatments.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(overdueTreatments.count) animals overdue for treatments",
                    message: "Treatments older than \(treatmentIntervalDays) days.",
                    icon: "pill",
                    severity: .warning,
                    destination: .animalList(.overdueTreatments)
                )
            )
        }

        // MARK: - 5. Pasture Overstock
//        if enablePastureOverstockWarnings {
//            for pasture in pastures {
//                if pasture.animals.count > pastureCapacity {
//                    alerts.append(
//                        DashboardAlert(
//                            title: "Overstock warning: \(pasture.name)",
//                            message: "\(pasture.animals.count) animals > capacity \(pastureCapacity)",
//                            icon: "alert-triangle",
//                            severity: .warning
//                        )
//                    )
//                }
//            }
//        }
        
        if enablePastureOverstockWarnings {
            for pasture in pastures {
                let alive = pasture.animals.filter { $0.status == .alive }.count
                let analytics = PastureAnalytics(
                    pasture: pasture,
                    aliveAnimals: alive,
                    fallbackCapacityHead: Double(pastureCapacity)
                )
                
                if analytics.isOverstocked,
                   let cap = analytics.capacityHead {
                    alerts.append(
                        DashboardAlert(
                            title: "Overstock warning in \(pasture.name)",
                            message: "\(alive) animals > capacity \(Int(cap))",
                            icon: "alert-triangle",
                            severity: .warning,
                            destination: .pasture(pasture)
                        )
                    )
                }
            }
        }

        // MARK: - Final Sort (severity)
        let sortedAlerts = alerts.sorted(by: { (a: DashboardAlert, b: DashboardAlert) in
            a.severityOrder > b.severityOrder
        })

        return sortedAlerts
    }
}
