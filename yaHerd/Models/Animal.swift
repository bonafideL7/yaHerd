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
    /// User-visible tag number.
    ///
    /// IMPORTANT: This is NOT globally unique. Tags can be reused after an animal is sold or deceased.
    var tagNumber: String
    /// NEW: User-defined tag color selected from the settings library.
    ///
    /// Stored as a UUID referencing a `TagColorDefinition` persisted in `UserDefaults`.
    var tagColorID: UUID?
    /// Legacy stored designation (cow/bull/heifer/steer). Still persisted for migration/back-compat.
    var sex: Sex

    /// Biological sex used to compute `designation`. Optional so existing stores migrate without a versioned schema.
    var biologicalSex: BiologicalSex?
    var birthDate: Date
    var status: AnimalStatus
    var sire: String?
    var dam: String?

    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []

    /// Current pasture location. Nil when the animal is in the working pen.
    @Relationship var pasture: Pasture?

    /// Current non-pasture location state.
    ///
    /// Stored as OPTIONAL to avoid SwiftData crashing on existing stores where this field
    /// did not exist yet (it will load as `nil`). Treat `nil` as `.pasture`.
    ///
    /// NOTE: SwiftData @Model requires fully-qualified enum values for property default values.
    var locationRaw: AnimalLocation? = AnimalLocation.pasture

    /// Non-optional façade used throughout the app.
    var location: AnimalLocation {
        get { locationRaw ?? .pasture }
        set { locationRaw = newValue }
    }

    /// Active working session when `location == .workingPen`.
    @Relationship(deleteRule: .nullify)
    var activeWorkingSession: WorkingSession?


    /// Computed classification derived from biological sex and (for females) age.
    /// If `biologicalSex` is nil (older data), falls back to the legacy stored `sex`.
    var designation: Sex {
        guard let biologicalSex else { return sex }
        return Self.computeDesignation(
            biologicalSex: biologicalSex,
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
        birthDate: Date,
        referenceDate: Date
    ) -> Sex {
        switch biologicalSex {
        case .female:
            let comps = Calendar.current.dateComponents([.month], from: birthDate, to: referenceDate)
            let months = max(0, comps.month ?? 0)
            return months >= AnimalConstants.heiferToCowMonths ? .cow : .heifer
        case .male:
            return .bull
        }
    }

    /// Keep the legacy `sex` field in sync after editing biological data.
    func syncLegacySexFromData() {
        guard biologicalSex != nil else { return }
        sex = designation
    }

    init(
        tagNumber: String,
        tagColorID: UUID? = nil,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .alive,
        sire: String? = nil,
        dam: String? = nil,
        pasture: Pasture? = nil,
        biologicalSex: BiologicalSex? = nil
    ) {
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.sex = sex
        self.birthDate = birthDate
        self.status = status
        self.sire = sire
        self.dam = dam
        self.pasture = pasture

        self.location = AnimalLocation.pasture
        self.activeWorkingSession = nil


        // New data-driven fields (optional for migration)
        let inferredBio = biologicalSex ?? sex.inferredBiologicalSex
        self.biologicalSex = inferredBio
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

enum AnimalLocation: String, Codable, CaseIterable {
    case pasture
    case workingPen
}
