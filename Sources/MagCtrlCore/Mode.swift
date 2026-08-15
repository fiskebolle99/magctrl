public enum LEDMode: String, CaseIterable, Codable, Sendable {
  case auto
  case amber
  case green
  case off

  public var smcByte: UInt8 {
    switch self {
    case .auto: 0
    case .off: 1
    case .green: 3
    case .amber: 4
    }
  }
}
