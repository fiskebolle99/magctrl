import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Daemon engine")
struct DaemonEngineTests {
  @Test func startupAppliesPersistedMode() throws {
    let fixture = Fixture(persisted: .amber)

    #expect(try fixture.engine.start() == .amber)
    #expect(fixture.access.writes == [LEDMode.amber.smcByte])
  }

  @Test func modeRequestAppliesThenPersists() throws {
    let fixture = Fixture(persisted: .auto)
    _ = try fixture.engine.start()
    fixture.access.writes.removeAll()

    let response = fixture.engine.handle(ProtocolRequest.setMode(.off).encode())

    #expect(response == .ok)
    #expect(fixture.access.writes == [LEDMode.off.smcByte])
    #expect(fixture.persistence.saved == [.off])
    #expect(fixture.engine.currentMode == .off)
  }

  @Test func persistenceFailureRollsBackLEDAndMode() throws {
    let fixture = Fixture(persisted: .green)
    _ = try fixture.engine.start()
    fixture.access.writes.removeAll()
    fixture.persistence.saveError = FixtureError.failed

    let response = fixture.engine.handle(ProtocolRequest.setMode(.off).encode())

    guard case .error = response else {
      Issue.record("expected an error response")
      return
    }
    #expect(fixture.access.writes == [LEDMode.off.smcByte, LEDMode.green.smcByte])
    #expect(fixture.engine.currentMode == .green)
  }

  @Test func malformedInputNeverReachesLEDOrPersistence() throws {
    let fixture = Fixture(persisted: .auto)
    _ = try fixture.engine.start()
    fixture.access.writes.removeAll()

    let response = fixture.engine.handle(Data("WRITE ACLC ff\n".utf8))

    guard case .error = response else {
      Issue.record("expected an error response")
      return
    }
    #expect(fixture.access.writes.isEmpty)
    #expect(fixture.persistence.saved.isEmpty)
  }

  @Test func statusReturnsSelectedModeWithoutHardwareAccess() throws {
    let fixture = Fixture(persisted: .amber)
    _ = try fixture.engine.start()
    fixture.access.writes.removeAll()
    fixture.access.readCount = 0

    #expect(fixture.engine.handle(ProtocolRequest.status.encode()) == .status(.amber))
    #expect(fixture.access.writes.isEmpty)
    #expect(fixture.access.readCount == 0)
  }

  @Test func timerTickRepairsOnlyForcedModeDrift() throws {
    let fixture = Fixture(persisted: .green)
    _ = try fixture.engine.start()
    fixture.access.writes.removeAll()
    fixture.access.current = LEDMode.auto.smcByte

    #expect(try fixture.engine.reassertIfNeeded() == true)
    #expect(fixture.access.writes == [LEDMode.green.smcByte])
  }
}

private enum FixtureError: Error {
  case failed
}

private final class Fixture {
  let access: EngineFakeAccess
  let persistence: EngineFakePersistence
  let engine: DaemonEngine

  init(persisted: LEDMode) {
    access = EngineFakeAccess()
    persistence = EngineFakePersistence(loaded: persisted)
    engine = DaemonEngine(
      controller: LEDController(access: access),
      persistence: persistence
    )
  }
}

private final class EngineFakeAccess: MagSafeLEDAccess {
  var current = LEDMode.auto.smcByte
  var writes: [UInt8] = []
  var readCount = 0

  func readACLC() throws -> UInt8 {
    readCount += 1
    return current
  }

  func writeACLC(_ value: UInt8) throws {
    writes.append(value)
    current = value
  }
}

private final class EngineFakePersistence: ModePersistence {
  var loaded: LEDMode
  var saved: [LEDMode] = []
  var saveError: Error?

  init(loaded: LEDMode) {
    self.loaded = loaded
  }

  func load() -> LEDMode {
    loaded
  }

  func save(_ mode: LEDMode) throws {
    if let saveError { throw saveError }
    saved.append(mode)
    loaded = mode
  }
}
