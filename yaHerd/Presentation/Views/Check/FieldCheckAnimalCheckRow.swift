import SwiftUI

struct FieldCheckAnimalCheckRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.colorScheme) private var colorScheme

    let sessionID: UUID
    let check: FieldCheckAnimalCheckSnapshot
    let isEditable: Bool
    let onToggleCounted: () -> Void
    let onToggleMissing: () -> Void

    var body: some View {
        if isEditable {
            rowContent
                .contextMenu {
                    Button {
                        onToggleCounted()
                    } label: {
                        Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    }

                    Button {
                        onToggleMissing()
                    } label: {
                        Label(missingActionTitle, systemImage: missingActionSystemImage)
                    }
                }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                tagView

                VStack(alignment: .leading, spacing: 6) {
                    if !check.animalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(check.animalName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    statusBadges
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isEditable {
                    FieldCheckBadge(title: readOnlyStatusTitle, tint: readOnlyStatusTint)
                }
            }

            if isEditable {
                actionRow
            }

            if let animalID = check.animalID {
                NavigationLink {
                    FieldCheckAnimalDetailView(sessionID: sessionID, animalID: animalID)
                } label: {
                    Label("Open Animal", systemImage: "arrow.right.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var tagView: some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: check.displayTagColorID)
        let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: check.damDisplayTagColorID)

        return AnimalTagView(
            tagNumber: check.displayTagNumber,
            color: definition.color,
            colorName: definition.name,
            size: .compact,
            damTagNumber: check.damDisplayTagNumber,
            damTagColor: damDefinition.color,
            damTagColorName: damDefinition.name
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusBadges: some View {
        HStack(spacing: 6) {
            ForEach(Array(statusTokens.enumerated()), id: \.offset) { _, token in
                FieldCheckBadge(title: token.title, tint: token.tint)
            }
        }
        .lineLimit(1)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            primaryActionButton

            if showsMissingAction {
                Button {
                    onToggleMissing()
                } label: {
                    Label(missingActionTitle, systemImage: missingActionSystemImage)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(check.isMissing ? .accentColor : .orange)
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if primaryActionIsProminent {
            Button {
                onToggleCounted()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryActionTint)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
        } else {
            Button {
                onToggleCounted()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(primaryActionTint)
        }
    }

    private var statusTokens: [(title: String, tint: Color)] {
        var tokens: [(String, Color)] = []

        if check.wasCounted {
            tokens.append(("Seen", .green))
        } else if check.isMissing {
            tokens.append(("Missing", .orange))
        } else {
            tokens.append(("Not Seen", .secondary))
        }

        if check.needsAttention {
            tokens.append(("Flagged", .orange))
        }

        if !check.wasExpectedAtStart {
            tokens.append(("Added", .secondary))
        }

        return tokens
    }

    private var primaryActionTitle: String {
        if check.wasCounted { return "Mark Not Seen" }
        if check.isMissing { return "Mark Found" }
        return "Mark Seen"
    }

    private var primaryActionSystemImage: String {
        if check.wasCounted { return "checkmark.circle.fill" }
        if check.isMissing { return "checkmark.circle" }
        return "circle"
    }

    private var primaryActionTint: Color {
        if check.wasCounted { return .green }
        if check.isMissing { return .accentColor }
        return .accentColor
    }

    private var primaryActionIsProminent: Bool {
        !check.wasCounted
    }

    private var showsMissingAction: Bool {
        !check.isMissing && !check.wasCounted
    }

    private var missingActionTitle: String {
        check.isMissing ? "Mark Not Missing" : "Mark Missing"
    }

    private var missingActionSystemImage: String {
        check.isMissing ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var readOnlyStatusTitle: String {
        if check.wasCounted { return "Seen" }
        if check.isMissing { return "Missing" }
        return "Not Seen"
    }

    private var readOnlyStatusTint: Color {
        if check.wasCounted { return .green }
        if check.isMissing { return .orange }
        return .secondary
    }
}
