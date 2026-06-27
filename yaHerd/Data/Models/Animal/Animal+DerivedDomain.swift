import Foundation

extension Animal {
    var ageInMonths: Int {
        AnimalAgeFormatter.ageInMonths(from: birthDate)
    }

    var animalType: AnimalType {
        AnimalTypeClassifier.classify(
            sex: sex,
            birthDate: birthDate,
            hasMaternalOffspring: hasOffspring,
            hasCastrationOrBandingRecord: hasCastrationOrBandingRecord
        )
    }

    var hasOffspring: Bool {
        !maternalOffspring.isEmpty
    }

    var offspringCount: Int {
        maternalOffspring.count
    }

    var hasCastrationOrBandingRecord: Bool {
        healthRecords.contains { record in
            AnimalTypeClassifier.isCastrationOrBandingTreatment(record.treatment)
        }
    }

    var age: String {
        AnimalAgeFormatter.string(from: birthDate, style: .standard)
    }
}
