import Foundation
import IOKit

// The AppleSMC transport is adapted from MagHue by Kamen Levi and Peter Levi:
// https://github.com/kamenlevi/MagHue (GPL-3.0-or-later).
// magctrl intentionally retains only the operations needed for one-byte ACLC
// access and does not expose a general SMC interface outside this module.

protocol RawSMCClient: AnyObject {
  func readByte(key: UInt32) throws -> UInt8
  func writeByte(key: UInt32, value: UInt8) throws
}

final class AppleSMCClient: RawSMCClient {
  enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case smcResult(UInt8)
    case unexpectedLayout(Int)
    case unexpectedDataSize(UInt32)

    var description: String {
      switch self {
      case .serviceNotFound:
        "AppleSMC service not found"
      case .openFailed(let result):
        "IOServiceOpen failed (\(result))"
      case .callFailed(let result):
        "IOConnectCallStructMethod failed (\(result))"
      case .smcResult(let result):
        result == 0x84
          ? "ACLC is not available on this Mac"
          : "SMC returned error \(result)"
      case .unexpectedLayout(let size):
        "unexpected AppleSMC parameter size \(size)"
      case .unexpectedDataSize(let size):
        "ACLC is \(size) bytes; expected exactly 1"
      }
    }
  }

  private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
  }

  private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
  }

  private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  private struct SMCParamStruct {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0
    )
  }

  private static let handleEvent: UInt32 = 2
  private static let readKey: UInt8 = 5
  private static let writeKey: UInt8 = 6
  private static let getKeyInfo: UInt8 = 9

  func readByte(key: UInt32) throws -> UInt8 {
    try withConnection { connection in
      let size = try dataSize(for: key, connection: connection)
      guard size == 1 else { throw SMCError.unexpectedDataSize(size) }

      var request = SMCParamStruct()
      request.key = key
      request.data8 = Self.readKey
      request.keyInfo.dataSize = size
      return try call(connection, request).bytes.0
    }
  }

  func writeByte(key: UInt32, value: UInt8) throws {
    try withConnection { connection in
      let size = try dataSize(for: key, connection: connection)
      guard size == 1 else { throw SMCError.unexpectedDataSize(size) }

      var request = SMCParamStruct()
      request.key = key
      request.data8 = Self.writeKey
      request.keyInfo.dataSize = size
      request.bytes.0 = value
      _ = try call(connection, request)
    }
  }

  private func dataSize(for key: UInt32, connection: io_connect_t) throws -> UInt32 {
    var request = SMCParamStruct()
    request.key = key
    request.data8 = Self.getKeyInfo
    return try call(connection, request).keyInfo.dataSize
  }

  private func withConnection<T>(
    _ body: (io_connect_t) throws -> T
  ) throws -> T {
    let layoutSize = MemoryLayout<SMCParamStruct>.stride
    guard layoutSize == 80 else { throw SMCError.unexpectedLayout(layoutSize) }

    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("AppleSMC")
    )
    guard service != 0 else { throw SMCError.serviceNotFound }
    defer { IOObjectRelease(service) }

    var connection: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    defer { IOServiceClose(connection) }
    return try body(connection)
  }

  private func call(
    _ connection: io_connect_t,
    _ request: SMCParamStruct
  ) throws -> SMCParamStruct {
    var request = request
    var response = SMCParamStruct()
    var responseSize = MemoryLayout<SMCParamStruct>.stride
    let result = IOConnectCallStructMethod(
      connection,
      Self.handleEvent,
      &request,
      MemoryLayout<SMCParamStruct>.stride,
      &response,
      &responseSize
    )
    guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
    guard responseSize == MemoryLayout<SMCParamStruct>.stride else {
      throw SMCError.unexpectedLayout(responseSize)
    }
    guard response.result == 0 else { throw SMCError.smcResult(response.result) }
    return response
  }
}
