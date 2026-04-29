//
//  AppGlassCard.swift
//  yaHerd
//
//  Created by mm on 4/28/26.
//

import SwiftUI

struct AppGlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.12))
            }
            .shadow(radius: 12, y: 6)
    }
}
