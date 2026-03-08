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
        sex: Sex? = nil
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
        let inferredBio = sex ?? .female
        self.sex = inferredBio
    }
}

//MARK: Constants

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
