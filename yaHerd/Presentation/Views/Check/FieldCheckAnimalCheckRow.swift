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
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onToggleMissing()
                    } label: {
                        Label(missingActionTitle, systemImage: missingActionSystemImage)
                    }
                    .tint(check.isMissing ? .accentColor : .orange)
                }
                .contextMenu {
                    Button {
                        onToggleCounted()
                    } label: {
                        Label(countToggleActionTitle, systemImage: primaryActionSystemImage)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                let definition = tagColorLibrary.resolvedDefinition(tagColorID: check.displayTagColorID)
                let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: check.damDisplayTagColorID)
                AnimalTagView(
                    tagNumber: check.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name,
                    size: .compact,
                    damTagNumber: check.damDisplayTagNumber,
                    damTagColor: damDefinition.color,
                    damTagColorName: damDefinition.name
                )
                .fixedSize(horizontal: true, vertical: false)
                
                VStack(alignment: .leading, spacing: 4) {
                    if !check.animalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(check.animalName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 6) {
                        if !check.wasExpectedAtStart {
                            FieldCheckBadge(title: "Added", tint: .secondary)
                        }

                        if check.isMissing {
                            FieldCheckBadge(title: "Missing", tint: .orange)
                        }

                        if check.needsAttention {
                            FieldCheckBadge(title: "Flagged", tint: .orange)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
                
                statusControl
                    .layoutPriority(2)
            }
            
            if let animalID = check.animalID {
                NavigationLink {
                    FieldCheckAnimalDetailView(sessionID: sessionID, animalID: animalID)
                } label: {
                    Label("Open Animal", systemImage: "arrow.right.circle")
                        .font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusControl: some View {
        if isEditable {
            Button {
                onToggleCounted()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: primaryActionSystemImage)
                    Text(primaryActionTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(primaryActionTint)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            FieldCheckBadge(title: readOnlyStatusTitle, tint: readOnlyStatusTint)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var countToggleActionTitle: String {
        check.wasCounted ? "Clear Counted" : primaryActionTitle
    }

    private var primaryActionTitle: String {
        if check.wasCounted { return "Counted" }
        if check.isMissing { return "Found" }
        return "Count"
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

    private var missingActionTitle: String {
        check.isMissing ? "Clear Missing" : "Mark Missing"
    }

    private var missingActionSystemImage: String {
        check.isMissing ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var readOnlyStatusTitle: String {
        if check.wasCounted { return "Counted" }
        if check.isMissing { return "Missing" }
        return "Not Seen"
    }

    private var readOnlyStatusTint: Color {
        if check.wasCounted { return .green }
        if check.isMissing { return .orange }
        return .secondary
    }
}
