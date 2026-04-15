//
//  SwiftDataModel.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//
import SwiftData
import Foundation

@Model
final class Animal {
    @Attribute(.unique) var publicID: UUID
    var name: String
    var tagNumber: String
    var tagColorID: UUID?
    var sex: Sex?
    var birthDate: Date
    var status: AnimalStatus
    var saleDate: Date?
    var salePrice: Double?
    var reasonSold: String?
    var deathDate: Date?
    var causeOfDeath: String?
    var statusReferenceID: UUID?
    var isSoftDeleted: Bool
    var softDeletedAt: Date?
    var softDeleteReason: String?
    var locationRaw: AnimalLocation? = AnimalLocation.pasture
    var distinguishingFeatures: [DistinguishingFeature] = []

    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []
    @Relationship(deleteRule: .nullify) var activeWorkingSession: WorkingSession?
    @Relationship(deleteRule: .nullify) var sireAnimal: Animal?
    @Relationship(deleteRule: .nullify) var damAnimal: Animal?
    @Relationship var pasture: Pasture?
    @Relationship(deleteRule: .cascade, inverse: \AnimalTag.animal) var tags: [AnimalTag] = []

    var location: AnimalLocation {
        get { locationRaw ?? .pasture }
        set { locationRaw = newValue }
    }

    var isActiveInHerd: Bool {
        status == .active && !isSoftDeleted
    }

    var isVisibleRecord: Bool {
        !isSoftDeleted
    }

    var isArchived: Bool {
        isSoftDeleted
    }

    var archivedAt: Date? {
        softDeletedAt
    }

    var archiveReason: String? {
        softDeleteReason
    }

