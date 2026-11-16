import SwiftUI

/// Presented before constructing any Herd-bound feature graph. An empty local
/// inventory may mean CloudKit is still importing, not that the account owns
/// no Herds.
struct CloudKitHerdChooserView: View {
    @Environment(\.scenePhase) private var scenePhase

    let context: CloudKitHerdSelectionContext
    let onSelect: @MainActor (UUID) async throws -> Void

    @State private var herds: [AccessibleHerd] = []
    @State private var errorMessage: String?
    @State private var newHerdName = ""
    @State private var showingCreate = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                if herds.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Herds Available Yet", systemImage: "icloud.and.arrow.down")
                        } description: {
                            Text("iCloud may still be importing existing or joined Herds. " +
                                 "Refresh to check again. Creating a Herd starts a separate " +
                                 "new Herd; it does not restore or join an existing one.")
                        }
                    }
                }

                if !ownedHerds.isEmpty {
                    Section("My Herds") {
                        ForEach(ownedHerds) { herd in
                            herdButton(herd)
                        }
                    }
                }

                if !sharedHerds.isEmpty {
                    Section("Shared With Me") {
                        ForEach(sharedHerds) { herd in
                            herdButton(herd)
                        }
                    }
                }

                Section {
                    Button {
                        newHerdName = ""
                        showingCreate = true
                    } label: {
                        Label("Create New Herd", systemImage: "plus")
                    }
                    .disabled(isWorking)

                    Text("Herds shared with your Apple Account appear here after " +
                         "you accept their invitation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Select Herd")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        refresh()
                    }
                    .disabled(isWorking)
                }
            }
            .task {
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .alert("Create New Herd", isPresented: $showingCreate) {
                TextField("Herd name", text: $newHerdName)
                Button("Create") {
                    Task { await create() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This creates a new owned Herd, not a replacement for " +
                     "data that may still be importing from iCloud.")
            }
        }
    }

    private var ownedHerds: [AccessibleHerd] {
        herds.filter { $0.category == .owned }
    }

    private var sharedHerds: [AccessibleHerd] {
        herds.filter { $0.category == .shared }
    }

    private func herdButton(_ herd: AccessibleHerd) -> some View {
        Button {
            Task { await select(herd.id) }
        } label: {
            HStack {
                Text(herd.name)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .disabled(isWorking)
    }

    private func refresh() {
        guard !isWorking else { return }
        do {
            herds = try context.fetchHerds()
            errorMessage = nil
        } catch {
            // Retain the last valid inventory on transient read failures.
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ id: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await onSelect(id)
        } catch {
            errorMessage = error.localizedDescription
            refreshAfterFailure()
        }
    }

    private func create() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await context.createOwnedHerd(named: newHerdName)
            try await onSelect(created.id)
        } catch {
            errorMessage = error.localizedDescription
            refreshAfterFailure()
        }
    }

    private func refreshAfterFailure() {
        // Creation may have committed even if opening the new graph fails.
        // Show that Herd so a retry never creates a duplicate.
        if let updated = try? context.fetchHerds() {
            herds = updated
        }
    }
}
