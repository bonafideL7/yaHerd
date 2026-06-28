//
//  AnimalTagEditView.swift
//

import SwiftUI

struct AnimalTagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    
    @State private var number: String
    @State private var colorID: UUID?
    @State private var isPrimary: Bool
    
    private let title: String
    private let saveButtonTitle: String
    private let showsPrimaryToggle: Bool
    private let onSave: (String, UUID?, Bool) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    private var previewColorDefinition: TagColorSnapshot {
        tagColorLibrary.resolvedDefinition(tagColorID: colorID)
    }

    private var previewTagNumber: String {
        number.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    init(
        initialNumber: String = "",
        initialColorID: UUID? = nil,
        initialIsPrimary: Bool = false,
        title: String = "Add Tag",
        saveButtonTitle: String = "Save",
        showsPrimaryToggle: Bool = false,
        onSave: @escaping (String, UUID?, Bool) -> Void
    ) {
        _number = State(initialValue: initialNumber)
        _colorID = State(initialValue: initialColorID)
        _isPrimary = State(initialValue: initialIsPrimary)
        self.title = title
        self.saveButtonTitle = saveButtonTitle
        self.showsPrimaryToggle = showsPrimaryToggle
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Number") {
                    TextField("Number or ID", text: $number)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2)
                }
                
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tagColorLibrary.colors) { def in
                            let isSelected = def.id == tagColorLibrary.resolvedColorID(colorID)

                            Circle()
                                .fill(def.color)
                                .frame(height: 44)
                                .overlay {
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 3)
                                    }
                                }
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(def.name) tag color")
                            .accessibilityValue(isSelected ? "Selected" : "")
                            .onTapGesture {
                                colorID = def.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .onAppear {
                        colorID = tagColorLibrary.resolvedColorID(colorID)
                    }
                } header: {
                    Text("Color")
                }
                
                if showsPrimaryToggle {
                    Section {
                        Toggle("Use as primary tag", isOn: $isPrimary)
                    } footer: {
                        Text("Primary tags become the animal's display tag.")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    AnimalTagView(
                        tagNumber: previewTagNumber,
                        color: previewColorDefinition.color,
                        colorName: previewColorDefinition.name,
                        size: .regular
                    )
                    .accessibilityLabel("\(title) preview")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton(accessibilityLabel: saveButtonTitle) {
                        onSave(
                            number.trimmingCharacters(in: .whitespacesAndNewlines),
                            tagColorLibrary.resolvedColorID(colorID),
                            isPrimary
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
