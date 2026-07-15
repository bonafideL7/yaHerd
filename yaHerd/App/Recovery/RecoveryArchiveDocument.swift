//
//  RecoveryArchiveDocument.swift
//  yaHerd
//

import SwiftUI
import UniformTypeIdentifiers

struct RecoveryArchiveDocument: FileDocument {
  static var readableContentTypes: [UTType] {
    [UTType(filenameExtension: "tar") ?? .data]
  }

  private let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
