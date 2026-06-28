import SwiftUI

struct FieldCheckAnimalDetailView: View {
    @Environment(\.animalDetailRepository) private var animalRepository
    @Environment(\.fieldCheckAnimalDetailRepository) private var fieldCheckRepository
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    @State private var model = FieldCheckAnimalDetailViewModel()
    @State private var isLineageExpanded = false
    @State private var showingAddOffspring = false
    
    let sessionID: UUID
    let animalID: UUID
    
    private var displayedTagNumber: String {
        model.animalDetail?.displayTagNumber ?? ""
    }
    
    private var displayedTagColorID: UUID? {
        model.animalDetail?.displayTagColorID
    }
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
    
    var body: some View {
        Group {
            if let detail = model.animalDetail {
                Form {
                    if let animalCheck = model.animalCheck {
                        fieldCheckFindingsSection(animalCheck)
                    }
                    
                    AnimalDetailOffspringSection(
                        detail: detail,
                        canAddOffspring: model.preparedOffspringEditor != nil,
                        onAddOffspring: {
                            showingAddOffspring = true
                        }
                    )
                    AnimalDetailDistinguishingFeaturesSection(detail: detail)
                    AnimalDetailLineageSection(isExpanded: $isLineageExpanded, detail: detail)
                }
            } else if model.hasLoaded {
                ContentUnavailableView("Animal Not Found", systemImage: "tag")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Field Check Animal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !displayedTagNumber.isEmpty {
                ToolbarItem(placement: .principal) {
                    let def = tagColorLibrary.resolvedDefinition(tagColorID: displayedTagColorID)
                    AnimalTagView(
                        tagNumber: displayedTagNumber,
                        color: def.color,
                        colorName: def.name,
                        size: .compact
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddOffspring, onDismiss: {
            model.refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }) {
            if let preparedEditor = model.preparedOffspringEditor {
                AddAnimalView(
                    title: "Add Offspring",
                    initialDraft: preparedEditor.draft,
                    editorContext: preparedEditor.context
                )
            }
        }
        .task {
            if !model.hasLoaded {
                model.load(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
            }
        }
        .alert("Can’t Update Animal", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }
    
    @ViewBuilder
    private func fieldCheckFindingsSection(_ animalCheck: FieldCheckAnimalCheckSnapshot) -> some View {
        Section {
            if animalCheck.isMissing {
                HStack(spacing: 8) {
                    FieldCheckBadge(title: "Missing", tint: .orange)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    findingButton(.pinkEye)
                    findingButton(.limping)
                    findingButton(.missingAnimal)
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            
            if model.animalFindings.isEmpty {
                Text("No findings recorded for this animal in this check.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.animalFindings) { finding in
                    FieldCheckFindingRow(
                        finding: finding,
                        showsAnimalDisplayTagNumber: false,
                        onStatusChange: { status in
                            model.updateFindingStatus(
                                animalID: animalID,
                                sessionID: sessionID,
                                findingID: finding.id,
                                status: status,
                                animalRepository: animalRepository,
                                fieldCheckRepository: fieldCheckRepository
                            )
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            model.deleteFinding(
                                animalID: animalID,
                                sessionID: sessionID,
                                findingID: finding.id,
                                animalRepository: animalRepository,
                                fieldCheckRepository: fieldCheckRepository
                            )
                        }
                    }
                }
            }
        } header: {
            Text("Findings")
        } footer: {
            Text("This animal is marked as needing attention whenever findings exist in the current check.")
        }
    }
    
    private func findingButton(_ type: FieldCheckFindingType) -> some View {
        Button {
            model.addFinding(
                animalID: animalID,
                sessionID: sessionID,
                type: type,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } label: {
            Label(type.label, systemImage: type.systemImage)
        }
        .buttonStyle(.bordered)
    }
}
