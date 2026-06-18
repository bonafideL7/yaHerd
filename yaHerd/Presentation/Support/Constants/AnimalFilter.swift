//
//  AnimalFilter.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//

import Foundation

enum AnimalPastureFilter: Hashable {
    case any
    case noPasture
    case pasture(UUID)

    var isActive: Bool {
        switch self {
        case .any:
            return false
        case .noPasture, .pasture:
            return true
        }
    }
}

enum AnimalLocationFilter: CaseIterable, Hashable {
    case any
    case pasture
    case workingPen

    var isActive: Bool {
        self != .any
    }

    var label: String {
        switch self {
        case .any:
            return "Any Location"
        case .pasture:
            return "Pasture"
        case .workingPen:
            return "Working Pen"
        }
    }
}

enum AnimalCareFilter: CaseIterable, Hashable {
    case any
    case overduePregnancyCheck
    case overdueTreatment
    case calvingWatch

    var isActive: Bool {
        self != .any
    }

    var label: String {
        switch self {
        case .any:
            return "Any Care Status"
        case .overduePregnancyCheck:
            return "Overdue Pregnancy Check"
        case .overdueTreatment:
            return "Overdue Treatment"
        case .calvingWatch:
            return "Calving Watch"
        }
    }
}

enum AnimalRecordIssueFilter: CaseIterable, Hashable {
    case any
    case missingPasture
    case missingTagNumber
    case missingTagColor
    case unknownSex
    case archivedActive

    var isActive: Bool {
        self != .any
    }

    var label: String {
        switch self {
        case .any:
            return "Any Record State"
        case .missingPasture:
            return "Missing Pasture"
        case .missingTagNumber:
            return "Missing Tag Number"
        case .missingTagColor:
            return "Missing Tag Color"
        case .unknownSex:
            return "Unknown Sex"
        case .archivedActive:
            return "Archived Active"
        }
    }
}

struct AnimalFilter: Hashable {
    var sex: Sex? = nil
    var animalType: AnimalType? = nil
    var status: AnimalStatus? = nil
    var pasture: AnimalPastureFilter = .any
    var location: AnimalLocationFilter = .any
    var care: AnimalCareFilter = .any
    var recordIssue: AnimalRecordIssueFilter = .any

    var pastureID: UUID? {
        get {
            if case let .pasture(id) = pasture {
                return id
            }
            return nil
        }
        set {
            pasture = newValue.map(AnimalPastureFilter.pasture) ?? .any
        }
    }

    var isActive: Bool {
        sex != nil
        || animalType != nil
        || status != nil
        || pasture.isActive
        || location.isActive
        || care.isActive
        || recordIssue.isActive
    }

    mutating func clear() {
        sex = nil
        animalType = nil
        status = nil
        pasture = .any
        location = .any
        care = .any
        recordIssue = .any
    }
}
