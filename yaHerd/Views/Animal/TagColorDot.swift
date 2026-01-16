//
//  TagColorDot.swift
//  yaHerd
//

import SwiftUI

struct TagColorDot: View {
    let tagColor: TagColor

    var body: some View {
        TagColorTagIcon(
            color: tagColor.color,
            accessibilityLabel: "Tag color: \(tagColor.label)",
            size: 14
        )
    }
}
