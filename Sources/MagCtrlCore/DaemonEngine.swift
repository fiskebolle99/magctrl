import Foundation

public final class DaemonEngine {
  private let controller: LEDController
  private let persistence: any ModePersistence

  public var currentMode: LEDMode {
    controller.currentMode
  }

  public init(
    controller: LEDController,
    persistence: any ModePersistence
  ) {
    self.controller = controller
    self.persistence = persistence
  }

  @discardableResult
  public func start() throws -> LEDMode {
    let mode = persistence.load()
    try controller.apply(mode)
    return mode
  }

  public func handle(_ data: Data) -> ProtocolResponse {
    do {
      switch try ProtocolRequest.decode(data) {
      case .status:
        return .status(currentMode)
      case .setMode(let mode):
        let previousMode = currentMode
        try controller.apply(mode)
        do {
          try persistence.save(mode)
        } catch {
          try? controller.apply(previousMode)
          throw error
        }
        return .ok
      }
    } catch {
      return .error(String(describing: error))
    }
  }

  @discardableResult
  public func reassertIfNeeded() throws -> Bool {
    try controller.reassertIfNeeded()
  }
}
