import Darwin
import Foundation

public struct InstallationPaths: Sendable {
  public static let live = InstallationPaths(
    root: URL(fileURLWithPath: "/", isDirectory: true)
  )

  public let cli: URL
  public let helper: URL
  public let plist: URL
  public let stateDirectory: URL
  public let mode: URL
  public let socketPath: String

  public init(root: URL) {
    func rooted(_ absolutePath: String, isDirectory: Bool = false) -> URL {
      if root.path == "/" {
        return URL(fileURLWithPath: absolutePath, isDirectory: isDirectory)
      }
      return URL(
        fileURLWithPath: root.path + absolutePath,
        isDirectory: isDirectory
      )
    }

    cli = rooted("/usr/local/bin/magctrl")
    helper = rooted("/Library/PrivilegedHelperTools/magctrl")
    plist = rooted("/Library/LaunchDaemons/com.signum.magctrl.plist")
    stateDirectory = rooted("/Library/Application Support/magctrl", isDirectory: true)
    mode = rooted("/Library/Application Support/magctrl/mode")
    socketPath = rooted("/var/run/magctrl.sock").path
  }
}

public enum LaunchdConfiguration {
  public static let label = "com.signum.magctrl"

  public static func data(helperPath: String) throws -> Data {
    let configuration: [String: Any] = [
      "Label": label,
      "ProgramArguments": [helperPath, "--daemon"],
      "UserName": "root",
      "GroupName": "wheel",
      "RunAtLoad": true,
      "KeepAlive": true,
      "ProcessType": "Background",
      "ThrottleInterval": 2,
    ]
    return try PropertyListSerialization.data(
      fromPropertyList: configuration,
      format: .xml,
      options: 0
    )
  }
}

public struct InstallationFiles {
  public let paths: InstallationPaths
  private let assignOwnership: (URL) throws -> Void

  public init(paths: InstallationPaths) {
    self.paths = paths
    self.assignOwnership = { url in
      guard geteuid() == 0 else { return }
      guard chown(url.path, 0, 0) == 0 else {
        throw InstallationError.systemCall("chown", errno)
      }
    }
  }

  init(paths: InstallationPaths, assignOwnership: @escaping (URL) throws -> Void) {
    self.paths = paths
    self.assignOwnership = assignOwnership
  }

  public func install(from executable: URL) throws {
    try requireRegularFile(executable)
    try ensureDirectory(paths.cli.deletingLastPathComponent(), mode: 0o755)
    try ensureDirectory(paths.helper.deletingLastPathComponent(), mode: 0o755)
    try ensureDirectory(paths.plist.deletingLastPathComponent(), mode: 0o755)
    try ensureDirectory(paths.stateDirectory, mode: 0o755, enforceMode: true)

    try copyAtomically(from: executable, to: paths.cli, mode: 0o755)
    try copyAtomically(from: executable, to: paths.helper, mode: 0o755)
    let plistData = try LaunchdConfiguration.data(helperPath: paths.helper.path)
    try writeAtomically(plistData, to: paths.plist, mode: 0o644)

    if !pathExists(paths.mode) {
      try ModeStore(url: paths.mode).save(.auto)
      try assignOwnership(paths.mode)
    } else {
      try requireRegularFile(paths.mode)
    }
  }

  public func removeArtifacts() throws {
    for file in [paths.plist, paths.helper, paths.cli, paths.mode] {
      try removeRegularFileIfPresent(file)
    }
    try removeSocketIfPresent(paths.socketPath)
    _ = rmdir(paths.stateDirectory.path)
  }

  private func copyAtomically(from source: URL, to destination: URL, mode: Int) throws {
    if source.standardizedFileURL.path == destination.standardizedFileURL.path {
      guard chmod(destination.path, mode_t(mode)) == 0 else {
        throw InstallationError.systemCall("chmod", errno)
      }
      try assignOwnership(destination)
      return
    }
    try requireReplaceableDestination(destination)
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".magctrl-install-\(getpid())-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    do {
      try FileManager.default.copyItem(at: source, to: temporary)
      guard chmod(temporary.path, mode_t(mode)) == 0 else {
        throw InstallationError.systemCall("chmod", errno)
      }
      guard Darwin.rename(temporary.path, destination.path) == 0 else {
        throw InstallationError.systemCall("rename", errno)
      }
      try assignOwnership(destination)
    } catch {
      throw error
    }
  }

  private func writeAtomically(_ data: Data, to destination: URL, mode: Int) throws {
    try requireReplaceableDestination(destination)
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".magctrl-install-\(getpid())-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try data.write(to: temporary, options: [.atomic])
    guard chmod(temporary.path, mode_t(mode)) == 0 else {
      throw InstallationError.systemCall("chmod", errno)
    }
    guard Darwin.rename(temporary.path, destination.path) == 0 else {
      throw InstallationError.systemCall("rename", errno)
    }
    try assignOwnership(destination)
  }

  private func ensureDirectory(
    _ url: URL,
    mode: Int,
    enforceMode: Bool = false
  ) throws {
    var info = stat()
    if lstat(url.path, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFDIR else {
        throw InstallationError.unsafePath(url.path)
      }
      if enforceMode {
        guard chmod(url.path, mode_t(mode)) == 0 else {
          throw InstallationError.systemCall("chmod", errno)
        }
        try assignOwnership(url)
      }
      return
    }
    guard errno == ENOENT else {
      throw InstallationError.systemCall("lstat", errno)
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    guard chmod(url.path, mode_t(mode)) == 0 else {
      throw InstallationError.systemCall("chmod", errno)
    }
    try assignOwnership(url)
  }

  private func requireRegularFile(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      throw InstallationError.systemCall("lstat", errno)
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
      throw InstallationError.unsafePath(url.path)
    }
  }

  private func requireReplaceableDestination(_ url: URL) throws {
    var info = stat()
    if lstat(url.path, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFREG else {
        throw InstallationError.unsafePath(url.path)
      }
    } else if errno != ENOENT {
      throw InstallationError.systemCall("lstat", errno)
    }
  }

  private func removeRegularFileIfPresent(_ url: URL) throws {
    var info = stat()
    if lstat(url.path, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFREG else {
        throw InstallationError.unsafePath(url.path)
      }
      guard unlink(url.path) == 0 else {
        throw InstallationError.systemCall("unlink", errno)
      }
    } else if errno != ENOENT {
      throw InstallationError.systemCall("lstat", errno)
    }
  }

  private func removeSocketIfPresent(_ path: String) throws {
    var info = stat()
    if lstat(path, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFSOCK else {
        throw InstallationError.unsafePath(path)
      }
      guard unlink(path) == 0 else {
        throw InstallationError.systemCall("unlink", errno)
      }
    } else if errno != ENOENT {
      throw InstallationError.systemCall("lstat", errno)
    }
  }

  private func pathExists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }
}

public enum InstallationError: Error, CustomStringConvertible, Sendable {
  case unsafePath(String)
  case systemCall(String, Int32)

  public var description: String {
    switch self {
    case .unsafePath(let path):
      "refusing unsafe installation path: \(path)"
    case .systemCall(let operation, let code):
      "\(operation) failed: \(String(cString: strerror(code)))"
    }
  }
}
