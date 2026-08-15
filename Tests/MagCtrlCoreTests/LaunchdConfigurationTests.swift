import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Installation configuration")
struct LaunchdConfigurationTests {
  @Test func liveLayoutUsesOnlyFixedSystemPaths() {
    let paths = InstallationPaths.live
    #expect(paths.cli.path == "/usr/local/bin/magctrl")
    #expect(paths.helper.path == "/Library/PrivilegedHelperTools/magctrl")
    #expect(paths.plist.path == "/Library/LaunchDaemons/com.signum.magctrl.plist")
    #expect(paths.stateDirectory.path == "/Library/Application Support/magctrl")
    #expect(paths.mode.path == "/Library/Application Support/magctrl/mode")
    #expect(paths.socketPath == "/var/run/magctrl.sock")
  }

  @Test func stagingLayoutPreservesTheAbsoluteTree() {
    let root = URL(fileURLWithPath: "/tmp/magctrl-stage", isDirectory: true)
    let paths = InstallationPaths(root: root)
    #expect(paths.cli.path == "/tmp/magctrl-stage/usr/local/bin/magctrl")
    #expect(paths.helper.path == "/tmp/magctrl-stage/Library/PrivilegedHelperTools/magctrl")
    #expect(paths.plist.path == "/tmp/magctrl-stage/Library/LaunchDaemons/com.signum.magctrl.plist")
    #expect(paths.mode.path == "/tmp/magctrl-stage/Library/Application Support/magctrl/mode")
  }

  @Test func launchdPlistRunsTheFixedHelperAsRootAtBoot() throws {
    let helper = "/Library/PrivilegedHelperTools/magctrl"
    let data = try LaunchdConfiguration.data(helperPath: helper)
    let object = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )

    #expect(object["Label"] as? String == "com.signum.magctrl")
    #expect(object["ProgramArguments"] as? [String] == [helper, "--daemon"])
    #expect(object["UserName"] as? String == "root")
    #expect(object["GroupName"] as? String == "wheel")
    #expect(object["RunAtLoad"] as? Bool == true)
    #expect(object["KeepAlive"] as? Bool == true)
    #expect(object["ProcessType"] as? String == "Background")
    #expect(object["EnvironmentVariables"] == nil)
    #expect(object["Sockets"] == nil)
  }
}
