//
//  AnimalFormFieldSections.swift
//

import SwiftUI

struct DistinguishingFeaturesSection: View {
    @Binding var features: [DistinguishingFeature]

    var body: some View {
        Section("Distinguishing Features") {
            ForEach(features.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Feature", text: $features[index].description)

                    if features.count > 1 {
                        Menu {
                            Button("Move Up", systemImage: "chevron.up") {
                                moveFeature(from: index, to: index - 1)
                            }
                            .disabled(index == features.startIndex)

                            Button("Move Down", systemImage: "chevron.down") {
                                moveFeature(from: index, to: index + 1)
                            }
                            .disabled(index == features.index(before: features.endIndex))
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Change feature order")
                    }
                }
            }
            .onDelete { offsets in
                features.remove(atOffsets: offsets)
                normalizeFeatureOrder()
            }
            .onMove { source, destination in
                features.move(fromOffsets: source, toOffset: destination)
                normalizeFeatureOrder()
            }

            Button {
                features.append(DistinguishingFeature(description: "", order: features.count))
                normalizeFeatureOrder()
            } label: {
                HStack {
                    Text("Note Distinguishing Feature(s)")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .onAppear {
            features = features.orderedDistinguishingFeatures
            normalizeFeatureOrder()
        }
    }

    private func moveFeature(from source: Int, to destination: Int) {
        guard features.indices.contains(source), features.indices.contains(destination) else { return }
        let feature = features.remove(at: source)
        features.insert(feature, at: destination)
        normalizeFeatureOrder()
    }

    private func normalizeFeatureOrder() {
        features = features.enumerated().map { index, feature in
            DistinguishingFeature(
                id: feature.id,
                description: feature.description,
                order: index
            )
        }
    }
}

struct DateFieldRow: View {
    let title: String
    @Binding var date: Date
    let quickSelections: [AnimalEditorContext.DateQuickSelection]
    
    @State private var isPresentingPicker = false
    
    init(title: String, date: Binding<Date>, quickSelections: [AnimalEditorContext.DateQuickSelection] = []) {
        self.title = title
        self._date = date
        self.quickSelections = quickSelections
    }

    private var formattedDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    
    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            LabeledContent(title) {
                Text(formattedDate)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            NavigationStack {
                Form {
                    if !quickSelections.isEmpty {
                        Section("Quick Select") {
                            ForEach(quickSelections) { selection in
                                Button(selection.title) {
                                    date = selection.resolvedDate()
                                }
                            }
                        }
                    }

                    Section {
                        DatePicker(
                            title,
                            selection: $date,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    } footer: {
                        Text("Selected date: \(formattedDate)")
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresentingPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct AnimalStatusEditorSection: View {
    @Binding var status: AnimalStatus
    @Binding var statusReferenceID: UUID?
    @Binding var saleDate: Date
    @Binding var salePriceText: String
    @Binding var reasonSold: String
    @Binding var deathDate: Date
    @Binding var causeOfDeath: String
    
    let availableStatusReferences: [AnimalStatusReferenceOption]
    
    var body: some View {
        Group {
            if !availableStatusReferences.isEmpty || statusReferenceID != nil {
                Section {
                    Picker("Referenced Status", selection: $statusReferenceID) {
                        Text("None").tag(UUID?.none)
                        
                        ForEach(availableStatusReferences) { reference in
                            Text(reference.name)
                                .tag(UUID?.some(reference.id))
                        }
                    }
                } header: {
                    Text("Status Reference")
                } footer: {
                    Text(
                        "Use a referenced status definition for user-defined herd statuses. The base herd status remains Active, Sold, or Dead."
                    )
                }
            }
            
            switch status {
            case .active:
                EmptyView()
                
            case .sold:
                Section("Sale Details") {
                    DateFieldRow(title: "Sale Date", date: $saleDate)
                    TextField("Sale Price", text: $salePriceText)
                        .keyboardType(.decimalPad)
                    TextField("Reason Sold", text: $reasonSold, axis: .vertical)
                        .lineLimit(2...4)
                }
                
            case .dead:
                Section("Death Details") {
                    DateFieldRow(title: "Death Date", date: $deathDate)
                    TextField("Cause of Death", text: $causeOfDeath, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }
}

struct ParentFieldRow: View {
    let title: String
    @Binding var value: String
    let onClear: () -> Void
    let type: ParentPickerType
    @Binding var activePicker: ParentPickerType?
    
    var body: some View {
        Button {
            activePicker = type
        } label: {
            LabeledContent(title) {
                Text(value.isEmpty ? "Select" : value)
                    .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !value.isEmpty {
                Button("Clear", role: .destructive) {
                    onClear()
                }
            }
        }
    }
}

