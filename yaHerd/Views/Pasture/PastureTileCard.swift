//
//  PastureTileCard.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI
import LucideIcons

struct PastureTileCard: View {
    let pasture: Pasture
    let onTap: () -> Void

    private var headCount: Int {
        pasture.animals.filter { $0.isActiveInHerd }.count
    }

    private var acreage: String {
        if let acres = pasture.acreage {
            return acres.formatted()
        }
        return "—"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {

                // ICON
                if let icon = UIImage(lucideId: "map") {
                    Image(uiImage: icon.scaled(to: CGSize(width: 32, height: 32)))
                        .renderingMode(.template)
                        .foregroundStyle(.green)
                }

                // NAME
                Text(pasture.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // SUMMARY
                Text("\(headCount) head • \(acreage) acres")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
