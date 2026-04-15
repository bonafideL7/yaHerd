//
//  AnimalFormView.swift
//

import SwiftUI

enum ParentPickerType: Identifiable {
    case sire
    case dam
    
    var id: Int {
        switch self {
        case .sire: return 1
        case .dam: return 2
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
