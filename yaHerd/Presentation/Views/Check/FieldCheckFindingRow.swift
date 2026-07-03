import SwiftUI

struct FieldCheckFindingRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let finding: FieldCheckFindingSnapshot
    var showsAnimalDisplayTagNumber = true
    var showsPastureName = true
    var onEdit: (() -> Void)? = nil
    var onStatusChange: ((FieldCheckFindingStatus) -> Void)? = nil

    private var tint: Color {
        switch finding.severity {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var trimmedNote: String {
        finding.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !trimmedNote.isEmpty {
                noteRow
            }

            if onEdit != nil || onStatusChange != nil {
                actionRow
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: finding.type.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.tint(tint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(finding.type.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    FieldCheckBadge(title: finding.status.label, tint: tint)
                }

                metaRow
            }

            Spacer(minLength: 0)

            if showsAnimalDisplayTagNumber,
               let animalDisplayTagNumber = finding.animalDisplayTagNumber {
                animalTagLabel(animalDisplayTagNumber)
            }
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        let showsAnimal = !showsAnimalDisplayTagNumber && finding.animalDisplayTagNumber != nil
        let showsPasture = showsPastureName && finding.pastureName != nil

        if showsAnimal || showsPasture {
            HStack(spacing: 10) {
                if showsAnimal, let animalDisplayTagNumber = finding.animalDisplayTagNumber {
                    Label(animalDisplayTagNumber, systemImage: "tag")
                }

                if showsPasture, let pastureName = finding.pastureName {
                    Label(pastureName, systemImage: "map")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func animalTagLabel(_ animalDisplayTagNumber: String) -> some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: finding.animalDisplayTagColorID)

        return AnimalTagView(
            tagNumber: animalDisplayTagNumber,
            color: definition.color,
            colorName: definition.name,
            size: .compact
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Animal tag \(animalDisplayTagNumber)")
    }

    private var noteRow: some View {
        Text(trimmedNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Color.secondary.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let onStatusChange {
                statusAction(onStatusChange)
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func statusAction(_ onStatusChange: @escaping (FieldCheckFindingStatus) -> Void) -> some View {
        if finding.status == .resolved {
            statusMenu(onStatusChange, title: "Update")
        } else {
            Button {
                onStatusChange(.resolved)
            } label: {
                Label("Resolve", systemImage: "checkmark.circle")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
    }

    private func statusMenu(
        _ onStatusChange: @escaping (FieldCheckFindingStatus) -> Void,
        title: String = "Update"
    ) -> some View {
        Menu {
            ForEach(FieldCheckFindingStatus.allCases) { status in
                Button(status.label) {
                    onStatusChange(status)
                }
            }
        } label: {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

struct FieldCheckBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(tint.opacity(0.14)), in: Capsule())
            .foregroundStyle(tint)
    }
}
