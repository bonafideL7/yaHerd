import Foundation

struct AnimalEditorDraft {
    var name = ""
    var tagNumber = ""
    var tagColorID: UUID?
    var sex: Sex = .unknown
    var birthDate: Date = .now
    var status: AnimalStatus = .active
    var pastureID: UUID?
    var sireID: UUID?
    var sire = ""
    var damID: UUID?
    var dam = ""
    var distinguishingFeatures: [DistinguishingFeature] = []
    var saleDate: Date = .now
    var salePriceText = ""
    var reasonSold = ""
    var deathDate: Date = .now
    var causeOfDeath = ""
    var statusReferenceID: UUID?

    init() {}

    init(
        name: String = "",
        tagNumber: String = "",
        tagColorID: UUID? = nil,
        sex: Sex = .unknown,
        birthDate: Date = .now,
        status: AnimalStatus = .active,
        pastureID: UUID? = nil,
        sireID: UUID? = nil,
        sire: String = "",
        damID: UUID? = nil,
        dam: String = "",
        distinguishingFeatures: [DistinguishingFeature] = [],
        saleDate: Date = .now,
        salePriceText: String = "",
        reasonSold: String = "",
        deathDate: Date = .now,
        causeOfDeath: String = "",
        statusReferenceID: UUID? = nil
    ) {
        self.name = name
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.sex = sex
        self.birthDate = birthDate
        self.status = status
        self.pastureID = pastureID
        self.sireID = sireID
        self.sire = sire
        self.damID = damID
        self.dam = dam
        self.distinguishingFeatures = distinguishingFeatures
        self.saleDate = saleDate
        self.salePriceText = salePriceText
        self.reasonSold = reasonSold
        self.deathDate = deathDate
        self.causeOfDeath = causeOfDeath
        self.statusReferenceID = statusReferenceID
    }

    init(detail: AnimalDetailSnapshot) {
        name = detail.name
        tagNumber = detail.displayTagNumber
        tagColorID = detail.displayTagColorID
        sex = detail.sex
        birthDate = detail.birthDate
        status = detail.status
        pastureID = detail.pastureID
        sireID = detail.sireID
        sire = detail.sire ?? ""
        damID = detail.damID
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

    var normalizedReasonSold: String? {
        reasonSold.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedCauseOfDeath: String? {
        causeOfDeath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var cleanedDistinguishingFeatures: [DistinguishingFeature] {
        distinguishingFeatures
            .orderedDistinguishingFeatures
            .map { feature in
                DistinguishingFeature(
                    id: feature.id,
                    description: feature.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    order: feature.order
                )
            }
            .filter { !$0.description.isEmpty }
            .normalizedDistinguishingFeatureOrder
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
        try ValidationService.validateAnimal(
            ValidationService.AnimalValidationRules(
                birthDate: birthDate,
                status: status,
                saleDate: status == .sold ? saleDate : nil,
                deathDate: status == .dead ? deathDate : nil,
                animalID: nil,
                sireID: sireID,
                sireSex: nil,
                damID: damID,
                damSex: nil
            )
        )
        _ = try parsedSalePrice()
    }

    func hasChanges(comparedTo detail: AnimalDetailSnapshot) -> Bool {
        if normalizedName != detail.name { return true }
        if normalizedTagNumber != detail.displayTagNumber { return true }
        if tagColorID != detail.displayTagColorID { return true }
        if sex != detail.sex { return true }
        if birthDate != detail.birthDate { return true }
        if pastureID != detail.pastureID { return true }
        if sireID != detail.sireID { return true }
        if damID != detail.damID { return true }
        if cleanedDistinguishingFeatures != detail.distinguishingFeatures { return true }
        if status != detail.status { return true }
        if statusReferenceID != detail.statusReferenceID { return true }

        let draftSaleDate: Date? = status == .sold ? saleDate : nil
        let detailSaleDate: Date? = detail.status == .sold ? detail.saleDate : nil
        if draftSaleDate != detailSaleDate { return true }
        if normalizedReasonSold != detail.reasonSold { return true }

        let draftDeathDate: Date? = status == .dead ? deathDate : nil
        let detailDeathDate: Date? = detail.status == .dead ? detail.deathDate : nil
        if draftDeathDate != detailDeathDate { return true }
        if normalizedCauseOfDeath != detail.causeOfDeath { return true }

        let currentSalePriceText = detail.salePrice.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        } ?? ""

        return salePriceText.trimmingCharacters(in: .whitespacesAndNewlines) != currentSalePriceText
    }
}
