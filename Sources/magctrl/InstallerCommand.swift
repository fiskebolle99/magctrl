import Darwin
import Foundation
import MagCtrlCore
import MagCtrlSMC

enum InstallerCommand {
  static func install(paths: InstallationPaths = .live) throws {
    try CLI.requireRoot(for: "install")
    let executable = try currentExecutableURL()

    _ = try? runLaunchctl(["bootout", "system/\(LaunchdConfiguration.label)"])
    try InstallationFiles(paths: paths).install(from: executable)
    try runLaunchctl(["bootstrap", "system", paths.plist.path])
    print("installed magctrl; startup mode is \(ModeStore(url: paths.mode).load().rawValue)")
  }

  static func uninstall(paths: InstallationPaths = .live) throws {
    try CLI.requireRoot(for: "uninstall")

    do {
      _ = try UnixSocketClient(path: paths.socketPath)
        .exchange(ProtocolRequest.setMode(.auto).encode())
    } catch {
      // If the daemon is unavailable, restore the same single ACLC key
      // directly before removing its files.
      try? SystemMagSafeLED().writeACLC(LEDMode.auto.smcByte)
    }
    _ = try? runLaunchctl(["bootout", "system/\(LaunchdConfiguration.label)"])
    try InstallationFiles(paths: paths).removeArtifacts()
    print("uninstalled magctrl and returned the LED to macOS control")
  }

  private static func currentExecutableURL() throws -> URL {
    var capacity = UInt32(PATH_MAX)
    var buffer = [CChar](repeating: 0, count: Int(capacity))
    if _NSGetExecutablePath(&buffer, &capacity) != 0 {
      buffer = [CChar](repeating: 0, count: Int(capacity))
      guard _NSGetExecutablePath(&buffer, &capacity) == 0 else {
        throw InstallerError.executablePath
      }
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
      .resolvingSymlinksInPath()
  }

  @discardableResult
  private static func runLaunchctl(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw InstallerError.launchctl(arguments, process.terminationStatus)
    }
    return process.terminationStatus
  }
}

enum InstallerError: Error, CustomStringConvertible {
  case executablePath
  case launchctl([String], Int32)

  var description: String {
    switch self {
    case .executablePath:
      "could not resolve the magctrl executable path"
    case .launchctl(let arguments, let status):
      "launchctl \(arguments.joined(separator: " ")) failed with status \(status)"
    }
  }
}
