import SwiftUI

enum HomeSuggestionLayout {
    static let sectionCornerRadius: CGFloat = 32
    static let cardSpacing: CGFloat = 12
    static let cardHeight: CGFloat = 140
    static let carouselHeight: CGFloat = 152
    static let carouselHorizontalPadding: CGFloat = 12
    static let carouselVerticalPadding: CGFloat = 6
    static let cardCornerRadius: CGFloat = 24
    static let minimumCardWidth: CGFloat = 280
    static let maximumCardWidth: CGFloat = 360
    static let nextCardPeekWidth: CGFloat = 44

    static func cardWidth(for containerWidth: CGFloat) -> CGFloat {
        let availableWidth = max(containerWidth - (carouselHorizontalPadding * 2), 0)
        let widthWithPeek = availableWidth - cardSpacing - nextCardPeekWidth
        let cappedWidth = min(max(widthWithPeek, minimumCardWidth), maximumCardWidth)

        return min(cappedWidth, availableWidth)
    }
}

struct HomeSuggestionButtonRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let cardWidth: CGFloat
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HomeSuggestionCard(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            cardWidth: cardWidth,
            onDismiss: onDismiss
        ) {
            Button(action: onAction) {
                HomeSuggestionActionLabel(title: actionTitle)
            }
            .modifier(HomeSuggestionActionButtonStyle(tint: tint))
            .accessibilityLabel(actionTitle)
        }
    }
}

struct HomeSuggestionNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let cardWidth: CGFloat
    let destination: Destination
    let onDismiss: () -> Void

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        actionTitle: String,
        cardWidth: CGFloat,
        @ViewBuilder destination: () -> Destination,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.cardWidth = cardWidth
        self.destination = destination()
        self.onDismiss = onDismiss
    }

    var body: some View {
        HomeSuggestionCard(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            cardWidth: cardWidth,
            onDismiss: onDismiss
        ) {
            NavigationLink {
                destination
            } label: {
                HomeSuggestionActionLabel(title: actionTitle)
            }
            .modifier(HomeSuggestionActionButtonStyle(tint: tint))
            .accessibilityLabel(actionTitle)
        }
    }
}

struct HomeSuggestionCard<Action: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let cardWidth: CGFloat
    let onDismiss: () -> Void
    let action: Action

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        cardWidth: CGFloat,
        onDismiss: @escaping () -> Void,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.cardWidth = cardWidth
        self.onDismiss = onDismiss
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                HomeSuggestionIcon(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .modifier(HomeGlassControlBackground(cornerRadius: 14, tint: tint))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(title) suggestion")
            }

            HStack(spacing: 8) {
                action

                Spacer(minLength: 0)
            }
            .padding(.leading, 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .frame(width: cardWidth, height: HomeSuggestionLayout.cardHeight, alignment: .topLeading)
        .modifier(HomeGlassCardBackground(cornerRadius: HomeSuggestionLayout.cardCornerRadius, tint: tint))
        .contentShape(RoundedRectangle(cornerRadius: HomeSuggestionLayout.cardCornerRadius, style: .continuous))
    }
}

struct HomeSuggestionIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint))
            .shadow(color: tint.opacity(0.25), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

struct HomeSuggestionActionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(minWidth: 74)
    }
}

struct HomeSuggestionActionButtonStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(tint)
    }
}

struct HomeGlassCardBackground: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.regular.tint(tint.opacity(0.10)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
    }
}

struct HomeGlassControlBackground: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.regular.tint(tint.opacity(0.08)).interactive(), in: shape)
    }
}

struct HomeLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}
