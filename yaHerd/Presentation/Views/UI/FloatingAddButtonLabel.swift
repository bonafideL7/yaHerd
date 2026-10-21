import SwiftUI

/// Shared visual label for floating add buttons and add menus.
struct FloatingAddButtonLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: "plus")
            .font(.title2.weight(.bold))
            .foregroundStyle(AccessibleControlContrast.accentForeground(in: colorScheme).opacity(0.9))
            .frame(width: 48, height: 48)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.4)).interactive(), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
