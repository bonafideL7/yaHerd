//
//  TagColor.swift
//  yaHerd
//
//  Created by mm on 12/31/25.
//

import Foundation
import SwiftUI

/// Persisted ear-tag color.
///
/// Stored as a String raw value via `Codable`.
enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case brown
    case gray
    case black
    case white

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gray: return "Gray"
        default: return rawValue.capitalized
        }
    }

    /// SwiftUI color used for rendering.
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        case .black: return .black
        case .white: return .white
        }
    }
}
