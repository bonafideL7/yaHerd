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
    var name: String
    var tagNumber: String
    var tagColorID: UUID?
    var sex: Sex?
    var birthDate: Date
    var status: AnimalStatus
    var sire: String?
    var dam: String?
    var locationRaw: AnimalLocation? = AnimalLocation.pasture
    var distinguishingFeatures: [DistinguishingFeature] = []
    
    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []
    @Relationship(deleteRule: .nullify) var activeWorkingSession: WorkingSession?
    @Relationship var pasture: Pasture?
    @Relationship(deleteRule: .cascade, inverse: \AnimalTag.animal) var tags: [AnimalTag] = []

    var location: AnimalLocation {
        get { locationRaw ?? .pasture }
        set { locationRaw = newValue }
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
            return tag.persistentModelID != primaryTag.persistentModelID
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

        for otherTag in tags where otherTag.persistentModelID != tag.persistentModelID && otherTag.isActive {
            otherTag.isPrimary = false
        }

        syncPrimaryTagFieldsFromTags()
    }

    func promoteTagToPrimary(_ tag: AnimalTag) {
        for existingTag in tags where existingTag.isActive {
            existingTag.isPrimary = existingTag.persistentModelID == tag.persistentModelID
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

    var ageInMonths: Int {
        let now = Date()
        guard birthDate <= now else { return 0 }
        let comps = Calendar.current.dateComponents([.month], from: birthDate, to: now)
        return max(0, comps.month ?? 0)
    }
    
    //MARK: Age Calculation
    
    var age: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let birth = calendar.startOfDay(for: birthDate)
        
        guard birth <= today else { return "1 day" }
        
        // Years + Months
        let yearMonth = calendar.dateComponents([.year, .month], from: birth, to: today)
        if let y = yearMonth.year, y >= 1 {
            let m = yearMonth.month ?? 0
            if m > 0 {
                return "\(y)yr \(m)mo"
            } else {
                return y == 1 ? "1yr" : "\(y)yr"
            }
        }
        
        // Months
        let months = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        if months >= 1 {
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        // Weeks + Days
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
        
        // Days
        let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        let dFinal = max(days, 1)
        return dFinal == 1 ? "1 day" : "\(dFinal) days"
    }

    //MARK: Constructor
    
    init(
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        birthDate: Date,
        status: AnimalStatus = .alive,
        sire: String? = nil,
        dam: String? = nil,
        pasture: Pasture? = nil,
        sex: Sex? = nil,
        distinguishingFeatures: [DistinguishingFeature] = []
    ) {
        self.name = name
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.birthDate = birthDate
        self.status = status
        self.sire = sire
        self.dam = dam
        self.pasture = pasture
        self.location = AnimalLocation.pasture
        self.activeWorkingSession = nil
        self.sex = sex ?? .female
        self.distinguishingFeatures = distinguishingFeatures
    }
}

struct DistinguishingFeature: Codable, Hashable, Identifiable {
    var id: UUID
    var description: String

    init(id: UUID = UUID(), description: String) {
        self.id = id
        self.description = description
    }
}

//MARK: Constants

enum Sex: String, Codable, CaseIterable {
    case female
    case male
    case unknown
    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .unknown: return "Unknown"
        }
    }
}

enum AnimalStatus: String, Codable, CaseIterable {
    case alive
    case sold
    case deceased
}

enum AnimalLocation: String, Codable, CaseIterable {
    case pasture
    case workingPen
}
