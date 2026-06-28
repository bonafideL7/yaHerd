import SwiftUI

struct FieldCheckFindingRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    let finding: FieldCheckFindingSnapshot
    var showsAnimalDisplayTagNumber = true
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
        VStack(alignment: .leading, spacing: 12) {
            header
            
            if !trimmedNote.isEmpty {
                noteRow
            }
            
            if let onStatusChange {
                statusMenu(onStatusChange)
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect(cornerRadius: 16))
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: finding.type.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(finding.type.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    FieldCheckBadge(title: finding.status.label, tint: tint)
                }
                
                if let pastureName = finding.pastureName {
                    Label(pastureName, systemImage: "map")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
            
            if showsAnimalDisplayTagNumber,
               let animalDisplayTagNumber = finding.animalDisplayTagNumber {
                animalTagRow(animalDisplayTagNumber)
            }
        }
    }
    
    @ViewBuilder
    private func animalTagRow(_ animalDisplayTagNumber: String) -> some View {
        
        animalTagLabel(animalDisplayTagNumber)
        
    }
    
    private func animalTagLabel(_ animalDisplayTagNumber: String) -> some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: finding.animalDisplayTagColorID)
        
        return HStack(spacing: 8) {
            AnimalTagView(
                tagNumber: animalDisplayTagNumber,
                color: definition.color,
                colorName: definition.name,
                size: .compact
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(alignment: .trailing)
        .accessibilityLabel("Open animal with tag \(animalDisplayTagNumber)")
    }
    
    
    private var noteRow: some View {
        Text(trimmedNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func statusMenu(_ onStatusChange: @escaping (FieldCheckFindingStatus) -> Void) -> some View {
        Menu {
            ForEach(FieldCheckFindingStatus.allCases) { status in
                Button(status.label) {
                    onStatusChange(status)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                
                Text("Update Status")
                    .font(.footnote.weight(.semibold))
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
        .menuIndicator(.hidden)
    }
}

struct FieldCheckBadge: View {
    let title: String
    let tint: Color
    
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}
