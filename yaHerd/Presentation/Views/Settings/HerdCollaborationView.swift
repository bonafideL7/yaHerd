//
//  HerdCollaborationView.swift
//  yaHerd
//

import SwiftUI

struct HerdCollaborationView: View {
    @Environment(\.herdRepository) private var herdRepository
    @Environment(\.herdSharingRepository) private var herdSharingRepository
    @Environment(\.cloudKitShareInvitationCoordinator) private var shareInvitationCoordinator
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
                shareInvitationSection(sharingRepository: herdSharingRepository)
                shareActionSection(sharingRepository: herdSharingRepository)
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

    private func shareInvitationSection(sharingRepository: any HerdSharingRepository) -> some View {
        Section("Pending Share Invitation") {
            if let invitation = shareInvitationCoordinator?.pendingSummary {
                LabeledContent("Owner", value: invitation.displayOwnerName)
                LabeledContent("Container", value: invitation.displayContainerIdentifier)
                LabeledContent("Share Record", value: invitation.shareRecordName)
                LabeledContent("Root Record", value: invitation.displayRootRecordName)

                Button {
                    Task {
                        await viewModel.acceptPendingInvitation(
                            invitation,
                            using: sharingRepository,
                            storageMode: preferences.syncMode.herdStorageMode
                        )
                    }
                } label: {
                    Label("Accept Invitation", systemImage: "tray.and.arrow.down")
                }
                .disabled(viewModel.isSharingActionInProgress)

                Button("Clear Pending Invitation", role: .destructive) {
                    shareInvitationCoordinator?.clearPendingInvitation()
                    viewModel.clearMessages()
                }
            } else {
                ContentUnavailableView(
                    "No Pending Invitation",
                    systemImage: "tray",
                    description: Text("Accepted CloudKit share links will appear here after iOS hands the invitation metadata to yaHerd.")
                )
            }
        }
    }

    private func shareActionSection(sharingRepository: any HerdSharingRepository) -> some View {
        Section("Share Actions") {
            Button {
                Task {
                    await viewModel.startSharing(
                        using: sharingRepository,
                        storageMode: preferences.syncMode.herdStorageMode
                    )
                }
            } label: {
                Label("Share Herd", systemImage: "square.and.arrow.up")
            }
            .disabled(!viewModel.canStartSharing)

            Text("The share button is intentionally blocked until the sharing repository can create a real CloudKit share for the Herd root and persist share changes back to storage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nextImplementationSection: some View {
        Section("Next Implementation Step") {
            Label("Implement the persistent-store adapter", systemImage: "square.and.arrow.up")

            Text("The app now stores accepted invitation metadata long enough for the collaboration screen to review it. The remaining implementation is the storage adapter that actually accepts the CloudKit share and imports shared herd data.")
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
