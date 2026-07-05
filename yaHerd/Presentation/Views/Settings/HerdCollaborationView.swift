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
        coreDataBoundarySection
        shareInvitationSection(
          herdRepository: herdRepository,
          sharingRepository: herdSharingRepository
        )
        sharedBridgeImportSection(
          herdRepository: herdRepository,
          sharingRepository: herdSharingRepository
        )
        shareActionSection(sharingRepository: herdSharingRepository)
      } else {
        Section("Herd") {
          ContentUnavailableView(
            "Herd Repository Missing",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(
              "The app could not open herd collaboration settings because no herd repository was provided."
            )
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
    .sheet(item: $viewModel.systemShare) { systemShare in
      HerdCloudSharingControllerView(systemShare: systemShare)
        .ignoresSafeArea()
        .onDisappear {
          viewModel.dismissSystemShare()
        }
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
      LabeledContent(
        "Share UI", value: viewModel.readiness?.shareActionEnabled == true ? "Available" : "Blocked"
      )

      if let readiness = viewModel.readiness {
        LabeledContent("Status", value: readiness.title)
      }

      Text(viewModel.readiness?.message ?? readinessMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var coreDataBoundarySection: some View {
    Section("Core Data Boundary") {
      LabeledContent("App data store", value: "SwiftData")
      LabeledContent("Sharing bridge", value: "Core Data + CloudKit")
      LabeledContent(
        "Bridge scope",
        value:
          "Herd root + support records + pasture groups + pastures + animals + movement/status/health/pregnancy + working data + field checks"
      )
      LabeledContent(
        "SwiftData import",
        value:
          "Herd root + support records + pasture groups + pastures + animals + movement/status/health/pregnancy + working data + field checks"
      )

      Text(
        "Core Data is intentionally isolated behind the sharing repository. SwiftData remains the app data store. The bridge now mirrors tag colors, animal tags, custom status references, pasture groups, pastures, animals, movement records, status history, health records, pregnancy checks, working protocol templates, working sessions, queue items, treatment records, and field checks into CloudKit sharing and can import those accepted shared records back into SwiftData."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func shareInvitationSection(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository
  ) -> some View {
    Section("Pending Share Invitation") {
      if let invitation = shareInvitationCoordinator?.pendingInvitation {
        let summary = invitation.summary

        LabeledContent("Owner", value: summary.displayOwnerName)
        LabeledContent("Container", value: summary.displayContainerIdentifier)
        LabeledContent("Share Record", value: summary.shareRecordName)
        LabeledContent("Root Record", value: summary.displayRootRecordName)

        Button {
          Task {
            let accepted = await viewModel.acceptPendingInvitation(
              invitation,
              using: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode
            )
            if accepted {
              shareInvitationCoordinator?.clearPendingInvitation()
              viewModel.load(
                herdRepository: herdRepository,
                sharingRepository: sharingRepository,
                storageMode: preferences.syncMode.herdStorageMode
              )
            }
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
          description: Text(
            "Accepted CloudKit share links will appear here after iOS hands the invitation metadata to yaHerd."
          )
        )
      }
    }
  }

  private func sharedBridgeImportSection(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository
  ) -> some View {
    Section("Shared Bridge Import") {
      Button {
        Task {
          let imported = await viewModel.importSharedBridgeData(
            using: sharingRepository,
            storageMode: preferences.syncMode.herdStorageMode
          )
          if imported {
            viewModel.load(
              herdRepository: herdRepository,
              sharingRepository: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode
            )
          }
        }
      } label: {
        Label("Import Shared Data", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(
        viewModel.isSharingActionInProgress || preferences.syncMode.herdStorageMode != .iCloud)

      Text(
        "Use this after accepting a share or after the Core Data bridge receives remote shared changes. This pass imports the shared herd root, support records, pasture groups, pastures, animals, movement records, status history, health records, pregnancy checks, working protocol templates, working sessions, queue items, treatment records, and field checks into SwiftData so the normal app screens can display them."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
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

      Text(
        "This mirrors the current SwiftData herd, support records, pasture groups, pastures, animals, movement records, status history, health records, pregnancy checks, working protocol templates, working sessions, queue items, treatment records, and field checks into the isolated Core Data bridge, then opens Apple's CloudKit sharing sheet. It does not move yaHerd's normal app data out of SwiftData."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var readinessMessage: String {
    switch preferences.syncMode {
    case .localOnly:
      "Enable iCloud Sync before exposing a share action. Local-only stores cannot invite other iCloud users."
    case .iCloud:
      "The Core Data sharing bridge can create or accept the Herd share root while the app continues to use SwiftData for normal records."
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
