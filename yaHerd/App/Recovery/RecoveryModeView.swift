//
//  RecoveryModeView.swift
//  yaHerd
//

import SwiftUI

struct RecoveryModeView: View {
  @ObservedObject var controller: RecoveryModeController
  @State private var isExporting = false
  @State private var isShowingRepairConfirmation = false

  var body: some View {
    List {
      Section {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text("Recovery Mode Is Read-Only")
              .font(.headline)
            Text(
              "Data changes cannot be saved. Editing, sharing, and synchronization are disabled for this launch."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "externaldrive.badge.exclamationmark")
            .foregroundStyle(.red)
        }
      }

      Section("Storage State") {
        LabeledContent("Requested Mode", value: controller.context.requestedSyncMode.displayName)
        LabeledContent("Active Store", value: "In-memory recovery store")
        LabeledContent("Data Mutations", value: "Disabled")
        LabeledContent("Sharing and Sync", value: "Disabled")
        LabeledContent(
          "Entered Recovery",
          value: controller.context.enteredAt.formatted(date: .abbreviated, time: .standard))
      }

      Section("Storage Diagnostics") {
        LabeledContent(
          "In-Memory Records",
          value: controller.diagnostics.totalRecoveryRecordCount.formatted()
        )
        LabeledContent(
          "Persistent Store Files Found",
          value: controller.diagnostics.recoverableStoreFiles.count.formatted()
        )
        LabeledContent(
          "Persistent Store File Size",
          value: ByteCountFormatter.string(
            fromByteCount: Int64(controller.diagnostics.recoverableStoreByteCount),
            countStyle: .file
          )
        )
        LabeledContent(
          "Last Refreshed",
          value: controller.diagnostics.generatedAt.formatted(date: .omitted, time: .standard)
        )

        if let countError = controller.diagnostics.recoveryStoreCountError {
          Text("The in-memory record count could not be read: \(countError)")
            .font(.caption)
            .foregroundStyle(.red)
        }

        if !controller.diagnostics.recoverableStoreFiles.isEmpty {
          DisclosureGroup("Store File Inventory") {
            ForEach(controller.diagnostics.recoverableStoreFiles) { file in
              VStack(alignment: .leading, spacing: 3) {
                Text(file.originalFilename)
                  .font(.caption.weight(.semibold))
                Text(
                  ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
            }
          }
        }

        Button {
          controller.refreshDiagnostics()
        } label: {
          Label("Refresh Diagnostics", systemImage: "arrow.clockwise")
        }
      }

      Section("Export Before Repair") {
        Button {
          controller.prepareExport()
          isExporting = controller.exportDocument != nil
        } label: {
          if controller.isPreparingExport {
            Label("Preparing Recovery Export…", systemImage: "hourglass")
          } else {
            Label("Export Storage and Diagnostics", systemImage: "square.and.arrow.up")
          }
        }
        .disabled(controller.isPreparingExport)

        Text(
          "Creates a TAR archive containing storage diagnostics and copies of discoverable yaHerd SwiftData and sharing-bridge store files. Keep the archive private because it may contain herd records."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let exportErrorMessage = controller.exportErrorMessage {
          Text(exportErrorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Startup Failure") {
        Text(controller.context.startupError)
          .font(.caption)
          .textSelection(.enabled)
      }

      Section("Persistent Store Repair") {
        Toggle(isOn: $controller.hasAcknowledgedRepairRisk) {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              "I understand this local-only repair probe may open and migrate the persistent store")
            Text(
              "Recovery mode remains read-only until yaHerd is restarted, even when the store opens successfully."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        Button(role: .destructive) {
          isShowingRepairConfirmation = true
        } label: {
          if controller.isAttemptingRepair {
            Label("Attempting Store Repair…", systemImage: "hourglass")
          } else {
            Label("Attempt Persistent Store Repair", systemImage: "wrench.and.screwdriver")
          }
        }
        .disabled(!controller.hasAcknowledgedRepairRisk || controller.isAttemptingRepair)

        repairResultView
      }
    }
    .navigationTitle("Storage Recovery")
    .navigationBarTitleDisplayMode(.inline)
    .fileExporter(
      isPresented: $isExporting,
      document: controller.exportDocument,
      contentType: RecoveryArchiveDocument.readableContentTypes[0],
      defaultFilename: controller.exportFilename
    ) { result in
      controller.clearPreparedExport()
      if case .failure(let error) = result {
        controller.recordExportFailure(error)
      }
    }
    .confirmationDialog(
      "Attempt Persistent Store Repair?",
      isPresented: $isShowingRepairConfirmation,
      titleVisibility: .visible
    ) {
      Button("Attempt Repair", role: .destructive) {
        controller.attemptPersistentStoreRepair()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "yaHerd will attempt to open the failed persistent store using the production schema migration plan. Export the storage archive first. The current launch will remain read-only."
      )
    }
  }

  @ViewBuilder
  private var repairResultView: some View {
    if let repairResult = controller.repairResult {
      switch repairResult {
      case .succeeded(let message):
        Label(message, systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
      case .failed(let message):
        Label(message, systemImage: "xmark.octagon.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }
}
