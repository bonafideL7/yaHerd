import Foundation

struct AnimalEditorDraft {
    var name = ""
    var tagNumber = ""
    var tagColorID: UUID?
    var sex: Sex = .unknown
    var birthDate: Date = .now
    var status: AnimalStatus = .active
    var pastureID: UUID?
    var sire = ""
    var dam = ""
    var distinguishingFeatures: [DistinguishingFeature] = []
    var saleDate: Date = .now
    var salePriceText = ""
    var reasonSold = ""
    var deathDate: Date = .now
    var causeOfDeath = ""
    var statusReferenceID: UUID?

    init() {}

    init(detail: AnimalDetailSnapshot) {
        name = detail.name
        tagNumber = detail.displayTagNumber
        tagColorID = detail.displayTagColorID
        sex = detail.sex
        birthDate = detail.birthDate
        status = detail.status
        pastureID = detail.pastureID
        sire = detail.sire ?? ""
        dam = detail.dam ?? ""
        distinguishingFeatures = detail.distinguishingFeatures
        saleDate = detail.saleDate ?? .now
        salePriceText = detail.salePrice.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        } ?? ""
        reasonSold = detail.reasonSold ?? ""
        deathDate = detail.deathDate ?? .now
        causeOfDeath = detail.causeOfDeath ?? ""
        statusReferenceID = detail.statusReferenceID
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTagNumber: String {
        tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedSire: String? {
        sire.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedDam: String? {
        dam.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedReasonSold: String? {
        reasonSold.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedCauseOfDeath: String? {
        causeOfDeath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var cleanedDistinguishingFeatures: [DistinguishingFeature] {
        distinguishingFeatures
            .map {
                DistinguishingFeature(
                    id: $0.id,
                    description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.description.isEmpty }
    }

    func parsedSalePrice() throws -> Double? {
        let trimmed = salePriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed) else {
            throw AnimalValidationError.invalidSalePrice
        }
        return value
    }

    func validate() throws {
        try ValidationService.validateAnimal(birthDate: birthDate)
        _ = try parsedSalePrice()
    }

    func hasChanges(comparedTo detail: AnimalDetailSnapshot) -> Bool {
        if normalizedName != detail.name { return true }
        if normalizedTagNumber != detail.displayTagNumber { return true }
        if tagColorID != detail.displayTagColorID { return true }
        if sex != detail.sex { return true }
        if birthDate != detail.birthDate { return true }
        if pastureID != detail.pastureID { return true }
        if normalizedSire != detail.sire { return true }
        if normalizedDam != detail.dam { return true }
        if cleanedDistinguishingFeatures != detail.distinguishingFeatures { return true }
        if status != detail.status { return true }
        if statusReferenceID != detail.statusReferenceID { return true }
        if saleDate != (detail.saleDate ?? .now) { return true }
        if normalizedReasonSold != detail.reasonSold { return true }
        if deathDate != (detail.deathDate ?? .now) { return true }
        if normalizedCauseOfDeath != detail.causeOfDeath { return true }

        let currentSalePriceText = detail.salePrice.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        } ?? ""

        return salePriceText.trimmingCharacters(in: .whitespacesAndNewlines) != currentSalePriceText
    }
}
