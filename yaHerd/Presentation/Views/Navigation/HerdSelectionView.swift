import SwiftUI

/// Shown when no Herd is selected and as the explicit Herd switcher.
struct HerdSelectionView: View {
    let lifecycle: AppHerdLifecycle
    let allowsDismiss: Bool
    let onSelect: (UUID) -> Void
    let onCreate: (String) async -> Void
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    @State private var isShowingCreate = false
    @State private var isExplainingJoin = false
    @State private var newHerdName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Available Herds") {
                    if lifecycle.availableHerds.isEmpty {
                        if lifecycle.isMirroring {
                            Label("Waiting for iCloud Herds", systemImage: "icloud.and.arrow.down")
                            Text("Herds may still be importing. Refresh to check again, or create an owned Herd deliberately.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView(
                                "No Herds",
                                systemImage: "tray",
                                description: Text("Create a Herd to begin.")
                            )
                        }
                    } else {
                        ForEach(lifecycle.availableHerds) { herd in
                            Button {
                                onSelect(herd.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: herd.category == .owned ? "person.crop.circle" : "person.2")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(herd.name)
                                            .foregroundStyle(.primary)
                                        Text(herd.category == .owned ? "Owned" : "Shared")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if lifecycle.selectedHerdID == herd.id {
                                        Image(systemName: "checkmark")
                                            .accessibilityLabel("Selected")
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        newHerdName = ""
                        isShowingCreate = true
                    } label: {
                        Label("Create Herd", systemImage: "plus")
                    }
                    .disabled(lifecycle.isCreating)

                    Button {
                        isExplainingJoin = true
                    } label: {
                        Label("Join Herd", systemImage: "person.2.badge.plus")
                    }
                    Button("Refresh Herds", systemImage: "arrow.clockwise") {
                        onRefresh()
                    }
                }

                if lifecycle.isCreating {
                    ProgressView("Creating Herd…")
                }
                if let error = lifecycle.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Herds")
            .toolbar {
                if allowsDismiss {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDismiss)
                    }
                }
            }
            .refreshable { onRefresh() }
            .alert("Create Herd", isPresented: $isShowingCreate) {
                TextField("Herd name", text: $newHerdName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newHerdName
                    Task { await onCreate(name) }
                }
            } message: {
                Text("Choose a name for the new owned Herd.")
            }
            .alert("Join Herd", isPresented: $isExplainingJoin) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Joining another owner's Herd requires an invitation. Invitation acceptance is part of the upcoming sharing stage and is not available in this build.")
            }
        }
    }
}
