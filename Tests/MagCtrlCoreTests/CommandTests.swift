import Testing

@testable import MagCtrlCore

@Suite("Command parsing")
struct CommandTests {
  @Test func publicModesMapToFixedACLCBytes() {
    #expect(LEDMode.auto.smcByte == 0)
    #expect(LEDMode.off.smcByte == 1)
    #expect(LEDMode.green.smcByte == 3)
    #expect(LEDMode.amber.smcByte == 4)
  }

  @Test(arguments: ["auto", "amber", "green", "off"])
  func parsesPublicModes(_ name: String) throws {
    let expected = LEDMode(rawValue: name)!
    #expect(try Command.parse(arguments: [name]) == .mode(expected))
  }

  @Test func parsesManagementCommands() throws {
    #expect(try Command.parse(arguments: ["status"]) == .status)
    #expect(try Command.parse(arguments: ["install"]) == .install)
    #expect(try Command.parse(arguments: ["uninstall"]) == .uninstall)
    #expect(try Command.parse(arguments: ["--daemon"]) == .daemon)
    #expect(try Command.parse(arguments: ["help"]) == .help)
    #expect(try Command.parse(arguments: ["--help"]) == .help)
    #expect(try Command.parse(arguments: []) == .help)
  }

  @Test func rejectsExtraArguments() {
    #expect(throws: CommandError.self) {
      try Command.parse(arguments: ["green", "unexpected"])
    }
  }

  @Test func rejectsUnknownAndDifferentlyCasedCommands() {
    #expect(throws: CommandError.self) {
      try Command.parse(arguments: ["blue"])
    }
    #expect(throws: CommandError.self) {
      try Command.parse(arguments: ["GREEN"])
    }
  }

  @Test func helpListsTheFourModesAndPrivilegeBoundary() {
    #expect(Command.helpText.contains("magctrl auto"))
    #expect(Command.helpText.contains("magctrl amber"))
    #expect(Command.helpText.contains("magctrl green"))
    #expect(Command.helpText.contains("magctrl off"))
    #expect(Command.helpText.contains("sudo magctrl install"))
    #expect(Command.helpText.contains("sudo magctrl uninstall"))
  }
}
