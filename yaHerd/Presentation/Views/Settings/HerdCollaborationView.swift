//
//  HerdCollaborationView.swift
//  yaHerd
//

import SwiftUI

struct HerdCollaborationView: View {
    @Environment(\.herdRepository) private var herdRepository
    @Environment(\.herdSharingRepository) private var herdSharingRepository
    @State private var viewModel = HerdCollaborationViewModel()

    private let preferences: AppPreferencesProviding

    init(preferences: AppPreferencesProviding = AppPreferences()) {
        self.preferences = preferences
    }

    var body: some View {
        List {
            if let herdRepository, let herdSharingRepository {
                currentHerdSection(
                    herdRepository: herdRepository,
                    sharingRepository: herdSharingRepository
                )
                readinessSection
                nextImplementationSection
            } else {
                Section("Herd") {
                    ContentUnavailableView(
                        "Herd Repository Missing",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("The app could not open herd collaboration settings because no herd repository was provided.")
                    )
                }
            }
        }
        .navigationTitle("Herd Collaboration")
        .task {
            guard let herdRepository, let herdSharingRepository else { return }
            viewModel.load(
                herdRepository: herdRepository,
                sharingRepository: herdSharingRepository,
                storageMode: preferences.syncMode.herdStorageMode
            )
        }
        .alert("Herd Collaboration", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.clearMessages()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func currentHerdSection(
        herdRepository: any HerdRepository,
        sharingRepository: any HerdSharingRepository
    ) -> some View {
        Section("Current Herd") {
            TextField("Herd name", text: $viewModel.draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)

            Button("Save Herd Name") {
                viewModel.saveName(
                    using: herdRepository,
                    sharingRepository: sharingRepository,
                    storageMode: preferences.syncMode.herdStorageMode
                )
            }
            .disabled(!canSaveName)

            if let herd = viewModel.herd {
                LabeledContent("Share Root ID", value: herd.publicID.uuidString)
                LabeledContent("Schema Version", value: herd.schemaVersion.formatted())
            }

            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readinessSection: some View {
        Section("CloudKit Sharing Readiness") {
            LabeledContent("Storage Mode", value: preferences.syncMode.displayName)
            LabeledContent("Share Root", value: viewModel.herd == nil ? "Missing" : "Ready")
            LabeledContent("Share UI", value: viewModel.readiness?.shareActionEnabled == true ? "Available" : "Not wired")

            if let readiness = viewModel.readiness {
                LabeledContent("Status", value: readiness.title)
            }

            Text(viewModel.readiness?.message ?? readinessMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nextImplementationSection: some View {
        Section("Next Implementation Step") {
            Label("Add a CloudKit sharing adapter", systemImage: "square.and.arrow.up")

            Text("The app now has a stable Herd root and repository boundary. The remaining sharing work should live behind this boundary so views do not depend on CloudKit or persistence implementation details.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var readinessMessage: String {
        switch preferences.syncMode {
        case .localOnly:
            "Enable iCloud Sync before exposing a share action. Local-only stores cannot invite other iCloud users."
        case .iCloud:
            "The herd is scoped for collaboration prep. A real CloudKit sharing adapter still needs to create and manage a share for this root herd."
        }
    }

    private var canSaveName: Bool {
        let trimmedDraft = viewModel.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return false }
        return trimmedDraft != viewModel.herd?.name
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            viewModel.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.clearMessages()
            }
        }
    }
}
