import Darwin
import Dispatch
import Foundation
import MagCtrlCore
import MagCtrlSMC
import os

enum Daemon {
  private static let log = Logger(subsystem: "com.signum.magctrl", category: "daemon")

  static func run(paths: InstallationPaths = .live) throws {
    try CLI.requireRoot(for: "--daemon")
    let controller = LEDController(access: SystemMagSafeLED())
    let engine = DaemonEngine(
      controller: controller,
      persistence: ModeStore(url: paths.mode)
    )
    let selected = try engine.start()
    log.info("started in \(selected.rawValue, privacy: .public) mode")

    let server = UnixSocketServer(path: paths.socketPath)
    try server.open()
    defer { server.close() }

    let stop = StopFlag()
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let terminateSource = DispatchSource.makeSignalSource(
      signal: SIGTERM,
      queue: .global(qos: .utility)
    )
    let interruptSource = DispatchSource.makeSignalSource(
      signal: SIGINT,
      queue: .global(qos: .utility)
    )
    terminateSource.setEventHandler { stop.request() }
    interruptSource.setEventHandler { stop.request() }
    terminateSource.resume()
    interruptSource.resume()

    while !stop.isRequested {
      do {
        _ = try server.serveNext(timeoutMilliseconds: 1_000) { request in
          engine.handle(request).encode()
        }
      } catch {
        log.error("socket request failed: \(String(describing: error), privacy: .public)")
      }
      do {
        if try engine.reassertIfNeeded() {
          log.info("reasserted \(engine.currentMode.rawValue, privacy: .public) mode")
        }
      } catch {
        log.error("ACLC check failed: \(String(describing: error), privacy: .public)")
      }
    }

    do {
      try controller.apply(.auto)
      log.info("returned ACLC to macOS control")
    } catch {
      log.error("failed to return ACLC to macOS: \(String(describing: error), privacy: .public)")
    }

    withExtendedLifetime((terminateSource, interruptSource)) {}
  }
}

private final class StopFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var requested = false

  var isRequested: Bool {
    lock.withLock { requested }
  }

  func request() {
    lock.withLock { requested = true }
  }
}
