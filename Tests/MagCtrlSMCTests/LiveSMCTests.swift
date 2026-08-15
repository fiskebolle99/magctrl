import Foundation
import Testing

@testable import MagCtrlSMC

@Test(
  "Live ACLC read",
  .enabled(
    if: ProcessInfo.processInfo.environment["MAGCTRL_LIVE_SMC_TEST"] == "1",
    "set MAGCTRL_LIVE_SMC_TEST=1 to run the read-only hardware probe"
  )
)
func liveACLCReadDoesNotThrow() throws {
  _ = try SystemMagSafeLED().readACLC()
}
