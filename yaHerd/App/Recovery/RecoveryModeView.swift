//
//  RecoveryModeView.swift
//  yaHerd
//

import SwiftUI

struct RecoveryModeView: View {
  @ObservedObject var controller: RecoveryModeController
  @State private var isExporting = false

  var body: some View {
    List {
      Section {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text("Recovery Mode Is Read-Only")
              .font(.headline)
            Text("Data changes cannot be saved for this launch.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "externaldrive.badge.exclamationmark")
            .foregroundStyle(.red)
        }
      }

      Section("Storage State") {
        LabeledContent("Active Store", value: "In-memory recovery store")
        LabeledContent("Data Mutations", value: "Disabled")
        LabeledContent(
          "Entered Recovery",
          value: controller.context.enteredAt.formatted(date: .abbreviated, time: .standard)
        )
      }

      Section("Storage Diagnostics") {
        if controller.diagnosticsErrorMessage == nil {
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

        }

        if let diagnosticsErrorMessage = controller.diagnosticsErrorMessage {
          Text(diagnosticsErrorMessage)
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

      Section("Recovery Export") {
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
          "Creates a TAR archive with storage diagnostics, Core Data SQLite/WAL/SHM files, and any recognized legacy yaHerd storage files. Legacy files are preserved without conversion. Keep the archive private."
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

      Section("Read-Only Store Check") {
        Text(
          "Check whether the original Core Data store can open without changing its contents. This does not repair or migrate it. Recovery mode remains read-only until you restart yaHerd."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Button {
          Task { @MainActor in
            await controller.checkPersistentStoreReadOnly()
          }
        } label: {
          if controller.isCheckingPersistentStore {
            Label("Checking Persistent Store…", systemImage: "hourglass")
          } else {
            Label("Check Persistent Store (Read Only)", systemImage: "externaldrive")
          }
        }
        .disabled(controller.isCheckingPersistentStore)

        storeCheckResultView
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
  }

  @ViewBuilder
  private var storeCheckResultView: some View {
    if let storeCheckResult = controller.storeCheckResult {
      switch storeCheckResult {
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
