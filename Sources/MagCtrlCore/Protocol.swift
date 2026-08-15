import Foundation

public enum ProtocolRequest: Equatable, Sendable {
  case setMode(LEDMode)
  case status

  public static let maximumBytes = 64

  public static func decode(_ data: Data) throws -> ProtocolRequest {
    let message = try decodeSingleLine(data, maximumBytes: maximumBytes)
    switch message {
    case "AUTO": return .setMode(.auto)
    case "AMBER": return .setMode(.amber)
    case "GREEN": return .setMode(.green)
    case "OFF": return .setMode(.off)
    case "STATUS": return .status
    default: throw ProtocolError.unknownMessage
    }
  }

  public func encode() -> Data {
    let message: String
    switch self {
    case .setMode(.auto): message = "AUTO"
    case .setMode(.amber): message = "AMBER"
    case .setMode(.green): message = "GREEN"
    case .setMode(.off): message = "OFF"
    case .status: message = "STATUS"
    }
    return Data("\(message)\n".utf8)
  }
}

public enum ProtocolResponse: Equatable, Sendable {
  case ok
  case status(LEDMode)
  case error(String)

  public static let maximumBytes = 64

  public func encode() -> Data {
    switch self {
    case .ok:
      return Data("OK\n".utf8)
    case .status(let mode):
      return Data("STATUS \(mode.rawValue)\n".utf8)
    case .error(let message):
      let safe = message.utf8.map { byte -> UInt8 in
        (32...126).contains(byte) ? byte : 32
      }
      let maximumMessageBytes = Self.maximumBytes - Data("ERROR \n".utf8).count
      var data = Data("ERROR ".utf8)
      data.append(contentsOf: safe.prefix(maximumMessageBytes))
      data.append(0x0a)
      return data
    }
  }

  public static func decode(_ data: Data) throws -> ProtocolResponse {
    let message = try decodeSingleLine(data, maximumBytes: maximumBytes)
    if message == "OK" {
      return .ok
    }
    if message.hasPrefix("STATUS "),
      let mode = LEDMode(rawValue: String(message.dropFirst("STATUS ".count)))
    {
      return .status(mode)
    }
    if message.hasPrefix("ERROR ") {
      return .error(String(message.dropFirst("ERROR ".count)))
    }
    throw ProtocolError.unknownMessage
  }
}

public enum ProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
  case tooLarge
  case malformed
  case unknownMessage

  public var description: String {
    switch self {
    case .tooLarge: "protocol message exceeds 64 bytes"
    case .malformed: "protocol message must be one newline-terminated UTF-8 line"
    case .unknownMessage: "protocol message is not allowed"
    }
  }
}

private func decodeSingleLine(_ data: Data, maximumBytes: Int) throws -> String {
  guard data.count <= maximumBytes else {
    throw ProtocolError.tooLarge
  }
  guard data.count >= 2,
    data.last == 0x0a,
    !data.dropLast().contains(0x0a),
    !data.dropLast().contains(0x0d),
    let string = String(data: data.dropLast(), encoding: .utf8),
    !string.isEmpty
  else {
    throw ProtocolError.malformed
  }
  return string
}
