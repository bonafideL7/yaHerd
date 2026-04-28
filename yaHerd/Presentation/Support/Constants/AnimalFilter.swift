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

struct AnimalFilter {
    var sex: Sex? = nil
    var animalType: AnimalType? = nil
    var status: AnimalStatus? = nil
    var pasture: AnimalPastureFilter = .any

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
        sex != nil || animalType != nil || status != nil || pasture.isActive
    }

    mutating func clear() {
        sex = nil
        animalType = nil
        status = nil
        pasture = .any
    }
}
