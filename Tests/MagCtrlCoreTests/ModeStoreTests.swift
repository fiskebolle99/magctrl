import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Persisted mode")
struct ModeStoreTests {
  @Test func missingStateDefaultsToAuto() throws {
    try withTemporaryStore { store, _ in
      #expect(store.load() == .auto)
    }
  }

  @Test(arguments: LEDMode.allCases)
  func modeRoundTrips(_ mode: LEDMode) throws {
    try withTemporaryStore { store, url in
      try store.save(mode)
      #expect(store.load() == mode)
      #expect(try String(contentsOf: url, encoding: .utf8) == "\(mode.rawValue)\n")
    }
  }

  @Test func invalidStateFailsClosedToAuto() throws {
    try withTemporaryStore { store, url in
      try Data("green\nextra\n".utf8).write(to: url)
      #expect(store.load() == .auto)
    }
  }

  @Test func saveLeavesRootOnlyModeBitsAndNoTemporarySibling() throws {
    try withTemporaryStore { store, url in
      try store.save(.amber)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let permissions = attributes[.posixPermissions] as? NSNumber
      #expect(permissions?.intValue == 0o600)

      let siblings = try FileManager.default.contentsOfDirectory(
        at: url.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
      )
      #expect(siblings.map(\.lastPathComponent) == ["mode"])
    }
  }

  private func withTemporaryStore(
    _ body: (ModeStore, URL) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("magctrl-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("mode")
    try body(ModeStore(url: url), url)
  }
}
