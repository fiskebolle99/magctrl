import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Daemon protocol")
struct ProtocolTests {
  @Test(arguments: [
    ("AUTO\n", LEDMode.auto),
    ("AMBER\n", LEDMode.amber),
    ("GREEN\n", LEDMode.green),
    ("OFF\n", LEDMode.off),
  ])
  func decodesExactModeRequests(_ request: String, _ mode: LEDMode) throws {
    #expect(try ProtocolRequest.decode(Data(request.utf8)) == .setMode(mode))
  }

  @Test func decodesStatusRequest() throws {
    #expect(try ProtocolRequest.decode(Data("STATUS\n".utf8)) == .status)
  }

  @Test(arguments: [
    "green\n",
    "WRITE ACLC ff\n",
    "GREEN",
    "GREEN\nOFF\n",
    " GREEN\n",
    "GREEN \n",
    "\n",
  ])
  func rejectsAnythingOutsideTheAllowlist(_ request: String) {
    #expect(throws: ProtocolError.self) {
      try ProtocolRequest.decode(Data(request.utf8))
    }
  }

  @Test func rejectsOversizedRequest() {
    #expect(throws: ProtocolError.self) {
      try ProtocolRequest.decode(Data(repeating: 65, count: 65))
    }
  }

  @Test func rejectsInvalidUTF8() {
    #expect(throws: ProtocolError.self) {
      try ProtocolRequest.decode(Data([0xff, 0x0a]))
    }
  }

  @Test func encodesRequestsUsingTheFixedAllowlist() {
    #expect(ProtocolRequest.setMode(.auto).encode() == Data("AUTO\n".utf8))
    #expect(ProtocolRequest.setMode(.amber).encode() == Data("AMBER\n".utf8))
    #expect(ProtocolRequest.setMode(.green).encode() == Data("GREEN\n".utf8))
    #expect(ProtocolRequest.setMode(.off).encode() == Data("OFF\n".utf8))
    #expect(ProtocolRequest.status.encode() == Data("STATUS\n".utf8))
  }

  @Test func responseRoundTrips() throws {
    let responses: [ProtocolResponse] = [
      .ok,
      .status(.off),
      .error("SMC write failed"),
    ]
    for response in responses {
      #expect(try ProtocolResponse.decode(response.encode()) == response)
    }
  }

  @Test func errorResponseRemovesProtocolDelimiters() throws {
    let encoded = ProtocolResponse.error("bad\nmessage\rhere").encode()
    #expect(encoded == Data("ERROR bad message here\n".utf8))
    #expect(try ProtocolResponse.decode(encoded) == .error("bad message here"))
  }
}
