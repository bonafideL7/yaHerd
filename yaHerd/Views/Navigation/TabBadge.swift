//
//  TabBadge.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI

extension View {
    @ViewBuilder
    func tabBadge(_ count: Int) -> some View {
        if count > 0 {
            self.badge(count)
        } else {
            self
        }
    }
}
