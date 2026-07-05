import SwiftUI

struct FieldCheckAnimalCheckRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let sessionID: UUID
    let check: FieldCheckAnimalCheckSnapshot
    let isEditable: Bool
    var isCountedByQuickCount = false
    let onToggleCounted: () -> Void
    let onToggleMissing: () -> Void
    var onAddFinding: ((UUID) -> Void)? = nil
    var onOpenAnimal: ((UUID) -> Void)? = nil

    var body: some View {
        if isEditable {
            rowContent
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isEffectivelySeen {
                        Button(primaryActionTitle) {
                            onToggleCounted()
                        }
                        .tint(primaryActionTint)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let animalID = check.animalID, let onAddFinding {
                        Button("Finding") {
                            onAddFinding(animalID)
                        }
                        .tint(.blue)
                    }

                    Button(missingActionTitle) {
                        onToggleMissing()
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    if !isCountedByQuickCount {
                        Button {
                            onToggleCounted()
                        } label: {
                            Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                        }
                    }

                    Button {
                        onToggleMissing()
                    } label: {
                        Label(missingActionTitle, systemImage: missingActionSystemImage)
                    }

                    if let animalID = check.animalID, let onAddFinding {
                        Button {
                            onAddFinding(animalID)
                        } label: {
                            Label("Add Finding", systemImage: "exclamationmark.bubble")
                        }
                    }
                }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            tagView

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge

            if isEditable {
                primaryControl
            }

            if let animalID = check.animalID, let onOpenAnimal {
                Button {
                    onOpenAnimal(animalID)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HierarchicalShapeStyle.tertiary)
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open animal")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        if check.isMissing {
            FieldCheckBadge(title: "Missing", tint: .orange)
        } else if isCountedByQuickCount {
            FieldCheckBadge(title: "Counted", tint: .accentColor)
        } else if check.needsAttention {
            FieldCheckBadge(title: "Flagged", tint: .orange)
        } else if !check.wasExpectedAtStart {
            FieldCheckBadge(title: "Added", tint: .secondary)
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if isEffectivelySeen {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.green)
                .accessibilityLabel("Seen")
        } else {
            Button {
                onToggleCounted()
            } label: {
                Text(primaryActionTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(primaryActionTint)
        }
    }

    private var isEffectivelySeen: Bool {
        check.wasCounted || isCountedByQuickCount
    }

    private var titleText: String {
        let trimmedName = check.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return check.displayTagNumber }
        return trimmedName
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

    private var statusSummary: String {
        var parts: [String] = [check.animalType.label.lowercased()]

        if check.wasCounted {
            parts.append("seen")
        } else if isCountedByQuickCount {
            parts.append("counted by type")
        } else if check.isMissing {
            parts.append("missing")
        } else {
            parts.append("not seen")
        }

        if !check.wasExpectedAtStart {
            parts.append("added")
        }

        return parts.joined(separator: " • ")
    }

    private var primaryActionTitle: String {
        if check.wasCounted { return "Not Seen" }
        if isCountedByQuickCount { return "Seen" }
        if check.isMissing { return "Found" }
        return "Seen"
    }

    private var primaryActionSystemImage: String {
        if check.wasCounted { return "arrow.uturn.backward.circle" }
        if isCountedByQuickCount { return "checkmark.circle" }
        if check.isMissing { return "checkmark.circle" }
        return "checkmark.circle"
    }

    private var primaryActionTint: Color {
        if check.isMissing { return .accentColor }
        return .accentColor
    }

    private var missingActionTitle: String {
        check.isMissing ? "Not Missing" : "Missing"
    }

    private var missingActionSystemImage: String {
        check.isMissing ? "checkmark.circle" : "exclamationmark.triangle"
    }
}
