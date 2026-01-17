//
//  DashboardRoute.swift
//  yaHerd
//

import Foundation

/// Route types used for value-based navigation from the Dashboard tab.
///
/// We avoid embedding multiple `NavigationLink`s inside a single `List` row (SwiftUI can behave
/// unpredictably in that configuration). Instead, the dashboard pushes these routes onto the
/// dashboard `NavigationStack` path.
enum DashboardRoute: Hashable {
    case animalList(DashboardAnimalListKind)
    case pastureList
}
