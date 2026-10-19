import SwiftUI

/// A compact, full-row menu target shared by animal check and working lists.
struct AnimalListFilterMenuLabel: View {
    let selection: String
    let systemImage: String
    let count: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 0) {
                Text("Filter animals")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text(selection)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 8)

            Text(count)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
