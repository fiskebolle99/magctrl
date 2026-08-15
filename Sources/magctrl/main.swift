import Darwin
import Foundation
import MagCtrlCore

do {
  let command = try Command.parse(arguments: Array(CommandLine.arguments.dropFirst()))
  switch command {
  case .mode(let mode):
    try CLI.send(.setMode(mode))
  case .status:
    try CLI.send(.status)
  case .install:
    try InstallerCommand.install()
  case .uninstall:
    try InstallerCommand.uninstall()
  case .daemon:
    try Daemon.run()
  case .help:
    print(Command.helpText)
  }
} catch {
  FileHandle.standardError.write(Data("magctrl: \(error)\n".utf8))
  exit(1)
}
