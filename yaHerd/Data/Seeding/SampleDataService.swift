import SwiftData
import Foundation
import SwiftUI

struct SampleDataService {
    
    static func seedDefaultsIfNeeded(context: ModelContext) {
        seedProtocolTemplatesIfNeeded(context: context)
    }

    static func seedSampleDataIfNeeded(context: ModelContext) {
        seedProtocolTemplatesIfNeeded(context: context)
        
        // Avoid reseeding sample animals/pastures
        let descriptor = FetchDescriptor<Animal>()
        if let existing = try? context.fetch(descriptor),
           !existing.isEmpty { return }
        
        // Resolve the default "Green" tag color id from the library store.
        // TagColorDefinition IDs are generated when the library is first seeded, so we look them up by name.
        let tagColorStore = TagColorLibraryStore()
        let greenTagColorID = tagColorStore.colors.first(where: { $0.name == "Green" })?.id
        
        // MARK: - Pastures
        let northwest = Pasture(name: "NW Pasture", acreage: 35, usableAcreage: 25, targetAcresPerHead: 3)
        let southwest = Pasture(name: "SW Pasture", acreage: 80, usableAcreage: 65, targetAcresPerHead: 3)
        let northeast = Pasture(name: "NE Pasture", acreage: 30, usableAcreage: 25, targetAcresPerHead: 3)
        let southeast = Pasture(name: "SE Pasture", acreage: 35, usableAcreage: 20, targetAcresPerHead: 3)
        let lower = Pasture(name: "Lower", acreage: 65, usableAcreage: 50, targetAcresPerHead: 3)
        let holding = Pasture(name: "Holding", acreage: 7, usableAcreage: 5, targetAcresPerHead: 3)
        let wallys = Pasture(name: "Wally's", acreage: 48, usableAcreage: 40, targetAcresPerHead: 3)
        
        context.insert(northwest)
        context.insert(southwest)
        context.insert(northeast)
        context.insert(southeast)
        context.insert(lower)
        context.insert(wallys)
        context.insert(holding)
        
        // MARK: - Animals (Matthew and Heather's herd)
        // Tags are green; tag numbers and dates come from the provided list.
        let jane = Animal(
            name: "Jane",
            tagNumber: "1",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2020, 1, 17),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: northwest,
            sex: .female
        )
        
        let rudy = Animal(
            name: "Rudy",
            tagNumber: "2",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2019, 10, 31),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: southwest,
            sex: .female
        )
        
        let roux = Animal(
            name: "Roux",
            tagNumber: "3",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2023, 3, 14),
            status: .active,
            sireAnimal: nil,
            damAnimal: rudy,
            pasture: northwest,
            sex: .female
        )
        
        // "spring 2020?" -> mid-spring placeholder
        let imogene = Animal(
            name: "Imogene",
            tagNumber: "4",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2020, 4, 15),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: northeast,
            sex: .female
        )
        
        let telly = Animal(
            name: "Telly",
            tagNumber: "5",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2023, 3, 19),
            status: .active,
            sireAnimal: nil,
            damAnimal: imogene,
            pasture: northeast,
            sex: .female
        )
        
        // "Jan/Feb 2024" -> Feb 1 placeholder
        let aelin = Animal(
            name: "Aelin",
            tagNumber: "6",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2024, 2, 1),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: northwest,
            sex: .female
        )
        
        let izzy = Animal(
            name: "ZZ (Izzy)",
            tagNumber: "7",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2024, 2, 18),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: southwest,
            sex: .female
        )
        
        let lottie = Animal(
            name: "Lottie",
            tagNumber: "8",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2025, 2, 27),
            status: .active,
            sireAnimal: nil,
            damAnimal: nil,
            pasture: northeast,
            sex: .female
        )
        
        // Calf listed with explicit tag number
        let limeGreen80 = Animal(
            name: "Lime green 80",
            tagNumber: "80",
            tagColorID: greenTagColorID,
            birthDate: makeDate(2025, 2, 28),
            status: .sold,
            sireAnimal: nil,
            damAnimal: telly,
            pasture: holding,
            sex: .male
        )
        
        let animals = [jane, rudy, roux, imogene, telly, aelin, izzy, lottie, limeGreen80]
        animals.forEach { animal in
            context.insert(animal)
            _ = animal.ensurePrimaryTagRecord()
        }
        
        // MARK: - Pregnancy Checks (dashboard alerts)
        context.insert(PregnancyCheck(date: daysAgo(30), result: .pregnant, technician: "Dr. Smith", animal: jane))
        context.insert(PregnancyCheck(date: daysAgo(29), result: .open,     technician: "Dr. Smith", animal: rudy))
        context.insert(PregnancyCheck(date: daysAgo(220), result: .pregnant, technician: "Dr. Lee", animal: imogene))
        context.insert(PregnancyCheck(date: daysAgo(61),  result: .unknown,  technician: "Dr. Lee", animal: telly))
        
        // MARK: - Health Records (dashboard alerts)
        context.insert(HealthRecord(date: daysAgo(10),  treatment: "Vaccination", notes: "Booster", animal: jane))
        context.insert(HealthRecord(date: daysAgo(210), treatment: "Deworming",   notes: nil,       animal: limeGreen80))
        context.insert(HealthRecord(date: daysAgo(45),  treatment: "Foot Trim",   notes: "Mild lesion LF", animal: roux))
        context.insert(HealthRecord(date: daysAgo(5),   treatment: "Antibiotic",  notes: "Metritis", animal: imogene))
        context.insert(HealthRecord(date: daysAgo(7),   treatment: "Vaccination", notes: nil,        animal: telly))
        
        // MARK: - Movement History (timeline)
        let movementData: [(Animal, String?, String, Int)] = [
            (jane,        "SE Pasture", "NW Pasture", 120),
            (jane,        "NW Pasture", "SE Pasture",   20),
            (rudy,        "NE Pasture", "SW Pasture", 45),
            (limeGreen80, nil,             "Holding",        200),
            (imogene,     "SE Pasture",  "NE Pasture", 75),
            (telly,       "NW Pasture", "SW Pasture", 30),
        ]
        
        for (animal, from, to, days) in movementData {
            context.insert(
                MovementRecord(
                    date: daysAgo(days),
                    fromPasture: from,
                    toPasture: to,
                    animal: animal
                )
            )
        }
        
        // MARK: - Status History (timeline + dashboard)
        let statusData: [(Animal, AnimalStatus, AnimalStatus, Int)] = [
            (limeGreen80, .active, .sold, 40),
        ]
        
        for (animal, oldStatus, newStatus, days) in statusData {
            context.insert(
                StatusRecord(
                    date: daysAgo(days),
                    oldStatus: oldStatus,
                    newStatus: newStatus,
                    animal: animal
                )
            )
        }
        
        do { try context.save() } catch { assertionFailure("Failed to save seeded data: \(error.localizedDescription)") }
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
        do { try context.save() } catch { assertionFailure("Failed to save seeded data: \(error.localizedDescription)") }
    }
    
    // MARK: - Helpers
    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }
    
    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
