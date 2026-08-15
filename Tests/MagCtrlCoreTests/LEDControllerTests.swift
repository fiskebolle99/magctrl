import Testing

@testable import MagCtrlCore

@Suite("LED controller")
struct LEDControllerTests {
  @Test(arguments: LEDMode.allCases)
  func applyingModeWritesOnlyItsFixedByte(_ mode: LEDMode) throws {
    let access = FakeMagSafeLEDAccess(current: 99)
    let controller = LEDController(access: access)

    try controller.apply(mode)

    #expect(access.writes == [mode.smcByte])
    #expect(controller.currentMode == mode)
  }

  @Test func matchingForcedModeIsNotRewritten() throws {
    let access = FakeMagSafeLEDAccess(current: LEDMode.green.smcByte)
    let controller = LEDController(access: access, initialMode: .green)

    #expect(try controller.reassertIfNeeded() == false)
    #expect(access.readCount == 1)
    #expect(access.writes.isEmpty)
  }

  @Test func driftedForcedModeIsRepaired() throws {
    let access = FakeMagSafeLEDAccess(current: LEDMode.auto.smcByte)
    let controller = LEDController(access: access, initialMode: .off)

    #expect(try controller.reassertIfNeeded() == true)
    #expect(access.writes == [LEDMode.off.smcByte])
  }

  @Test func autoModeDoesNotPollOrFightMacOS() throws {
    let access = FakeMagSafeLEDAccess(current: LEDMode.amber.smcByte)
    let controller = LEDController(access: access, initialMode: .auto)

    #expect(try controller.reassertIfNeeded() == false)
    #expect(access.readCount == 0)
    #expect(access.writes.isEmpty)
  }

  @Test func failedWriteDoesNotChangeSelectedMode() {
    let access = FakeMagSafeLEDAccess(current: 0)
    access.writeError = FakeError.failed
    let controller = LEDController(access: access, initialMode: .auto)

    #expect(throws: FakeError.self) {
      try controller.apply(.green)
    }
    #expect(controller.currentMode == .auto)
  }
}

private enum FakeError: Error {
  case failed
}

private final class FakeMagSafeLEDAccess: MagSafeLEDAccess {
  var current: UInt8
  var writes: [UInt8] = []
  var readCount = 0
  var writeError: Error?

  init(current: UInt8) {
    self.current = current
  }

  func readACLC() throws -> UInt8 {
    readCount += 1
    return current
  }

  func writeACLC(_ value: UInt8) throws {
    if let writeError { throw writeError }
    writes.append(value)
    current = value
  }
}
