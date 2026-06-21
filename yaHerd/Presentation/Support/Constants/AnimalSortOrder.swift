//
//  AnimalSortOrder.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation

enum AnimalSortOrder: String, CaseIterable {
    case tagAscending
    case tagDescending
    case birthDateNewest
    case birthDateOldest
    case sex
    case animalType
    case status
    case pasture

    static var menuOptions: [AnimalSortOrder] {
        [.tagAscending, .birthDateNewest, .sex, .animalType, .status, .pasture]
    }

    var label: String {
        switch self {
        case .tagAscending: return "Tag (A → Z)"
        case .tagDescending: return "Tag (Z → A)"
        case .birthDateNewest: return "Birth Date (Newest)"
        case .birthDateOldest: return "Birth Date (Oldest)"
        case .sex: return "Sex"
        case .animalType: return "Animal Type"
        case .status: return "Status"
        case .pasture: return "Pasture"
        }
    }

    var menuLabel: String {
        switch self {
        case .tagAscending, .tagDescending: return "Tag"
        case .birthDateNewest, .birthDateOldest: return "Birth Date"
        case .sex: return "Sex"
        case .animalType: return "Animal Type"
        case .status: return "Status"
        case .pasture: return "Pasture"
        }
    }

    var icon: String {
        switch self {
        case .tagAscending: return "arrow.up"
        case .tagDescending: return "arrow.down"
        case .birthDateNewest: return "clock.arrow.circlepath"
        case .birthDateOldest: return "clock"
        case .sex: return "person.2"
        case .animalType: return "pawprint"
        case .status: return "tag"
        case .pasture: return "leaf"
        }
    }

    var menuIcon: String {
        switch self {
        case .tagAscending, .tagDescending: return "tag"
        case .birthDateNewest, .birthDateOldest: return "calendar"
        case .sex: return "person.2"
        case .animalType: return "pawprint"
        case .status: return "tag"
        case .pasture: return "leaf"
        }
    }

    var menuSelection: AnimalSortOrder {
        switch self {
        case .tagAscending, .tagDescending: return .tagAscending
        case .birthDateNewest, .birthDateOldest: return .birthDateNewest
        case .sex, .animalType, .status, .pasture: return self
        }
    }

    var defaultMenuSelection: AnimalSortOrder {
        switch self {
        case .tagAscending, .tagDescending: return .tagAscending
        case .birthDateNewest, .birthDateOldest: return .birthDateNewest
        case .sex, .animalType, .status, .pasture: return self
        }
    }

    var canReverseDirection: Bool {
        switch self {
        case .tagAscending, .tagDescending, .birthDateNewest, .birthDateOldest:
            return true
        case .sex, .animalType, .status, .pasture:
            return false
        }
    }

    var reversedDirection: AnimalSortOrder {
        switch self {
        case .tagAscending: return .tagDescending
        case .tagDescending: return .tagAscending
        case .birthDateNewest: return .birthDateOldest
        case .birthDateOldest: return .birthDateNewest
        case .sex, .animalType, .status, .pasture: return self
        }
    }

    var reverseDirectionIcon: String {
        switch self {
        case .tagAscending, .birthDateNewest: return "arrow.down"
        case .tagDescending, .birthDateOldest: return "arrow.up"
        case .sex, .animalType, .status, .pasture: return "arrow.up.arrow.down"
        }
    }

    var reverseDirectionAccessibilityLabel: String {
        switch self {
        case .tagAscending: return "Sort Tag Z to A"
        case .tagDescending: return "Sort Tag A to Z"
        case .birthDateNewest: return "Sort Birth Date Oldest First"
        case .birthDateOldest: return "Sort Birth Date Newest First"
        case .sex, .animalType, .status, .pasture: return "Reverse Sort Direction"
        }
    }
}
