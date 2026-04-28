import SwiftData
import Foundation

/// Large sample seed reconciled to the pasture summary counts in `Pasture Animals.txt`.
/// Best-fit choices used for ambiguous lines:
/// - Pasture header totals are treated as the source of truth.
/// - Dead animals are excluded from the current snapshot.
/// - All living bulls are placed in SE Pasture as the current holding pasture.
/// - Animal 17 and calf W029 are placed in Holding Pasture.
/// - 2026 calves are kept as animals but left without a direct pasture assignment so pasture headcounts stay closer to the source summaries.
struct SampleLargeDataService {
    
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Animal>()
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return
        }
        
        let tagColorStore = TagColorLibraryStore()
        let colorIDs = Dictionary(uniqueKeysWithValues: tagColorStore.colors.map { ($0.name, $0.id) })
        
        let pastureDefinitions: [(String, Double, Double, Double)] = [
            ("NW Pasture", 35, 30, 3),
            ("SW Pasture", 30, 30, 3),
            ("Wally's Pasture", 25, 22, 3),
            ("LF Pasture", 35, 30, 3),
            ("NE Pasture", 30, 28, 3),
            ("SE Pasture", 15, 12, 3),
            ("Holding Pasture", 5, 3, 3)
        ]
        
        var pasturesByName: [String: Pasture] = [:]
        for (name, acreage, usableAcreage, targetAcresPerHead) in pastureDefinitions {
            let pasture = Pasture(
                name: name,
                acreage: acreage,
                usableAcreage: usableAcreage,
                targetAcresPerHead: targetAcresPerHead
            )
            context.insert(pasture)
            pasturesByName[name] = pasture
        }
        
        var animalsByKey: [String: Animal] = [:]
        
        for seed in adultSeeds {
            let animal = makeAnimal(
                from: seed,
                context: context,
                colorIDs: colorIDs,
                pasturesByName: pasturesByName,
                animalsByKey: animalsByKey
            )
            animalsByKey[seed.key] = animal
        }
        
        for seed in olderCalfSeeds {
            let animal = makeAnimal(
                from: seed,
                context: context,
                colorIDs: colorIDs,
                pasturesByName: pasturesByName,
                animalsByKey: animalsByKey
            )
            animalsByKey[seed.key] = animal
        }
        
        for seed in calf2026Seeds {
            let animal = makeAnimal(
                from: seed,
                context: context,
                colorIDs: colorIDs,
                pasturesByName: pasturesByName,
                animalsByKey: animalsByKey
            )
            animalsByKey[seed.key] = animal
        }
        
        for seed in (adultSeeds + olderCalfSeeds + calf2026Seeds) where seed.isPregnant {
            guard let animal = animalsByKey[seed.key] else { continue }
            
            let check = PregnancyCheck(
                date: pregnancyCheckDate(for: seed.pastureName ?? ""),
                result: .pregnant,
                technician: seed.isHeifer ? "Large sample seed - bred heifer" : "Large sample seed",
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimal: seed.pregnancySireKey.flatMap { animalsByKey[$0] },
                workingSession: nil,
                animal: animal
            )
            context.insert(check)
        }
        
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save SampleLargeDataService seed data: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    private static func makeAnimal(
        from seed: AnimalSeed,
        context: ModelContext,
        colorIDs: [String: UUID],
        pasturesByName: [String: Pasture],
        animalsByKey: [String: Animal]
    ) -> Animal {
        let animal = Animal(
            name: seed.name,
            tagNumber: seed.tagNumber,
            tagColorID: seed.tagColorName.flatMap { colorIDs[$0] },
            birthDate: seed.birthDate,
            status: .active,
            sireAnimal: seed.sireKey.flatMap { animalsByKey[$0] },
            damAnimal: seed.damKey.flatMap { animalsByKey[$0] },
            pasture: seed.pastureName.flatMap { pasturesByName[$0] },
            sex: seed.sex,
            distinguishingFeatures: seed.features.map { DistinguishingFeature(description: $0) }
        )
        context.insert(animal)
        
        if !seed.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let primaryTag = animal.ensurePrimaryTagRecord()
            primaryTag.assignedAt = seed.birthDate
        }
        
        for retiredTag in seed.retiredTags {
            let tag = AnimalTag(
                number: retiredTag.number,
                colorID: retiredTag.colorName.flatMap { colorIDs[$0] },
                isPrimary: false,
                isActive: false,
                assignedAt: seed.birthDate,
                removedAt: seed.birthDate.addingTimeInterval(60 * 60 * 24 * 365),
                animal: animal
            )
            animal.tags.append(tag)
            context.insert(tag)
        }
        
        for movement in seed.movements {
            let record = MovementRecord(
                date: movement.date,
                fromPasture: movement.fromPasture,
                toPasture: movement.toPasture,
                animal: animal
            )
            context.insert(record)
        }
        
        return animal
    }
    
    private static func pregnancyCheckDate(for pastureName: String) -> Date {
        switch pastureName {
        case "NW Pasture":
            return seedDate(2025, 9, 1)
        case "SW Pasture":
            return seedDate(2025, 9, 5)
        case "Wally's Pasture":
            return seedDate(2025, 9, 10)
        case "LF Pasture", "Holding Pasture":
            return seedDate(2025, 9, 15)
        case "NE Pasture":
            return seedDate(2025, 9, 20)
        default:
            return seedDate(2025, 9, 1)
        }
    }
    
    private static func seedDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
    
    private struct RetiredTagSeed {
        let number: String
        let colorName: String?
    }
    
    private struct MovementSeed {
        let date: Date
        let fromPasture: String?
        let toPasture: String?
    }
    
    private struct AnimalSeed {
        let key: String
        let name: String
        let tagNumber: String
        let tagColorName: String?
        let sex: Sex
        let pastureName: String?
        let birthDate: Date
        let retiredTags: [RetiredTagSeed]
        let features: [String]
        let isPregnant: Bool
        let isHeifer: Bool
        let movements: [MovementSeed]
        let sireKey: String?
        let damKey: String?
        let pregnancySireKey: String?
    }
    
    private static let adultSeeds: [AnimalSeed] = [
        AnimalSeed(
            key: "bull-nw-y66",
            name: "",
            tagNumber: "66",
            tagColorName: "Yellow",
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2020, 3, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 2, 26), fromPasture: "NW Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-sw-denali",
            name: "Denali",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2019, 4, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 3, 14), fromPasture: "SW Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-sw-ut",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2019, 5, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 3, 14), fromPasture: "SW Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-wally-74",
            name: "",
            tagNumber: "74",
            tagColorName: "White",
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2019, 2, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 4, 1), fromPasture: "Wally's Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-lf",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2019, 3, 30),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 4, 1), fromPasture: "LF Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-ne-irish",
            name: "Irish",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2020, 3, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 4, 1), fromPasture: "NE Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-ne-8",
            name: "Kramer",
            tagNumber: "8",
            tagColorName: "White",
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2020, 4, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 4, 1), fromPasture: "NE Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "bull-ne-16",
            name: "Chuck",
            tagNumber: "16",
            tagColorName: "White",
            sex: .male,
            pastureName: "SE Pasture",
            birthDate: seedDate(2020, 5, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 4, 1), fromPasture: "NE Pasture", toPasture: "SE Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-80",
            name: "",
            tagNumber: "80",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-81",
            name: "",
            tagNumber: "81",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-203",
            name: "",
            tagNumber: "203",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-345",
            name: "",
            tagNumber: "345",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-347",
            name: "",
            tagNumber: "347",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-354",
            name: "",
            tagNumber: "354",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-355",
            name: "",
            tagNumber: "355",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-356",
            name: "",
            tagNumber: "356",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 8),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-nw-y66"
        ),
        
        AnimalSeed(
            key: "nw-cow-361",
            name: "",
            tagNumber: "361",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-362",
            name: "",
            tagNumber: "362",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 10),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-nw-y66"
        ),
        
        AnimalSeed(
            key: "nw-cow-375",
            name: "",
            tagNumber: "375",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 11),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-405",
            name: "",
            tagNumber: "405",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-406",
            name: "",
            tagNumber: "406",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 1),
            retiredTags: [
                RetiredTagSeed(number: "586", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-407",
            name: "",
            tagNumber: "407",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 2),
            retiredTags: [],
            features: ["Bad right back leg"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-gr3",
            name: "Roux",
            tagNumber: "3",
            tagColorName: "Green",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 3),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-nw-y66"
        ),
        
        AnimalSeed(
            key: "nw-cow-ut2",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 4),
            retiredTags: [
                RetiredTagSeed(number: "2", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-ut219",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 5),
            retiredTags: [
                RetiredTagSeed(number: "219", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-cow-utmom",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2020, 1, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-heifer-blind",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2024, 4, 20),
            retiredTags: [],
            features: ["Blind"],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-021",
            name: "",
            tagNumber: "21",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 1, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-85",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 2, 4),
            retiredTags: [
                RetiredTagSeed(number: "85", colorName: "White")
            ],
            features: ["Stubby tail"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-86",
            name: "",
            tagNumber: "86",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 3, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-222",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 4, 10),
            retiredTags: [
                RetiredTagSeed(number: "222", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-230",
            name: "",
            tagNumber: "230",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 5, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-257",
            name: "",
            tagNumber: "257",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 6, 16),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-265",
            name: "",
            tagNumber: "265",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 7, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-296",
            name: "",
            tagNumber: "296",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 8, 22),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-302",
            name: "",
            tagNumber: "302",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 9, 25),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-307",
            name: "",
            tagNumber: "307",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 10, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-363",
            name: "",
            tagNumber: "363",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 11, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-364",
            name: "",
            tagNumber: "364",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 1, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-367",
            name: "",
            tagNumber: "367",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 2, 11),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-368",
            name: "",
            tagNumber: "368",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 3, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-369",
            name: "",
            tagNumber: "369",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 4, 17),
            retiredTags: [
                RetiredTagSeed(number: "308", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-374",
            name: "White Sox",
            tagNumber: "374",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 5, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-377",
            name: "",
            tagNumber: "377",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 6, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-381",
            name: "",
            tagNumber: "381",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 7, 26),
            retiredTags: [
                RetiredTagSeed(number: "036", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-386",
            name: "",
            tagNumber: "386",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 8, 3),
            retiredTags: [
                RetiredTagSeed(number: "024", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-387",
            name: "",
            tagNumber: "387",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 9, 6),
            retiredTags: [
                RetiredTagSeed(number: "022", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-388",
            name: "",
            tagNumber: "388",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 10, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-389",
            name: "",
            tagNumber: "389",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 11, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-390",
            name: "",
            tagNumber: "390",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 1, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-391",
            name: "",
            tagNumber: "391",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 2, 18),
            retiredTags: [
                RetiredTagSeed(number: "023", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-392",
            name: "",
            tagNumber: "392",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 3, 21),
            retiredTags: [
                RetiredTagSeed(number: "026", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-393",
            name: "",
            tagNumber: "393",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 4, 24),
            retiredTags: [
                RetiredTagSeed(number: "003", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-394",
            name: "",
            tagNumber: "394",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 5, 1),
            retiredTags: [
                RetiredTagSeed(number: "011", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-gr1",
            name: "Jane",
            tagNumber: "1",
            tagColorName: "Green",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 6, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-gr2",
            name: "Rudy",
            tagNumber: "2",
            tagColorName: "Green",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 7, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-gr5",
            name: "Telly",
            tagNumber: "5",
            tagColorName: "Green",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 8, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-w047",
            name: "",
            tagNumber: "47",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2021, 9, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-blank",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2022, 10, 16),
            retiredTags: [
                RetiredTagSeed(number: "198", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-utwhite",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2019, 11, 19),
            retiredTags: [],
            features: ["White right side of udder"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-cow-utold",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2020, 1, 22),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-67",
            name: "",
            tagNumber: "67",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 1, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-68",
            name: "",
            tagNumber: "68",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 2, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-83",
            name: "",
            tagNumber: "83",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 3, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-020",
            name: "",
            tagNumber: "20",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 4, 7),
            retiredTags: [
                RetiredTagSeed(number: "91", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-227",
            name: "",
            tagNumber: "227",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 5, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-287",
            name: "",
            tagNumber: "287",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 6, 11),
            retiredTags: [],
            features: ["Limping 4/3"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-352",
            name: "",
            tagNumber: "352",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 7, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-365",
            name: "",
            tagNumber: "365",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 8, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-366",
            name: "",
            tagNumber: "366",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 9, 17),
            retiredTags: [
                RetiredTagSeed(number: "16", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-372",
            name: "",
            tagNumber: "372",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 10, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-379",
            name: "",
            tagNumber: "379",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 11, 21),
            retiredTags: [
                RetiredTagSeed(number: "46", colorName: "White")
            ],
            features: ["Bad eye"],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-wally-74"
        ),
        
        AnimalSeed(
            key: "wa-cow-380",
            name: "",
            tagNumber: "380",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 1, 23),
            retiredTags: [
                RetiredTagSeed(number: "47", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-385",
            name: "",
            tagNumber: "385",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 2, 25),
            retiredTags: [
                RetiredTagSeed(number: "40", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-cow-395",
            name: "",
            tagNumber: "395",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2019, 3, 2),
            retiredTags: [
                RetiredTagSeed(number: "14", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-gr6",
            name: "Aelin",
            tagNumber: "6",
            tagColorName: "Green",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 4, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-gr7",
            name: "ZZ Top",
            tagNumber: "7",
            tagColorName: "Green",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 5, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-gr8",
            name: "Lottie",
            tagNumber: "8",
            tagColorName: "Green",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 6, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-403",
            name: "",
            tagNumber: "403",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 7, 10),
            retiredTags: [
                RetiredTagSeed(number: "72", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-wally-74"
        ),
        
        AnimalSeed(
            key: "wa-heifer-426",
            name: "",
            tagNumber: "426",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 8, 12),
            retiredTags: [
                RetiredTagSeed(number: "39", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-wally-74"
        ),
        
        AnimalSeed(
            key: "wa-heifer-427",
            name: "",
            tagNumber: "427",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 9, 14),
            retiredTags: [
                RetiredTagSeed(number: "41", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-wally-74"
        ),
        
        AnimalSeed(
            key: "wa-heifer-424",
            name: "",
            tagNumber: "424",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 10, 16),
            retiredTags: [
                RetiredTagSeed(number: "17", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-423",
            name: "",
            tagNumber: "423",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 11, 18),
            retiredTags: [
                RetiredTagSeed(number: "43", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-425",
            name: "",
            tagNumber: "425",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 1, 20),
            retiredTags: [
                RetiredTagSeed(number: "47", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-heifer-422",
            name: "",
            tagNumber: "422",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2024, 2, 22),
            retiredTags: [
                RetiredTagSeed(number: "50", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w05",
            name: "",
            tagNumber: "5",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 1, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w06",
            name: "",
            tagNumber: "6",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 2, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w011",
            name: "",
            tagNumber: "11",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 3, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w014",
            name: "",
            tagNumber: "14",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 4, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w015",
            name: "",
            tagNumber: "15",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 5, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w018",
            name: "",
            tagNumber: "18",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 6, 11),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w87",
            name: "",
            tagNumber: "87",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 7, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w95",
            name: "",
            tagNumber: "95",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 8, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w226",
            name: "",
            tagNumber: "226",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 9, 17),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w271",
            name: "",
            tagNumber: "271",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 10, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w323",
            name: "",
            tagNumber: "323",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 11, 21),
            retiredTags: [],
            features: ["White on udder and up on belly"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w328",
            name: "",
            tagNumber: "328",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 1, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w370",
            name: "",
            tagNumber: "370",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 2, 25),
            retiredTags: [],
            features: ["Knot on right jaw"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w376",
            name: "",
            tagNumber: "376",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 3, 27),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w408",
            name: "",
            tagNumber: "408",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 4, 2),
            retiredTags: [
                RetiredTagSeed(number: "122", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w410",
            name: "",
            tagNumber: "410",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 5, 4),
            retiredTags: [
                RetiredTagSeed(number: "120", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w411",
            name: "",
            tagNumber: "411",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 6, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w412",
            name: "",
            tagNumber: "412",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 7, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w413",
            name: "",
            tagNumber: "413",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 8, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w414",
            name: "",
            tagNumber: "414",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 9, 12),
            retiredTags: [
                RetiredTagSeed(number: "304", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w415",
            name: "",
            tagNumber: "415",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 10, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w416",
            name: "",
            tagNumber: "416",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 11, 16),
            retiredTags: [
                RetiredTagSeed(number: "116", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w417",
            name: "",
            tagNumber: "417",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 1, 18),
            retiredTags: [
                RetiredTagSeed(number: "110", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w418",
            name: "",
            tagNumber: "418",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 2, 20),
            retiredTags: [
                RetiredTagSeed(number: "118", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w420",
            name: "",
            tagNumber: "420",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 3, 22),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w421",
            name: "",
            tagNumber: "421",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2019, 4, 24),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-utmom",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2020, 5, 26),
            retiredTags: [],
            features: ["Right ear frozen"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w429",
            name: "",
            tagNumber: "429",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2021, 6, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w430",
            name: "",
            tagNumber: "430",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2022, 7, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-cow-w431",
            name: "",
            tagNumber: "431",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2023, 8, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-heifer-w017",
            name: "",
            tagNumber: "17",
            tagColorName: "White",
            sex: .female,
            pastureName: "Holding Pasture",
            birthDate: seedDate(2024, 4, 10),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [
                MovementSeed(date: seedDate(2026, 1, 15), fromPasture: "LF Pasture", toPasture: "Holding Pasture")
            ],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-lf"
        ),
        
        AnimalSeed(
            key: "lf-heifer-w409",
            name: "",
            tagNumber: "409",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2024, 5, 11),
            retiredTags: [
                RetiredTagSeed(number: "264", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-lf"
        ),
        
        AnimalSeed(
            key: "lf-heifer-w419",
            name: "",
            tagNumber: "419",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2024, 6, 12),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-lf"
        ),
        
        AnimalSeed(
            key: "lf-heifer-w428",
            name: "",
            tagNumber: "428",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2024, 7, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-ut59",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 1, 1),
            retiredTags: [
                RetiredTagSeed(number: "59", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-78",
            name: "",
            tagNumber: "78",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2020, 2, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-96",
            name: "",
            tagNumber: "96",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2021, 3, 7),
            retiredTags: [
                RetiredTagSeed(number: "26", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-97",
            name: "",
            tagNumber: "97",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2022, 4, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-99",
            name: "",
            tagNumber: "99",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2023, 5, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-023",
            name: "",
            tagNumber: "23",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 6, 16),
            retiredTags: [
                RetiredTagSeed(number: "165", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-216",
            name: "",
            tagNumber: "216",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2020, 7, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-025",
            name: "",
            tagNumber: "25",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2021, 8, 22),
            retiredTags: [
                RetiredTagSeed(number: "243", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-247",
            name: "",
            tagNumber: "247",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2022, 9, 25),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-252",
            name: "",
            tagNumber: "252",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2023, 10, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-024",
            name: "",
            tagNumber: "24",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 11, 4),
            retiredTags: [
                RetiredTagSeed(number: "254", colorName: "White"),
                RetiredTagSeed(number: "185", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-314",
            name: "",
            tagNumber: "314",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2020, 1, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-319",
            name: "",
            tagNumber: "319",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2021, 2, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-349",
            name: "",
            tagNumber: "349",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2022, 3, 13),
            retiredTags: [
                RetiredTagSeed(number: "28", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-358",
            name: "",
            tagNumber: "358",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2023, 4, 16),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-ne-irish"
        ),
        
        AnimalSeed(
            key: "ne-cow-373",
            name: "",
            tagNumber: "373",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 5, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-378",
            name: "",
            tagNumber: "378",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2020, 6, 22),
            retiredTags: [
                RetiredTagSeed(number: "187", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-397",
            name: "",
            tagNumber: "397",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2021, 7, 25),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-399",
            name: "",
            tagNumber: "399",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2022, 8, 1),
            retiredTags: [],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-ne-irish"
        ),
        
        AnimalSeed(
            key: "ne-cow-400",
            name: "",
            tagNumber: "400",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2023, 9, 4),
            retiredTags: [
                RetiredTagSeed(number: "23", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-ne-irish"
        ),
        
        AnimalSeed(
            key: "ne-cow-401",
            name: "",
            tagNumber: "401",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 10, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-402",
            name: "",
            tagNumber: "402",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2020, 11, 10),
            retiredTags: [
                RetiredTagSeed(number: "69", colorName: "Purple")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-579",
            name: "",
            tagNumber: "579",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2021, 1, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-584",
            name: "",
            tagNumber: "584",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2022, 2, 16),
            retiredTags: [
                RetiredTagSeed(number: "24", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-gr4",
            name: "Imogene",
            tagNumber: "4",
            tagColorName: "Green",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2023, 3, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-cow-w71",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2019, 4, 22),
            retiredTags: [
                RetiredTagSeed(number: "71", colorName: "White")
            ],
            features: ["Short tail"],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-heifer-orange2",
            name: "",
            tagNumber: "2",
            tagColorName: "Orange",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2024, 5, 12),
            retiredTags: [
                RetiredTagSeed(number: "25", colorName: "White")
            ],
            features: [],
            isPregnant: true,
            isHeifer: true,
            movements: [],
            sireKey: nil,
            damKey: nil,
            pregnancySireKey: "bull-ne-irish"
        )
    ]
    
    private static let olderCalfSeeds: [AnimalSeed] = [
        AnimalSeed(
            key: "nw-older-w031",
            name: "",
            tagNumber: "31",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 9, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-362",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-w034",
            name: "",
            tagNumber: "34",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-80",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-w038",
            name: "",
            tagNumber: "38",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 12),
            retiredTags: [
                RetiredTagSeed(number: "203", colorName: "White")
            ],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-203",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-b130",
            name: "",
            tagNumber: "130",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 9, 25),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-354",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-b132",
            name: "",
            tagNumber: "132",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-utmom",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-utbigboy",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 9, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-355",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-utboy1",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-356",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-utboy2",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-361",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-utheifer",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 10, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-81",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-older-ut219boy",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "NW Pasture",
            birthDate: seedDate(2025, 11, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-ut219",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-b114",
            name: "",
            tagNumber: "114",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-394",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-w013",
            name: "",
            tagNumber: "13",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-021",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-w014",
            name: "",
            tagNumber: "14",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 24),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-85",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-w034",
            name: "",
            tagNumber: "34",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-257",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-1",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 11),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-2",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-3",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-4",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-5",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-ut123456-6",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 9, 16),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-307",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-heifer-1",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 16),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-368",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-heifer-2",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 17),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-368",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-heifer-3",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-368",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-heifer-4",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .female,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 10, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-368",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-older-extra",
            name: "",
            tagNumber: "",
            tagColorName: "White",
            sex: .male,
            pastureName: "SW Pasture",
            birthDate: seedDate(2025, 11, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-utold",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-b143",
            name: "",
            tagNumber: "143",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 9, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-372",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-b154",
            name: "",
            tagNumber: "154",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 10, 4),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-365",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-w019",
            name: "",
            tagNumber: "19",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 9, 19),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-020",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-w049",
            name: "",
            tagNumber: "49",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 10, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-380",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-w061",
            name: "",
            tagNumber: "61",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 10, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-385",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-older-w075",
            name: "",
            tagNumber: "75",
            tagColorName: "White",
            sex: .female,
            pastureName: "Wally's Pasture",
            birthDate: seedDate(2025, 11, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-395",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-older-w77",
            name: "",
            tagNumber: "77",
            tagColorName: "White",
            sex: .female,
            pastureName: "LF Pasture",
            birthDate: seedDate(2025, 10, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w011",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-older-b155",
            name: "",
            tagNumber: "155",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "LF Pasture",
            birthDate: seedDate(2025, 9, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w95",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-older-b156",
            name: "",
            tagNumber: "156",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "LF Pasture",
            birthDate: seedDate(2025, 10, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w421",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-w023",
            name: "",
            tagNumber: "23",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-400",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-w024",
            name: "",
            tagNumber: "24",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-584",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-w026",
            name: "",
            tagNumber: "26",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 24),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-96",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-w028",
            name: "",
            tagNumber: "28",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 30),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-349",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-w036",
            name: "",
            tagNumber: "36",
            tagColorName: "White",
            sex: .female,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 10, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-252",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-b123",
            name: "",
            tagNumber: "123",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-319",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-b126",
            name: "",
            tagNumber: "126",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 9, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-402",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-b128",
            name: "",
            tagNumber: "128",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 10, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-397",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-older-b129",
            name: "",
            tagNumber: "129",
            tagColorName: "Blue",
            sex: .male,
            pastureName: "NE Pasture",
            birthDate: seedDate(2025, 10, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-025",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "hold-w029",
            name: "",
            tagNumber: "29",
            tagColorName: "White",
            sex: .female,
            pastureName: "Holding Pasture",
            birthDate: seedDate(2025, 10, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [
                MovementSeed(date: seedDate(2026, 2, 8), fromPasture: "NE Pasture", toPasture: "Holding Pasture")
            ],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-401",
            pregnancySireKey: nil
        )
    ]
    
    private static let calf2026Seeds: [AnimalSeed] = [
        AnimalSeed(
            key: "nw-new-80",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 29),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-80",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-new-406",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-406",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-new-405",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 16),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-405",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-new-347",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 26),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-347",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-new-407",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-407",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "nw-new-gr3",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 17),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-nw-y66",
            damKey: "nw-cow-gr3",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-257",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-257",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-381",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 30),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-381",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-296",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-296",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-364",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-364",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-265",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 1),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-265",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-utwhite",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 2),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-utwhite",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-047",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-w047",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-021",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 10),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-021",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-386",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 18),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-386",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-374",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 22),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-374",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-gr2",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-gr2",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-377",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-377",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-302",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-302",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-utold",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-utold",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-85",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-85",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-blank",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 16),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-blank",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-230",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-230",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "sw-new-369",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 31),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-sw-denali",
            damKey: "sw-cow-369",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-67",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-67",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-68",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 17),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-68",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-227",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 6),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-227",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-287",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-287",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-366",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-366",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-379",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 29),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-379",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "wa-new-395",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 31),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-wally-74",
            damKey: "wa-cow-395",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-328",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 23),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w328",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-412",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 5),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w412",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-271",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w271",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-408",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 8),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w408",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-95",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 11),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w95",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-420",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 12),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w420",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-413",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 13),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w413",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-416",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 14),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w416",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-226",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w226",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-415",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 21),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w415",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-376",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 22),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w376",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-370",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 3, 29),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w370",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-418",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w418",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "lf-new-414",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 4, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-lf",
            damKey: "lf-cow-w414",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-216",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 3),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-216",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-579",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 7),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-579",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-023",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 9),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-023",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-gr4",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .male,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 15),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-gr4",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-378",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 1, 20),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-378",
            pregnancySireKey: nil
        ),
        
        AnimalSeed(
            key: "ne-new-99",
            name: "",
            tagNumber: "",
            tagColorName: nil,
            sex: .female,
            pastureName: nil,
            birthDate: seedDate(2026, 2, 28),
            retiredTags: [],
            features: [],
            isPregnant: false,
            isHeifer: false,
            movements: [],
            sireKey: "bull-ne-irish",
            damKey: "ne-cow-99",
            pregnancySireKey: nil
        )
    ]
}
