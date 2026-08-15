public enum Command: Equatable, Sendable {
  case mode(LEDMode)
  case status
  case install
  case uninstall
  case daemon
  case help

  public static func parse(arguments: [String]) throws -> Command {
    guard arguments.count <= 1 else {
      throw CommandError.invalidArguments
    }
    guard let argument = arguments.first else {
      return .help
    }
    if let mode = LEDMode(rawValue: argument) {
      return .mode(mode)
    }
    switch argument {
    case "status": return .status
    case "install": return .install
    case "uninstall": return .uninstall
    case "--daemon": return .daemon
    case "help", "--help", "-h": return .help
    default: throw CommandError.unknownCommand(argument)
    }
  }

  public static let helpText = """
    magctrl — control only the MagSafe charging light

    Usage:
      magctrl auto       return the LED to macOS control
      magctrl amber      keep the LED amber
      magctrl green      keep the LED green
      magctrl off        keep the LED dark
      magctrl status     print the selected mode

    Setup:
      sudo magctrl install
      sudo magctrl uninstall
    """
}

public enum CommandError: Error, Equatable, CustomStringConvertible, Sendable {
  case invalidArguments
  case unknownCommand(String)

  public var description: String {
    switch self {
    case .invalidArguments:
      "expected exactly one command"
    case .unknownCommand(let command):
      "unknown command: \(command)"
    }
  }
}
