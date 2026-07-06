//
//  HerdCollaborationView.swift
//  yaHerd
//

import SwiftUI

struct HerdCollaborationView: View {
  @Environment(\.herdRepository) private var herdRepository
  @Environment(\.herdSharingRepository) private var herdSharingRepository
  @Environment(\.cloudKitShareInvitationCoordinator) private var shareInvitationCoordinator
  @Environment(\.herdSharingSyncCoordinator) private var sharingSyncCoordinator
  @Environment(\.herdCollaborationWritePolicy) private var writePolicy
  @Environment(\.herdSharingConflictReviewStore) private var conflictReviewStore
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
        sharingAccessSection(sharingRepository: herdSharingRepository)
        coreDataBoundarySection
        conflictPolicySection
        shareInvitationSection(
          herdRepository: herdRepository,
          sharingRepository: herdSharingRepository
        )
        sharedBridgeImportSection(
          herdRepository: herdRepository,
          sharingRepository: herdSharingRepository
        )
        sharedBridgeSyncSection(
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
      viewModel.loadLatestConflictReview(from: conflictReviewStore)
      await viewModel.refreshSharingAccess(
        using: herdSharingRepository,
        storageMode: preferences.syncMode.herdStorageMode,
        writePolicy: writePolicy
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

  private func sharingAccessSection(sharingRepository: any HerdSharingRepository) -> some View {
    Section("Sharing Access") {
      if let access = viewModel.sharingAccess {
        LabeledContent("Bridge Location", value: access.locationDescription)
        LabeledContent("Permission", value: access.permissionDescription)
        LabeledContent("Participants", value: access.participantDescription)
        LabeledContent(
          "Can Export Local Edits",
          value: access.canExportLocalChangesToBridge ? "Yes" : "No"
        )
      } else {
        LabeledContent("Permission", value: "Unknown")
      }

      if let sharingAccessMessage = viewModel.sharingAccessMessage {
        Text(sharingAccessMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let writePolicy {
        let snapshot = writePolicy.snapshot
        LabeledContent(
          "Local Edit Policy",
          value: snapshot.allowsLocalMutations ? "Allowed" : "Blocked"
        )
        Text(snapshot.statusDescription)
          .font(.caption)
          .foregroundStyle(.secondary)

        if let lastBlockedMutationReason = snapshot.lastBlockedMutationReason {
          Text("Last blocked edit: \(lastBlockedMutationReason.displayName)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let sharingSyncCoordinator {
        LabeledContent(
          "Access Refresh",
          value: sharingSyncCoordinator.isRefreshingSharingAccess ? "Running" : "Idle"
        )

        if let trigger = sharingSyncCoordinator.lastAccessRefreshTriggerDescription {
          LabeledContent("Last Access Trigger", value: trigger)
        }

        if let lastFinishedAt = sharingSyncCoordinator.lastAccessRefreshFinishedAt {
          LabeledContent("Access Last Checked", value: formattedSyncDate(lastFinishedAt))
        }

        if let skippedReason = sharingSyncCoordinator.lastAccessRefreshSkippedReason {
          Text(skippedReason)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let errorMessage = sharingSyncCoordinator.lastAccessRefreshErrorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Button {
        Task {
          if let sharingSyncCoordinator {
            await sharingSyncCoordinator.refreshSharingAccessNow(
              trigger: .manual,
              minimumInterval: 0
            )
          }
          await viewModel.refreshSharingAccess(
            using: sharingRepository,
            storageMode: preferences.syncMode.herdStorageMode,
            writePolicy: writePolicy
          )
        }
      } label: {
        Label("Refresh Access", systemImage: "person.crop.circle.badge.checkmark")
      }
      .disabled(
        viewModel.herd == nil || preferences.syncMode.herdStorageMode != .iCloud
          || sharingSyncCoordinator?.isRefreshingSharingAccess == true)

      Text(
        "Read-only CloudKit participants can import shared changes. yaHerd now refreshes CloudKit share access on launch, foreground, major tab openings, share invitation receipt, and write-policy preflight. It blocks read-only local edit attempts before SwiftData writes and also refuses to export local changes back into the shared bridge."
      )
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

  private var conflictPolicySection: some View {
    Section("Conflict Handling") {
      LabeledContent("Existing local records", value: "Reported on import")
      LabeledContent("Shared deletes", value: "Skipped when local record is newer")

      if let conflictReview = latestConflictReview {
        LabeledContent("Last Conflict Source", value: conflictReview.sourceDescription)
        LabeledContent("Last Checked", value: formattedSyncDate(conflictReview.detectedAt))
        LabeledContent(
          "Updated Existing Local Records",
          value: conflictReview.existingLocalRecordUpdateCount.formatted()
        )
        LabeledContent(
          "Skipped Shared Deletes",
          value: conflictReview.preventedDeleteCount.formatted()
        )

        Text(conflictReview.summary)
          .font(.caption)
          .foregroundStyle(.secondary)

        NavigationLink {
          HerdSharingConflictReviewDetailView(review: conflictReview)
        } label: {
          Label("Review Conflict Details", systemImage: "exclamationmark.triangle")
        }

        if !conflictReview.preventedDeleteConflicts.isEmpty {
          DisclosureGroup("Skipped Shared Deletes") {
            ForEach(conflictReview.preventedDeleteConflicts) { conflict in
              VStack(alignment: .leading, spacing: 4) {
                Text(conflict.displayEntityName)
                  .font(.caption.weight(.semibold))
                Text("Record ID: \(conflict.publicID.uuidString)")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text("Local edit: \(formattedSyncDate(conflict.localModifiedAt))")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text("Shared delete: \(formattedSyncDate(conflict.sharedDeletedAt))")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Button("Clear Latest Conflict Report") {
          if let sharingSyncCoordinator {
            sharingSyncCoordinator.clearConflictReview()
            viewModel.loadLatestConflictReview(from: conflictReviewStore)
          } else {
            viewModel.clearConflictReview(in: conflictReviewStore)
          }
        }

        if let history = conflictReviewStore?.reviewHistory, history.count > 1 {
          DisclosureGroup("Conflict History") {
            ForEach(history.dropFirst()) { review in
              NavigationLink {
                HerdSharingConflictReviewDetailView(review: review)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(review.sourceDescription)
                    .font(.caption.weight(.semibold))
                  Text(formattedSyncDate(review.detectedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  Text(review.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }

          Button("Clear All Conflict Reports", role: .destructive) {
            if let sharingSyncCoordinator {
              sharingSyncCoordinator.clearAllConflictReviews()
              viewModel.loadLatestConflictReview(from: conflictReviewStore)
            } else {
              viewModel.clearAllConflictReviews(in: conflictReviewStore)
            }
          }
        }
      } else {
        LabeledContent("Last Conflict Report", value: "None")
      }

      Text(
        "yaHerd now persists conflict reports locally, survives app restarts, keeps a short history of prior reports, and provides a detail screen for skipped shared deletes. This is still conflict reporting and guardrail logic, not a full manual merge UI."
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
              storageMode: preferences.syncMode.herdStorageMode,
              conflictReviewStore: conflictReviewStore
            )
            if accepted {
              shareInvitationCoordinator?.clearPendingInvitation()
              viewModel.load(
                herdRepository: herdRepository,
                sharingRepository: sharingRepository,
                storageMode: preferences.syncMode.herdStorageMode
              )
              if let sharingSyncCoordinator {
                await sharingSyncCoordinator.refreshSharingAccessNow(
                  trigger: .shareInvitationAccepted,
                  minimumInterval: 0
                )
              }
              await viewModel.refreshSharingAccess(
                using: sharingRepository,
                storageMode: preferences.syncMode.herdStorageMode,
                writePolicy: writePolicy
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
            storageMode: preferences.syncMode.herdStorageMode,
            conflictReviewStore: conflictReviewStore
          )
          if imported {
            viewModel.load(
              herdRepository: herdRepository,
              sharingRepository: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode
            )
            await viewModel.refreshSharingAccess(
              using: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode,
              writePolicy: writePolicy
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

  private func sharedBridgeSyncSection(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository
  ) -> some View {
    Section("Shared Bridge Sync") {
      Button {
        Task {
          let synced: Bool
          if let sharingSyncCoordinator {
            synced = await sharingSyncCoordinator.syncNow(trigger: .manual)
          } else {
            synced = await viewModel.syncSharedBridgeData(
              using: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode,
              conflictReviewStore: conflictReviewStore
            )
          }

          if synced {
            viewModel.load(
              herdRepository: herdRepository,
              sharingRepository: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode
            )
            await viewModel.refreshSharingAccess(
              using: sharingRepository,
              storageMode: preferences.syncMode.herdStorageMode,
              writePolicy: writePolicy
            )
          }
        }
      } label: {
        Label("Sync Shared Data", systemImage: "arrow.triangle.2.circlepath.icloud")
      }
      .disabled(
        viewModel.isSharingActionInProgress || sharingSyncCoordinator?.isSyncing == true
          || viewModel.herd == nil || preferences.syncMode.herdStorageMode != .iCloud)

      if let sharingSyncCoordinator {
        LabeledContent(
          "Lifecycle Sync",
          value: sharingSyncCoordinator.isSyncing ? "Running" : "Idle"
        )

        if let trigger = sharingSyncCoordinator.lastTriggerDescription {
          LabeledContent("Last Trigger", value: trigger)
        }

        if let lastFinishedAt = sharingSyncCoordinator.lastFinishedAt {
          LabeledContent("Last Finished", value: formattedSyncDate(lastFinishedAt))
        }

        if let lastSkippedReason = sharingSyncCoordinator.lastSkippedReason {
          Text(lastSkippedReason)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let lastErrorMessage = sharingSyncCoordinator.lastErrorMessage {
          Text(lastErrorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Text(
        "Exports the current SwiftData herd into the Core Data sharing bridge, then imports available accepted shared records back into SwiftData. This now also runs automatically on app launch and when the app returns to the foreground, with debounce/throttle protection so CloudKit is not hammered."
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
            storageMode: preferences.syncMode.herdStorageMode,
            conflictReviewStore: conflictReviewStore
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

  private func formattedSyncDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
  }

  private var latestConflictReview: HerdSharingConflictReview? {
    sharingSyncCoordinator?.lastConflictReview
      ?? viewModel.latestConflictReview
      ?? conflictReviewStore?.latestReview
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
