import Testing

@testable import MagCtrlSMC

@Suite("ACLC-only SMC adapter")
struct MagSafeLEDTests {
  @Test func readUsesOnlyTheACLCFourCC() throws {
    let raw = FakeRawSMCClient(readValue: 4)
    let access = SystemMagSafeLED(client: raw)

    #expect(try access.readACLC() == 4)
    #expect(raw.readKeys == [0x4143_4c43])
    #expect(raw.writes.isEmpty)
  }

  @Test func writeUsesOnlyTheACLCFourCCAndPassedByte() throws {
    let raw = FakeRawSMCClient(readValue: 0)
    let access = SystemMagSafeLED(client: raw)

    try access.writeACLC(3)

    #expect(raw.readKeys.isEmpty)
    #expect(raw.writes == [.init(key: 0x4143_4c43, value: 3)])
  }

  @Test func transportErrorsAreForwarded() {
    let raw = FakeRawSMCClient(readValue: 0)
    raw.error = FakeSMCError.failed
    let access = SystemMagSafeLED(client: raw)

    #expect(throws: FakeSMCError.self) {
      try access.writeACLC(1)
    }
  }
}

private enum FakeSMCError: Error {
  case failed
}

private final class FakeRawSMCClient: RawSMCClient {
  struct Write: Equatable {
    var key: UInt32
    var value: UInt8
  }

  var readValue: UInt8
  var readKeys: [UInt32] = []
  var writes: [Write] = []
  var error: Error?

  init(readValue: UInt8) {
    self.readValue = readValue
  }

  func readByte(key: UInt32) throws -> UInt8 {
    if let error { throw error }
    readKeys.append(key)
    return readValue
  }

  func writeByte(key: UInt32, value: UInt8) throws {
    if let error { throw error }
    writes.append(.init(key: key, value: value))
  }
}
