import SwiftUI

/// Shared visual label for floating add buttons and add menus.
struct FloatingAddButtonLabel: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 50)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.1)).interactive(), in: Circle())
            .shadow(
                color: Color.accentColor.opacity(0.8),
                radius: 1,
                x: 0,
                y: 0
            )
    }
}
