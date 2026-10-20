import SwiftUI

/// Shared finish action used by Working Sessions and Pasture Checks.
struct SessionFinishActionBar: View {
    let title: String
    let isEnabled: Bool
    let statusText: String?
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let statusText {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onFinish) {
                Label(title, systemImage: "checkmark.circle.fill")
                    .readableAccentForeground()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}
