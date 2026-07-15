//
//  RecoveryTarArchiveBuilder.swift
//  yaHerd
//

import Foundation

struct RecoveryArchiveEntry: Equatable {
  let path: String
  let data: Data
  let modifiedAt: Date

  init(path: String, data: Data, modifiedAt: Date = .now) {
    self.path = path
    self.data = data
    self.modifiedAt = modifiedAt
  }
}

enum RecoveryTarArchiveBuilder {
  static func makeArchive(entries: [RecoveryArchiveEntry]) throws -> Data {
    var archive = Data()

    for entry in entries.sorted(by: { $0.path < $1.path }) {
      let normalizedPath = sanitize(path: entry.path)
      guard !normalizedPath.isEmpty else { continue }
      guard normalizedPath.utf8.count <= 100 else {
        throw RecoveryArchiveError.pathTooLong(normalizedPath)
      }

      var header = Data(repeating: 0, count: 512)
      writeString(normalizedPath, to: &header, offset: 0, length: 100)
      writeOctal(0o644, to: &header, offset: 100, length: 8)
      writeOctal(0, to: &header, offset: 108, length: 8)
      writeOctal(0, to: &header, offset: 116, length: 8)
      writeOctal(entry.data.count, to: &header, offset: 124, length: 12)
      writeOctal(Int(entry.modifiedAt.timeIntervalSince1970), to: &header, offset: 136, length: 12)
      writeString("        ", to: &header, offset: 148, length: 8)
      header[156] = 48
      writeString("ustar", to: &header, offset: 257, length: 6)
      writeString("00", to: &header, offset: 263, length: 2)
      writeString("yaHerd", to: &header, offset: 265, length: 32)
      writeString("yaHerd", to: &header, offset: 297, length: 32)

      let checksum = header.reduce(0) { $0 + Int($1) }
      writeChecksum(checksum, to: &header, offset: 148, length: 8)

      archive.append(header)
      archive.append(entry.data)

      let remainder = entry.data.count % 512
      if remainder != 0 {
        archive.append(Data(repeating: 0, count: 512 - remainder))
      }
    }

    archive.append(Data(repeating: 0, count: 1024))
    return archive
  }

  private static func sanitize(path: String) -> String {
    path
      .replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/")
      .filter { $0 != "." && $0 != ".." }
      .joined(separator: "/")
  }

  private static func writeString(
    _ value: String,
    to data: inout Data,
    offset: Int,
    length: Int
  ) {
    let bytes = Array(value.utf8.prefix(length))
    data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
  }

  private static func writeOctal(
    _ value: Int,
    to data: inout Data,
    offset: Int,
    length: Int
  ) {
    let digits = String(value, radix: 8)
    let padded = String(repeating: "0", count: max(0, length - digits.count - 1)) + digits + "\0"
    writeString(padded, to: &data, offset: offset, length: length)
  }

  private static func writeChecksum(
    _ value: Int,
    to data: inout Data,
    offset: Int,
    length: Int
  ) {
    let digits = String(value, radix: 8)
    let padded = String(repeating: "0", count: max(0, length - digits.count - 2)) + digits + "\0 "
    writeString(padded, to: &data, offset: offset, length: length)
  }
}

enum RecoveryArchiveError: LocalizedError, Equatable {
  case pathTooLong(String)

  var errorDescription: String? {
    switch self {
    case .pathTooLong(let path):
      "The recovery export could not include a file because its archive path is too long: \(path)"
    }
  }
}
