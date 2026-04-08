import SwiftData
import Foundation

struct SampleLargeDataService {

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Animal>()
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return
        }

        let tagColorStore = TagColorLibraryStore()
        let whiteTagColorID = tagColorStore.colors.first(where: { $0.name == "White" })?.id
        let greenTagColorID = tagColorStore.colors.first(where: { $0.name == "Green" })?.id
        let blueTagColorID = tagColorStore.colors.first(where: { $0.name == "Blue" })?.id

        let pasture = Pasture(name: "Wally's Pasture", acreage: 40)
        context.insert(pasture)

        let bull74 = Animal(
            name: "Wally's Bull",
            tagNumber: "74",
            tagColorID: whiteTagColorID,
            birthDate: makeDate(2021, 2, 11),
            status: .active,
            sire: nil,
            dam: nil,
            pasture: pasture,
            sex: .male
        )
        context.insert(bull74)
        _ = bull74.ensurePrimaryTagRecord()

        @discardableResult
        func makeAnimal(
            tagNumber: String,
            colorID: UUID?,
            sex: Sex,
            birthDate: Date,
            pasture: Pasture,
            name: String = "",
            status: AnimalStatus = .active,
            dam: Animal? = nil,
            sire: Animal? = nil,
            oldTag: (number: String, colorID: UUID?)? = nil,
            featureDescriptions: [String] = [],
            pregDate: Date? = nil,
            isHeifer: Bool = false,
            statusChangeDate: Date? = nil
        ) -> Animal {
            let animal = Animal(
                name: name,
                tagNumber: tagNumber,
                tagColorID: colorID,
                birthDate: birthDate,
                status: status,
                sire: sire?.displayTagNumber,
                dam: dam?.displayTagNumber,
                pasture: pasture,
                sex: sex,
                distinguishingFeatures: featureDescriptions.map { DistinguishingFeature(description: $0) }
            )
            context.insert(animal)

            if !tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let primaryTag = animal.ensurePrimaryTagRecord()
                primaryTag.assignedAt = birthDate
            }

            if let oldTag {
                let retiredTag = AnimalTag(
                    number: oldTag.number,
                    colorID: oldTag.colorID,
                    isPrimary: false,
                    isActive: false,
                    assignedAt: Calendar.current.date(byAdding: .month, value: -8, to: birthDate) ?? birthDate,
                    removedAt: Calendar.current.date(byAdding: .month, value: -1, to: birthDate) ?? birthDate,
                    animal: animal
                )
                animal.tags.append(retiredTag)
            }

            if let pregDate {
                let check = PregnancyCheck(
                    date: pregDate,
                    result: .pregnant,
                    technician: isHeifer ? "Sample seed - bred heifer" : "Sample seed",
                    sireAnimal: sire,
                    workingSession: nil,
                    animal: animal
                )
                context.insert(check)
            }

            if let statusChangeDate, status != .active {
                let record = StatusRecord(
                    date: statusChangeDate,
                    oldStatus: .active,
                    newStatus: status,
                    animal: animal
                )
                context.insert(record)
            }

            return animal
        }

        let pregnancyCheckDate = makeDate(2026, 1, 15)

        let femaleBirths: [String: Date] = [
            "67": makeDate(2022, 3, 12),
            "68": makeDate(2021, 4, 24),
            "83": makeDate(2021, 3, 16),
            "020": makeDate(2020, 9, 8),
            "227": makeDate(2021, 2, 9),
            "287": makeDate(2021, 5, 5),
            "352": makeDate(2020, 8, 28),
            "365": makeDate(2021, 1, 14),
            "366": makeDate(2020, 10, 22),
            "372": makeDate(2020, 9, 17),
            "379": makeDate(2020, 10, 3),
            "380": makeDate(2021, 4, 2),
            "385": makeDate(2020, 9, 29),
            "395": makeDate(2021, 2, 23),
            "403": makeDate(2024, 3, 11),
            "426": makeDate(2024, 4, 19),
            "427": makeDate(2024, 2, 27),
            "6": makeDate(2024, 5, 1),
            "7": makeDate(2024, 4, 12),
            "8": makeDate(2024, 5, 19),
            "424": makeDate(2024, 3, 8),
            "423": makeDate(2024, 4, 6),
            "046": makeDate(2024, 3, 2),
            "425": makeDate(2024, 5, 7),
            "422": makeDate(2024, 4, 28)
        ]

        let mom68 = makeAnimal(tagNumber: "68", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["68"]!, pasture: pasture, sire: bull74)
        let mom227 = makeAnimal(tagNumber: "227", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["227"]!, pasture: pasture, sire: bull74)

        _ = makeAnimal(tagNumber: "67", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["67"]!, pasture: pasture, pregDate: pregnancyCheckDate)
        _ = makeAnimal(tagNumber: "83", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["83"]!, pasture: pasture)
        _ = makeAnimal(tagNumber: "020", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["020"]!, pasture: pasture, oldTag: ("91", whiteTagColorID))
        _ = makeAnimal(tagNumber: "287", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["287"]!, pasture: pasture, pregDate: pregnancyCheckDate)
        _ = makeAnimal(tagNumber: "352", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["352"]!, pasture: pasture)
        _ = makeAnimal(tagNumber: "365", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["365"]!, pasture: pasture)
        _ = makeAnimal(tagNumber: "366", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["366"]!, pasture: pasture, oldTag: ("16", whiteTagColorID), pregDate: pregnancyCheckDate)
        _ = makeAnimal(tagNumber: "372", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["372"]!, pasture: pasture, oldTag: ("143", blueTagColorID))
        _ = makeAnimal(tagNumber: "379", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["379"]!, pasture: pasture, oldTag: ("46", whiteTagColorID), featureDescriptions: ["Bad eye"], pregDate: pregnancyCheckDate)
        _ = makeAnimal(tagNumber: "380", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["380"]!, pasture: pasture, oldTag: ("047", whiteTagColorID))
        _ = makeAnimal(tagNumber: "385", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["385"]!, pasture: pasture, oldTag: ("040", whiteTagColorID))
        _ = makeAnimal(tagNumber: "395", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["395"]!, pasture: pasture, oldTag: ("014", whiteTagColorID), pregDate: pregnancyCheckDate)
        _ = makeAnimal(tagNumber: "403", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["403"]!, pasture: pasture, oldTag: ("072", whiteTagColorID), pregDate: pregnancyCheckDate, isHeifer: true)
        _ = makeAnimal(tagNumber: "426", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["426"]!, pasture: pasture, oldTag: ("039", whiteTagColorID), pregDate: pregnancyCheckDate, isHeifer: true)
        _ = makeAnimal(tagNumber: "427", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["427"]!, pasture: pasture, oldTag: ("041", whiteTagColorID), pregDate: pregnancyCheckDate, isHeifer: true)

        _ = makeAnimal(tagNumber: "6", colorID: greenTagColorID, sex: .female, birthDate: femaleBirths["6"]!, pasture: pasture, name: "Aelin")
        _ = makeAnimal(tagNumber: "7", colorID: greenTagColorID, sex: .female, birthDate: femaleBirths["7"]!, pasture: pasture, name: "ZZ Top")
        _ = makeAnimal(tagNumber: "8", colorID: greenTagColorID, sex: .female, birthDate: femaleBirths["8"]!, pasture: pasture, name: "Lottie")

        _ = makeAnimal(tagNumber: "424", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["424"]!, pasture: pasture, oldTag: ("017", whiteTagColorID))
        _ = makeAnimal(tagNumber: "423", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["423"]!, pasture: pasture, oldTag: ("043", whiteTagColorID))
        _ = makeAnimal(
            tagNumber: "046",
            colorID: whiteTagColorID,
            sex: .female,
            birthDate: femaleBirths["046"]!,
            pasture: pasture,
            status: .dead,
            featureDescriptions: ["Dead in pond"],
            statusChangeDate: makeDate(2026, 1, 27)
        )
        _ = makeAnimal(tagNumber: "425", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["425"]!, pasture: pasture, sire: bull74, oldTag: ("047", whiteTagColorID))
        _ = makeAnimal(tagNumber: "422", colorID: whiteTagColorID, sex: .female, birthDate: femaleBirths["422"]!, pasture: pasture, sire: bull74, oldTag: ("050", whiteTagColorID))

        let fallBabies: [(String, UUID?, Sex, Date)] = [
            ("143", blueTagColorID, .male, makeDate(2025, 9, 14)),
            ("154", blueTagColorID, .male, makeDate(2025, 10, 3)),
            ("019", whiteTagColorID, .female, makeDate(2025, 9, 29)),
            ("049", whiteTagColorID, .female, makeDate(2025, 10, 18)),
            ("061", whiteTagColorID, .female, makeDate(2025, 11, 7)),
            ("075", whiteTagColorID, .female, makeDate(2025, 11, 21))
        ]

        for calf in fallBabies {
            _ = makeAnimal(
                tagNumber: calf.0,
                colorID: calf.1,
                sex: calf.2,
                birthDate: calf.3,
                pasture: pasture,
                sire: bull74
            )
        }

        _ = makeAnimal(
            tagNumber: "",
            colorID: nil,
            sex: .unknown,
            birthDate: makeDate(2026, 3, 17),
            pasture: pasture,
            name: "Calf of 68",
            dam: mom68,
            sire: bull74
        )

        _ = makeAnimal(
            tagNumber: "",
            colorID: nil,
            sex: .unknown,
            birthDate: makeDate(2026, 3, 6),
            pasture: pasture,
            dam: mom227,
            sire: bull74
        )

        _ = makeAnimal(
            tagNumber: "",
            colorID: nil,
            sex: .male,
            birthDate: makeDate(2025, 10, 12),
            pasture: pasture,
            status: .dead,
            statusChangeDate: makeDate(2026, 1, 27)
        )

        _ = makeAnimal(
            tagNumber: "",
            colorID: nil,
            sex: .female,
            birthDate: makeDate(2025, 10, 25),
            pasture: pasture,
            status: .dead,
            statusChangeDate: makeDate(2026, 1, 27)
        )

        _ = makeAnimal(
            tagNumber: "",
            colorID: nil,
            sex: .female,
            birthDate: makeDate(2025, 9, 8),
            pasture: pasture,
            status: .dead,
            statusChangeDate: makeDate(2025, 11, 15)
        )

        try? context.save()
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
