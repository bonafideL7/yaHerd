import SwiftData
import Foundation

struct SampleDataService {

    static func seedIfNeeded(context: ModelContext) {

        // Seed working protocol templates (safe to do independently of animal seed)
        seedProtocolTemplatesIfNeeded(context: context)

        // Avoid reseeding sample animals/pastures
        let descriptor = FetchDescriptor<Animal>()
        if let existing = try? context.fetch(descriptor),
           !existing.isEmpty { return }


        // MARK: - Pastures
        let north = Pasture(name: "North Pasture", acreage: 35)
        let south = Pasture(name: "South Pasture", acreage: 28)
        let east  = Pasture(name: "East Meadow",   acreage: 22)
        let drylot = Pasture(name: "Drylot",       acreage: 5)

        context.insert(north)
        context.insert(south)
        context.insert(east)
        context.insert(drylot)


        // MARK: - Animals
        let a1 = Animal(tagNumber: "101", birthDate: daysAgo(900), status: .alive, sire: "A13", dam: "B07", pasture: north, biologicalSex: .female)
        let a2 = Animal(tagNumber: "102", birthDate: daysAgo(700), status: .alive, sire: "A13", dam: "B07", pasture: south, biologicalSex: .female)
        let a3 = Animal(tagNumber: "201", birthDate: daysAgo(1400), status: .alive, sire: "X99", dam: "C21", pasture: drylot, biologicalSex: .male)
        let a4 = Animal(tagNumber: "301", birthDate: daysAgo(300), status: .alive, sire: "A55", dam: "C33", pasture: north, biologicalSex: .female)

        // archived examples
        let a5 = Animal(tagNumber: "401", birthDate: daysAgo(1200), status: .sold, sire: "Z18", dam: "D99", pasture: south, biologicalSex: .female)
        let a6 = Animal(tagNumber: "402", birthDate: daysAgo(1500), status: .deceased, sire: "Z18", dam: "D99", pasture: east, biologicalSex: .female)

        let a7 = Animal(tagNumber: "501", birthDate: daysAgo(1100), status: .alive, sire: "S9", dam: "R2", pasture: east, biologicalSex: .female)
        let a8 = Animal(tagNumber: "502", birthDate: daysAgo(1050), status: .alive, sire: "S9", dam: "R2", pasture: north, biologicalSex: .female)

        let a9 = Animal(tagNumber: "503", birthDate: daysAgo(200), status: .alive, sire: "A9", dam: "F1", pasture: south, biologicalSex: .female)
        let a10 = Animal(tagNumber: "504", birthDate: daysAgo(150), status: .alive, sire: "A9", dam: "F1", pasture: north, biologicalSex: .female)
        let a11 = Animal(tagNumber: "601", birthDate: daysAgo(1800), status: .alive, sire: "OldBull", dam: "Matriarch", pasture: drylot, biologicalSex: .male)
        let a12 = Animal(tagNumber: "701", birthDate: daysAgo(500), status: .alive, sire: "S21", dam: "H04", pasture: east, biologicalSex: .female)

        let animals = [a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12]
        animals.forEach { context.insert($0) }


        // MARK: - Pregnancy Checks (creates dashboard preg-check alerts)
        context.insert(PregnancyCheck(date: daysAgo(30), result: .pregnant, technician: "Dr. Smith", animal: a1))
        context.insert(PregnancyCheck(date: daysAgo(29), result: .open,     technician: "Dr. Smith", animal: a2))
        context.insert(PregnancyCheck(date: daysAgo(220), result: .pregnant, technician: "Dr. Lee", animal: a7))   // overdue calving
        context.insert(PregnancyCheck(date: daysAgo(61),  result: .unknown,  technician: "Dr. Lee", animal: a8))


        // MARK: - Health Records (creates overdue treatment alerts)
        context.insert(HealthRecord(date: daysAgo(10),  treatment: "Vaccination", notes: "Booster", animal: a1))
        context.insert(HealthRecord(date: daysAgo(210), treatment: "Deworming",   notes: nil,       animal: a3))   // overdue treatment
        context.insert(HealthRecord(date: daysAgo(45),  treatment: "Foot Trim",   notes: "Mild lesion LF", animal: a4))
        context.insert(HealthRecord(date: daysAgo(5),   treatment: "Antibiotic",  notes: "Metritis", animal: a7))
        context.insert(HealthRecord(date: daysAgo(7),   treatment: "Vaccination", notes: nil,        animal: a8))


        // MARK: - Movement History (timeline)
        let movementData: [(Animal, String?, String, Int)] = [
            (a1, "South Pasture",   "North Pasture", 120),
            (a1, "North Pasture",   "East Meadow",   20),
            (a2, "North Pasture",   "South Pasture", 45),
            (a3, nil,               "Drylot",        200),
            (a7, "East Meadow",     "North Pasture", 75),
            (a8, "North Pasture",   "South Pasture", 30),
        ]

        for (animal, from, to, days) in movementData {
            let m = MovementRecord(
                date: daysAgo(days),
                fromPasture: from,
                toPasture: to,
                animal: animal
            )
            context.insert(m)
        }


        // MARK: - Status History (timeline + dashboard)
        let statusData: [(Animal, AnimalStatus, AnimalStatus, Int)] = [
            (a5, .alive,    .sold,     40),
            (a6, .alive,    .deceased, 300),
        ]

        for (animal, oldStatus, newStatus, days) in statusData {
            let s = StatusRecord(
                date: daysAgo(days),
                oldStatus: oldStatus,
                newStatus: newStatus,
                animal: animal
            )
            context.insert(s)
        }

        try? context.save()
    }

    private static func seedProtocolTemplatesIfNeeded(context: ModelContext) {
        let desc = FetchDescriptor<WorkingProtocolTemplate>()
        let existing = (try? context.fetch(desc)) ?? []
        guard existing.isEmpty else { return }

        let spring = WorkingProtocolTemplate(
            name: "Spring Working",
            items: [
                WorkingProtocolItem(name: "7-way", defaultQuantity: nil),
                WorkingProtocolItem(name: "Respiratory", defaultQuantity: nil),
                WorkingProtocolItem(name: "Dewormer", defaultQuantity: nil)
            ]
        )

        let fall = WorkingProtocolTemplate(
            name: "Fall Booster",
            items: [
                WorkingProtocolItem(name: "Booster", defaultQuantity: nil)
            ]
        )

        context.insert(spring)
        context.insert(fall)
        try? context.save()
    }


    // MARK: - Helper
    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }
}
