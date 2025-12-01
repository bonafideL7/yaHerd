//
//  NavigationCoordinator.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

final class NavigationCoordinator: ObservableObject {
    @Published var globalPath = NavigationPath()

    func push<T: Hashable>(_ value: T) {
        globalPath.append(value)
    }

    func reset() {
        globalPath = NavigationPath()
    }
}
