public protocol MagSafeLEDAccess: AnyObject {
  func readACLC() throws -> UInt8
  func writeACLC(_ value: UInt8) throws
}

public final class LEDController {
  private let access: any MagSafeLEDAccess
  public private(set) var currentMode: LEDMode

  public init(access: any MagSafeLEDAccess, initialMode: LEDMode = .auto) {
    self.access = access
    self.currentMode = initialMode
  }

  public func apply(_ mode: LEDMode) throws {
    try access.writeACLC(mode.smcByte)
    currentMode = mode
  }

  @discardableResult
  public func reassertIfNeeded() throws -> Bool {
    guard currentMode != .auto else {
      return false
    }
    guard try access.readACLC() != currentMode.smcByte else {
      return false
    }
    try access.writeACLC(currentMode.smcByte)
    return true
  }
}
