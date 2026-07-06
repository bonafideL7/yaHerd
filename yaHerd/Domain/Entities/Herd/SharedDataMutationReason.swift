//
//  SharedDataMutationReason.swift
//  yaHerd
//

import Foundation

enum SharedDataMutationReason: Equatable, Sendable {
    case herd
    case animal
    case pasture
    case dashboard
    case fieldCheck
    case working
    case tagColor
    case sampleData

    var displayName: String {
        switch self {
        case .herd:
            "herd"
        case .animal:
            "animal"
        case .pasture:
            "pasture"
        case .dashboard:
            "dashboard"
        case .fieldCheck:
            "field check"
        case .working:
            "working"
        case .tagColor:
            "tag color"
        case .sampleData:
            "sample data"
        }
    }
}
