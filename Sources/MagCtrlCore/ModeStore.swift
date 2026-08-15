import Foundation

public protocol ModePersistence {
  func load() -> LEDMode
  func save(_ mode: LEDMode) throws
}

public struct ModeStore: ModePersistence, Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func load() -> LEDMode {
    guard let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .utf8),
      text.last == "\n",
      !text.dropLast().contains("\n"),
      let mode = LEDMode(rawValue: String(text.dropLast()))
    else {
      return .auto
    }
    return mode
  }

  public func save(_ mode: LEDMode) throws {
    try Data("\(mode.rawValue)\n".utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }
}
