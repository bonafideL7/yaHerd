//
//  QuickPastureCard.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI
import LucideIcons

struct QuickPastureCard: View {
    let pasture: Pasture
    let onTap: () -> Void
    
    private var headCount: Int {
        pasture.animals.filter { $0.status == .alive }.count
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                
                if let icon = UIImage(lucideId: "bolt") {
                    Image(uiImage: icon.scaled(to: CGSize(width: 20, height: 20)))
                        .renderingMode(.template)
                        .foregroundStyle(.yellow)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(pasture.name)
                        .font(.headline)
                    Text("\(headCount) head")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
