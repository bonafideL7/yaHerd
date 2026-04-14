import SwiftData
import SwiftUI

struct PastureDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var model = PastureDetailViewModel()

    private let pastureID: UUID

    init(pastureID: UUID) {
        self.pastureID = pastureID
    }

    init(pasture: Pasture) {
        self.init(pastureID: pasture.publicID)
    }

    private var repository: any PastureRepository {
        SwiftDataPastureRepository(context: context)
    }


    var body: some View {
        Group {
            if let detail = model.detail {
                Form {
                    pastureInfoSection(detail)
                    stockingSection(detail)
                    animalsSection
                }
            } else if model.hasLoaded {
                ContentUnavailableView(
                    "Pasture unavailable",
                    systemImage: "leaf",
                    description: Text("The selected pasture could not be loaded.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.detail?.name ?? "Pasture")
        .toolbar {
            if model.isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(pastureID: pastureID, using: repository)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelEditing()
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        model.beginEditing()
                    }
                    .disabled(model.detail == nil)
                }
            }
        }
        .task(id: pastureID) {
            model.load(pastureID: pastureID, using: repository)
        }
        .alert("Can’t Save", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func pastureInfoSection(_ detail: PastureDetailSnapshot) -> some View {
        Section("Pasture Info") {
            if model.isEditing {
                TextField("Name", text: formNameBinding)

                HStack {
                    Text("Acreage")
                    Spacer()
                    TextField("acres", text: formAcreageBinding)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            } else {
                Text("Active Animals: \(detail.activeAnimalCount)")

                HStack {
                    if let acreage = detail.acreage {
                        Text("Acreage: \(acreage, format: .number)")
                    }

                    Spacer()

                    if let usableAcreage = detail.usableAcreage,
                       usableAcreage != detail.acreage {
                        Text("Usable Acres: \(usableAcreage, format: .number)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stockingSection(_ detail: PastureDetailSnapshot) -> some View {
        let metrics = detail.metrics

        Section("Stocking") {
            if model.isEditing {
                HStack {
                    Text("Usable Acres")
                    Spacer()
                    TextField("usable acres", text: formUsableAcreageBinding)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }

                HStack {
                    Text("Target Acres/Head")
                    Spacer()
                    TextField("rate", text: formTargetAcresPerHeadBinding)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            } else {
                if let capacityHead = metrics.capacityHead {
                    Text("Capacity: \(capacityHead, format: .number.precision(.fractionLength(2)))")
                }

                Text(
                    "Stocking Rate: \(metrics.acresPerHead, format: .number.precision(.fractionLength(2))) acres/head"
                )

                if let targetAcresPerHead = metrics.targetAcresPerHead {
                    Text(
                        "Target Rate: \(targetAcresPerHead, format: .number.precision(.fractionLength(2))) acres/head"
                    )
                }

                HStack {
                    if let utilizationPercent = metrics.utilizationPercent {
                        Text(
                            "Utilization: \(utilizationPercent, format: .percent.precision(.fractionLength(2)))"
                        )
                        .foregroundStyle(
                            utilizationPercent > 0.9 ? .red :
                            utilizationPercent > 0.75 ? .orange : .green
                        )
                    }

                    Spacer()

                    if metrics.isOverstocked {
                        Label("Overstocked", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if metrics.isUnderutilized {
                        Label("Underutilized", systemImage: "arrow.down.left.and.arrow.up.right")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var animalsSection: some View {
        if !model.residentAnimals.isEmpty {
            Section("Animals") {
                ForEach(model.residentAnimals) { animal in
                    NavigationLink {
                        AnimalDetailView(animalID: animal.id)
                    } label: {
                        let definition = tagColorLibrary.resolvedDefinition(for: animal)

                        AnimalTagView(
                            tagNumber: animal.displayTagNumber,
                            color: definition.color,
                            colorName: definition.name
                        )
                    }
                }
            }
        }
    }

    private var formNameBinding: Binding<String> {
        Binding(
            get: { model.form.name },
            set: { model.form.name = $0 }
        )
    }

    private var formAcreageBinding: Binding<String> {
        Binding(
            get: { model.form.acreageText },
            set: { model.form.acreageText = $0 }
        )
    }

    private var formUsableAcreageBinding: Binding<String> {
        Binding(
            get: { model.form.usableAcreageText },
            set: { model.form.usableAcreageText = $0 }
        )
    }

    private var formTargetAcresPerHeadBinding: Binding<String> {
        Binding(
            get: { model.form.targetAcresPerHeadText },
            set: { model.form.targetAcresPerHeadText = $0 }
        )
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
}
