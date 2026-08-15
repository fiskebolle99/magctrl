import Foundation
import MagCtrlCore

enum CLIError: Error, CustomStringConvertible {
  case daemon(String)
  case unexpectedResponse
  case rootRequired(String)

  var description: String {
    switch self {
    case .daemon(let message): message
    case .unexpectedResponse: "the daemon returned an unexpected response"
    case .rootRequired(let command): "\(command) requires root; run sudo magctrl \(command)"
    }
  }
}

enum CLI {
  static func send(_ request: ProtocolRequest, paths: InstallationPaths = .live) throws {
    let responseData: Data
    do {
      responseData = try UnixSocketClient(path: paths.socketPath)
        .exchange(request.encode())
    } catch {
      throw CLIError.daemon(
        "cannot reach the magctrl daemon: \(error). Run sudo magctrl install first"
      )
    }

    switch try ProtocolResponse.decode(responseData) {
    case .ok:
      if case .setMode(let mode) = request {
        print(mode.rawValue)
      } else {
        print("ok")
      }
    case .status(let mode):
      print(mode.rawValue)
    case .error(let message):
      throw CLIError.daemon("daemon error: \(message)")
    }
  }

  static func requireRoot(for command: String) throws {
    guard geteuid() == 0 else { throw CLIError.rootRequired(command) }
  }
}
