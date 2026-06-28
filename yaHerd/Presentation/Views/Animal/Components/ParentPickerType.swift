//
//  ParentPickerType.swift
//

import Foundation

enum ParentPickerType: Int, Identifiable {
    case sire = 1
    case dam = 2

    var id: Int { rawValue }
}
