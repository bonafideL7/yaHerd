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
    @Attribute(.unique) var tagNumber: String
    /// Visual tag grouping. Optional for painless SwiftData migration; treat `nil` as `.yellow`.
    var tagColor: TagColor?
    /// Legacy stored designation (cow/bull/heifer/steer). Still persisted for migration/back-compat.
    var sex: Sex

    /// Biological sex used to compute `designation`. Optional so existing stores migrate without a versioned schema.
    var biologicalSex: BiologicalSex?
    /// Applies when `biologicalSex == .male`.
    var isCastrated: Bool = false
    var birthDate: Date
    var status: AnimalStatus
    var sire: String?
    var dam: String?

    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []

    @Relationship var pasture: Pasture?


    /// Computed classification derived from biological sex, castration, and (for females) age.
    /// If `biologicalSex` is nil (older data), falls back to the legacy stored `sex`.
    var designation: Sex {
        guard let biologicalSex else { return sex }
        return Self.computeDesignation(
            biologicalSex: biologicalSex,
            isCastrated: isCastrated,
            birthDate: birthDate,
            referenceDate: Date()
        )
    }

    var ageInMonths: Int {
        let now = Date()
        guard birthDate <= now else { return 0 }
        let comps = Calendar.current.dateComponents([.month], from: birthDate, to: now)
        return max(0, comps.month ?? 0)
    }

    static func computeDesignation(
        biologicalSex: BiologicalSex,
        isCastrated: Bool,
        birthDate: Date,
        referenceDate: Date
    ) -> Sex {
        switch biologicalSex {
        case .female:
            let comps = Calendar.current.dateComponents([.month], from: birthDate, to: referenceDate)
            let months = max(0, comps.month ?? 0)
            return months >= AnimalConstants.heiferToCowMonths ? .cow : .heifer
        case .male:
            return isCastrated ? .steer : .bull
        }
    }

    /// Keep the legacy `sex` field in sync after editing biological data.
    func syncLegacySexFromData() {
        guard biologicalSex != nil else { return }
        sex = designation
        if biologicalSex != .male { isCastrated = false }
    }

    init(
        tagNumber: String,
        tagColor: TagColor? = nil,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .alive,
        sire: String? = nil,
        dam: String? = nil,
        pasture: Pasture? = nil,
        biologicalSex: BiologicalSex? = nil,
        isCastrated: Bool = false
    ) {
        self.tagNumber = tagNumber
        self.tagColor = tagColor
        self.sex = sex
        self.birthDate = birthDate
        self.status = status
        self.sire = sire
        self.dam = dam
        self.pasture = pasture


        // New data-driven fields (optional for migration)
        let inferredBio = biologicalSex ?? sex.inferredBiologicalSex
        self.biologicalSex = inferredBio
        if inferredBio == .male {
            self.isCastrated = isCastrated || sex == .steer
        } else {
            self.isCastrated = false
        }
        self.syncLegacySexFromData()
    }
}

enum BiologicalSex: String, Codable, CaseIterable {
    case female
    case male

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        }
    }
}

enum Sex: String, Codable, CaseIterable {
    case cow
    case bull
    case heifer
    case steer
}

extension Sex {
    /// Best-effort mapping from the legacy designation to biological sex.
    /// Used to infer `biologicalSex` for older data during migration.
    var inferredBiologicalSex: BiologicalSex {
        switch self {
        case .cow, .heifer:
            return .female
        case .bull, .steer:
            return .male
        }
    }
}

enum AnimalStatus: String, Codable, CaseIterable {
    case alive
    case sold
    case deceased
}
