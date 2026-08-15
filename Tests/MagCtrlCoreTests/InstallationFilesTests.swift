import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Installation filesystem effects")
struct InstallationFilesTests {
  @Test func stagedInstallCreatesOnlyExpectedArtifactsAndDefaultsToAuto() throws {
    try withFixture { fixture in
      try fixture.installer.install(from: fixture.source)

      #expect(try Data(contentsOf: fixture.paths.cli) == Data("binary".utf8))
      #expect(try Data(contentsOf: fixture.paths.helper) == Data("binary".utf8))
      #expect(ModeStore(url: fixture.paths.mode).load() == .auto)

      let cliMode = try permissions(of: fixture.paths.cli)
      let helperMode = try permissions(of: fixture.paths.helper)
      let plistMode = try permissions(of: fixture.paths.plist)
      let stateMode = try permissions(of: fixture.paths.stateDirectory)
      #expect(cliMode == 0o755)
      #expect(helperMode == 0o755)
      #expect(plistMode == 0o644)
      #expect(stateMode == 0o755)

      let plist =
        try PropertyListSerialization.propertyList(
          from: Data(contentsOf: fixture.paths.plist),
          format: nil
        ) as? [String: Any]
      #expect(plist?["ProgramArguments"] as? [String] == [fixture.paths.helper.path, "--daemon"])
    }
  }

  @Test func reinstallPreservesSelectedMode() throws {
    try withFixture { fixture in
      try fixture.installer.install(from: fixture.source)
      try ModeStore(url: fixture.paths.mode).save(.off)

      try fixture.installer.install(from: fixture.source)

      #expect(ModeStore(url: fixture.paths.mode).load() == .off)
    }
  }

  @Test func installerRefusesToReplaceSymlinkDestination() throws {
    try withFixture { fixture in
      try FileManager.default.createDirectory(
        at: fixture.paths.cli.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.createSymbolicLink(
        at: fixture.paths.cli,
        withDestinationURL: fixture.source
      )

      #expect(throws: InstallationError.self) {
        try fixture.installer.install(from: fixture.source)
      }
      let values = try fixture.paths.cli.resourceValues(forKeys: [.isSymbolicLinkKey])
      #expect(values.isSymbolicLink == true)
    }
  }

  @Test func uninstallRemovesOnlyOwnedArtifacts() throws {
    try withFixture { fixture in
      try fixture.installer.install(from: fixture.source)
      let unrelated = fixture.paths.stateDirectory.appendingPathComponent("keep-me")
      try Data("user data".utf8).write(to: unrelated)

      try fixture.installer.removeArtifacts()

      #expect(!FileManager.default.fileExists(atPath: fixture.paths.cli.path))
      #expect(!FileManager.default.fileExists(atPath: fixture.paths.helper.path))
      #expect(!FileManager.default.fileExists(atPath: fixture.paths.plist.path))
      #expect(!FileManager.default.fileExists(atPath: fixture.paths.mode.path))
      #expect(try String(contentsOf: unrelated, encoding: .utf8) == "user data")
    }
  }

  @Test func installDoesNotClaimPreexistingSharedDirectories() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("magctrl-owner-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = InstallationPaths(root: root)
    let sharedDirectories = [
      paths.cli.deletingLastPathComponent(),
      paths.helper.deletingLastPathComponent(),
      paths.plist.deletingLastPathComponent(),
    ]
    for directory in sharedDirectories {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let source = root.appendingPathComponent("source-magctrl")
    try Data("binary".utf8).write(to: source)
    var claimed: [String] = []
    let installer = InstallationFiles(paths: paths) { claimed.append($0.path) }

    try installer.install(from: source)

    for directory in sharedDirectories {
      #expect(!claimed.contains(directory.path))
    }
    #expect(claimed.contains(paths.stateDirectory.path))
    #expect(claimed.contains(paths.cli.path))
    #expect(claimed.contains(paths.helper.path))
    #expect(claimed.contains(paths.plist.path))
    #expect(claimed.contains(paths.mode.path))
  }

  private func withFixture(_ body: (Fixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("magctrl-install-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source-magctrl")
    try Data("binary".utf8).write(to: source)
    try body(Fixture(root: root, source: source))
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? NSNumber).intValue
  }
}

private struct Fixture {
  let source: URL
  let paths: InstallationPaths
  let installer: InstallationFiles

  init(root: URL, source: URL) {
    self.source = source
    paths = InstallationPaths(root: root)
    installer = InstallationFiles(paths: paths)
  }
}
