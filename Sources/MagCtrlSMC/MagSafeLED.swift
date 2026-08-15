import MagCtrlCore

public final class SystemMagSafeLED: MagSafeLEDAccess {
  // ASCII "ACLC" encoded as a big-endian four-character SMC key.
  private static let aclcKey: UInt32 = 0x4143_4c43
  private let client: any RawSMCClient

  public init() {
    self.client = AppleSMCClient()
  }

  init(client: any RawSMCClient) {
    self.client = client
  }

  public func readACLC() throws -> UInt8 {
    try client.readByte(key: Self.aclcKey)
  }

  public func writeACLC(_ value: UInt8) throws {
    try client.writeByte(key: Self.aclcKey, value: value)
  }
}
