import SwiftUI

struct FieldCheckAnimalCheckRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.colorScheme) private var colorScheme
    
    let sessionID: UUID
    let check: FieldCheckAnimalCheckSnapshot
    let onToggleCounted: () -> Void
    
    var body: some View {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    if !check.animalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(check.animalName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if check.needsAttention {
                        FieldCheckBadge(title: "Flagged", tint: .orange)
                    }
                }
                
                Spacer(minLength: 8)
                
                Button {
                    onToggleCounted()
                } label: {
                    Label(check.wasCounted ? "Counted" : "Count", systemImage: check.wasCounted ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(check.wasCounted ? .green : .accentColor)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
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
}
