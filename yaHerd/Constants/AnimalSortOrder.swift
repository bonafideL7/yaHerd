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
    case status

    var label: String {
        switch self {
        case .tagAscending: return "Tag (A → Z)"
        case .tagDescending: return "Tag (Z → A)"
        case .birthDateNewest: return "Birth Date (Newest)"
        case .birthDateOldest: return "Birth Date (Oldest)"
        case .sex: return "Sex"
        case .status: return "Status"
        }
    }

    var icon: String {
        switch self {
        case .tagAscending: return "arrow.up"
        case .tagDescending: return "arrow.down"
        case .birthDateNewest: return "clock.arrow.circlepath"
        case .birthDateOldest: return "clock"
        case .sex: return "person.2"
        case .status: return "tag"
        }
    }
}
