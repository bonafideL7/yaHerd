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

    var tagNumber: String
    var tagColorID: UUID?
    var sex: Sex?
    var birthDate: Date
    var status: AnimalStatus
    var sire: String?
    var dam: String?
    var locationRaw: AnimalLocation? = AnimalLocation.pasture
    
    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []
    @Relationship(deleteRule: .nullify) var activeWorkingSession: WorkingSession?
    @Relationship var pasture: Pasture?

    var location: AnimalLocation {
        get { locationRaw ?? .pasture }
        set { locationRaw = newValue }
    }

    var ageInMonths: Int {
        let now = Date()
        guard birthDate <= now else { return 0 }
        let comps = Calendar.current.dateComponents([.month], from: birthDate, to: now)
        return max(0, comps.month ?? 0)
    }

    init(
        tagNumber: String,
        tagColorID: UUID? = nil,
        birthDate: Date,
        status: AnimalStatus = .alive,
        sire: String? = nil,
        dam: String? = nil,
        pasture: Pasture? = nil,
        sex: Sex? = nil
    ) {
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.birthDate = birthDate
        self.status = status
        self.sire = sire
        self.dam = dam
        self.pasture = pasture
        self.location = AnimalLocation.pasture
        self.activeWorkingSession = nil
        let inferredBio = sex ?? .female
        self.sex = inferredBio
    }
}

enum Sex: String, Codable, CaseIterable {
    case female
    case male

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
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