    var activeTags: [AnimalTag] {
        tags
            .filter { $0.isActive }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                if lhs.assignedAt != rhs.assignedAt { return lhs.assignedAt > rhs.assignedAt }
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedAscending
            }
    }

    var inactiveTags: [AnimalTag] {
        tags
            .filter { !$0.isActive }
            .sorted { lhs, rhs in
                let leftDate = lhs.removedAt ?? lhs.assignedAt
                let rightDate = rhs.removedAt ?? rhs.assignedAt
                return leftDate > rightDate
            }
    }

    var primaryTag: AnimalTag? {
        activeTags.first(where: { $0.isPrimary }) ?? activeTags.first
    }

    var secondaryActiveTags: [AnimalTag] {
        activeTags.filter { tag in
            guard let primaryTag else { return true }
            return tag.publicID != primaryTag.publicID
        }
    }

    var displayTagNumber: String {
        primaryTag?.normalizedNumber ?? tagNumber
    }

    var displayTagColorID: UUID? {
        primaryTag?.colorID ?? tagColorID
    }

    func syncPrimaryTagFieldsFromTags() {
        tagNumber = primaryTag?.normalizedNumber ?? ""
        tagColorID = primaryTag?.colorID
    }

    func ensurePrimaryTagRecord() -> AnimalTag {
        if let primaryTag {
            if primaryTag.normalizedNumber != tagNumber {
                primaryTag.number = tagNumber
            }
            if primaryTag.colorID != tagColorID {
                primaryTag.colorID = tagColorID
            }
            if !primaryTag.isActive {
                primaryTag.isActive = true
                primaryTag.removedAt = nil
            }
            primaryTag.isPrimary = true
            return primaryTag
        }

        let tag = AnimalTag(
            number: tagNumber,
            colorID: tagColorID,
            isPrimary: true,
            isActive: true,
            assignedAt: .now,
            animal: self
        )
        tags.append(tag)
        syncPrimaryTagFieldsFromTags()
        return tag
    }

    func addTag(number: String, colorID: UUID?, isPrimary: Bool, assignedAt: Date = .now) -> AnimalTag {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldBePrimary = isPrimary || activeTags.isEmpty

        if shouldBePrimary {
            for tag in tags where tag.isActive {
                tag.isPrimary = false
            }
        }

        let tag = AnimalTag(
            number: trimmedNumber,
            colorID: colorID,
            isPrimary: shouldBePrimary,
            isActive: true,
            assignedAt: assignedAt,
            animal: self
        )
        tags.append(tag)
        syncPrimaryTagFieldsFromTags()
        return tag
    }

    func updatePrimaryTag(number: String, colorID: UUID?) {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        tagNumber = trimmedNumber
        tagColorID = colorID

        let tag = ensurePrimaryTagRecord()
        tag.number = trimmedNumber
        tag.colorID = colorID

        for otherTag in tags where otherTag.publicID != tag.publicID && otherTag.isActive {
            otherTag.isPrimary = false
        }

        syncPrimaryTagFieldsFromTags()
    }

    func promoteTagToPrimary(_ tag: AnimalTag) {
        for existingTag in tags where existingTag.isActive {
            existingTag.isPrimary = existingTag.publicID == tag.publicID
        }
        tag.isActive = true
        tag.removedAt = nil
        syncPrimaryTagFieldsFromTags()
    }

    func retireTag(_ tag: AnimalTag, on date: Date = .now) {
        tag.isActive = false
        tag.isPrimary = false
        tag.removedAt = date

        if let replacement = activeTags.first {
            replacement.isPrimary = true
            replacement.isActive = true
            replacement.removedAt = nil
        }

        syncPrimaryTagFieldsFromTags()
    }

    func applyStatus(_ newStatus: AnimalStatus, effectiveDate: Date = .now) {
        status = newStatus

        switch newStatus {
        case .active:
            saleDate = nil
            salePrice = nil
            reasonSold = nil
            deathDate = nil
            causeOfDeath = nil
            statusReferenceID = nil
        case .sold:
            saleDate = saleDate ?? effectiveDate
            deathDate = nil
            causeOfDeath = nil
            statusReferenceID = nil
        case .dead:
            deathDate = deathDate ?? effectiveDate
            saleDate = nil
            salePrice = nil
            reasonSold = nil
            statusReferenceID = nil
        }
    }

    func archive(reason: String? = nil, at date: Date = .now) {
        isSoftDeleted = true
        softDeletedAt = date
        softDeleteReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func restoreArchivedRecord() {
        isSoftDeleted = false
        softDeletedAt = nil
        softDeleteReason = nil
    }

    func softDelete(reason: String? = nil, at date: Date = .now) {
        archive(reason: reason, at: date)
    }

    func restoreSoftDeletedRecord() {
        restoreArchivedRecord()
    }

    var ageInMonths: Int {
        let now = Date()
        guard birthDate <= now else { return 0 }
        let comps = Calendar.current.dateComponents([.month], from: birthDate, to: now)
        return max(0, comps.month ?? 0)
    }

    var age: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let birth = calendar.startOfDay(for: birthDate)

        guard birth <= today else { return "1 day" }

        let yearMonth = calendar.dateComponents([.year, .month], from: birth, to: today)
        if let y = yearMonth.year, y >= 1 {
            let m = yearMonth.month ?? 0
            if m > 0 {
                return "\(y)yr \(m)mo"
            } else {
                return y == 1 ? "1yr" : "\(y)yr"
            }
        }

        let months = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        if months >= 1 {
            return months == 1 ? "1mo" : "\(months)mo"
        }

        let weekDay = calendar.dateComponents([.weekOfYear, .day], from: birth, to: today)
        let w = weekDay.weekOfYear ?? 0
        let d = weekDay.day ?? 0

        if w >= 1 {
            if d > 0 {
                let weekText = w == 1 ? "1 wk" : "\(w) wks"
                let dayText = d == 1 ? "1 day" : "\(d) days"
                return "\(weekText) \(dayText)"
            } else {
                return w == 1 ? "1 wk" : "\(w) wks"
            }
        }

        let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        let dFinal = max(days, 1)
        return dFinal == 1 ? "1 day" : "\(dFinal) days"
    }

    init(
        publicID: UUID = UUID(),
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        birthDate: Date,
        status: AnimalStatus = .active,
        saleDate: Date? = nil,
        salePrice: Double? = nil,
        reasonSold: String? = nil,
        deathDate: Date? = nil,
        causeOfDeath: String? = nil,
        statusReferenceID: UUID? = nil,
        isSoftDeleted: Bool = false,
        softDeletedAt: Date? = nil,
        softDeleteReason: String? = nil,
        sireAnimal: Animal? = nil,
        damAnimal: Animal? = nil,
        pasture: Pasture? = nil,
        sex: Sex? = nil,
        distinguishingFeatures: [DistinguishingFeature] = []
    ) {
        self.publicID = publicID
        self.name = name
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.birthDate = birthDate
        self.status = status
        self.saleDate = saleDate
        self.salePrice = salePrice
        self.reasonSold = reasonSold
        self.deathDate = deathDate
        self.causeOfDeath = causeOfDeath
        self.statusReferenceID = statusReferenceID
        self.isSoftDeleted = isSoftDeleted
        self.softDeletedAt = softDeletedAt
        self.softDeleteReason = softDeleteReason
        self.sireAnimal = sireAnimal
        self.damAnimal = damAnimal
        self.pasture = pasture
        self.location = AnimalLocation.pasture
        self.activeWorkingSession = nil
        self.sex = sex ?? .unknown
        self.distinguishingFeatures = distinguishingFeatures
    }
}
