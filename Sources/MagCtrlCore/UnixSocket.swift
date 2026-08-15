import Darwin
import Foundation

public final class UnixSocketServer: @unchecked Sendable {
  private let path: String
  private var descriptor: Int32 = -1
  private var createdDevice: dev_t?
  private var createdInode: ino_t?

  public init(path: String) {
    self.path = path
  }

  deinit {
    close()
  }

  public func open() throws {
    guard descriptor == -1 else { return }
    _ = try unixAddress(path: path)

    var existing = stat()
    if lstat(path, &existing) == 0 {
      guard (existing.st_mode & S_IFMT) == S_IFSOCK else {
        throw UnixSocketError.unsafeExistingPath(path)
      }
      if socketAcceptsConnections(path: path) {
        throw UnixSocketError.alreadyRunning(path)
      }
      guard unlink(path) == 0 else {
        throw UnixSocketError.systemCall("unlink", errno)
      }
    } else if errno != ENOENT {
      throw UnixSocketError.systemCall("lstat", errno)
    }

    let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else {
      throw UnixSocketError.systemCall("socket", errno)
    }

    do {
      var address = try unixAddress(path: path)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(
            socketDescriptor,
            $0,
            socklen_t(MemoryLayout<sockaddr_un>.size)
          )
        }
      }
      guard bindResult == 0 else {
        throw UnixSocketError.systemCall("bind", errno)
      }
      guard chmod(path, 0o666) == 0 else {
        throw UnixSocketError.systemCall("chmod", errno)
      }
      guard Darwin.listen(socketDescriptor, 8) == 0 else {
        throw UnixSocketError.systemCall("listen", errno)
      }

      var created = stat()
      guard lstat(path, &created) == 0,
        (created.st_mode & S_IFMT) == S_IFSOCK
      else {
        throw UnixSocketError.unsafeExistingPath(path)
      }
      descriptor = socketDescriptor
      createdDevice = created.st_dev
      createdInode = created.st_ino
    } catch {
      Darwin.close(socketDescriptor)
      var created = stat()
      if lstat(path, &created) == 0,
        (created.st_mode & S_IFMT) == S_IFSOCK
      {
        _ = unlink(path)
      }
      throw error
    }
  }

  @discardableResult
  public func serveNext(
    timeoutMilliseconds: Int32,
    handler: (Data) -> Data
  ) throws -> Bool {
    guard descriptor >= 0 else { throw UnixSocketError.notOpen }
    var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    let pollResult = Darwin.poll(&event, 1, timeoutMilliseconds)
    if pollResult == 0 { return false }
    if pollResult < 0 {
      if errno == EINTR { return false }
      throw UnixSocketError.systemCall("poll", errno)
    }
    guard event.revents & Int16(POLLIN) != 0 else { return false }

    let client = Darwin.accept(descriptor, nil, nil)
    guard client >= 0 else {
      if errno == EINTR { return false }
      throw UnixSocketError.systemCall("accept", errno)
    }
    defer { Darwin.close(client) }

    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    _ = withUnsafePointer(to: &timeout) {
      setsockopt(
        client,
        SOL_SOCKET,
        SO_RCVTIMEO,
        $0,
        socklen_t(MemoryLayout<timeval>.size)
      )
    }

    let request = try readLine(from: client, maximumBytes: ProtocolRequest.maximumBytes)
    let response = handler(request)
    guard response.count <= ProtocolResponse.maximumBytes else {
      throw UnixSocketError.messageTooLarge
    }
    try writeAll(response, to: client)
    return true
  }

  public func close() {
    if descriptor >= 0 {
      Darwin.close(descriptor)
      descriptor = -1
    }
    guard let createdDevice, let createdInode else { return }
    var current = stat()
    if lstat(path, &current) == 0,
      (current.st_mode & S_IFMT) == S_IFSOCK,
      current.st_dev == createdDevice,
      current.st_ino == createdInode
    {
      _ = unlink(path)
    }
    self.createdDevice = nil
    self.createdInode = nil
  }
}

public struct UnixSocketClient: Sendable {
  public let path: String

  public init(path: String) {
    self.path = path
  }

  public func exchange(_ request: Data) throws -> Data {
    guard request.count <= ProtocolRequest.maximumBytes else {
      throw UnixSocketError.messageTooLarge
    }
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw UnixSocketError.systemCall("socket", errno)
    }
    defer { Darwin.close(descriptor) }

    var address = try unixAddress(path: path)
    let connectResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(
          descriptor,
          $0,
          socklen_t(MemoryLayout<sockaddr_un>.size)
        )
      }
    }
    guard connectResult == 0 else {
      throw UnixSocketError.systemCall("connect", errno)
    }

    try writeAll(request, to: descriptor)
    _ = Darwin.shutdown(descriptor, SHUT_WR)
    return try readLine(from: descriptor, maximumBytes: ProtocolResponse.maximumBytes)
  }
}

public enum UnixSocketError: Error, CustomStringConvertible, Sendable {
  case pathTooLong
  case unsafeExistingPath(String)
  case alreadyRunning(String)
  case notOpen
  case messageTooLarge
  case incompleteMessage
  case systemCall(String, Int32)

  public var description: String {
    switch self {
    case .pathTooLong:
      "Unix socket path is too long"
    case .unsafeExistingPath(let path):
      "refusing to replace non-socket path: \(path)"
    case .alreadyRunning(let path):
      "a daemon is already listening at \(path)"
    case .notOpen:
      "Unix socket server is not open"
    case .messageTooLarge:
      "Unix socket message exceeds 64 bytes"
    case .incompleteMessage:
      "Unix socket closed before a complete message arrived"
    case .systemCall(let operation, let code):
      "\(operation) failed: \(String(cString: strerror(code)))"
    }
  }
}

private func unixAddress(path: String) throws -> sockaddr_un {
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
  let bytes = Array(path.utf8) + [0]
  let capacity = MemoryLayout.size(ofValue: address.sun_path)
  guard bytes.count <= capacity else { throw UnixSocketError.pathTooLong }
  withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: bytes)
  }
  return address
}

private func socketAcceptsConnections(path: String) -> Bool {
  guard var address = try? unixAddress(path: path) else { return false }
  let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { return false }
  defer { Darwin.close(descriptor) }
  let result = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(
        descriptor,
        $0,
        socklen_t(MemoryLayout<sockaddr_un>.size)
      )
    }
  }
  return result == 0
}

private func readLine(from descriptor: Int32, maximumBytes: Int) throws -> Data {
  var result = Data()
  var byte: UInt8 = 0
  while result.count <= maximumBytes {
    let count = Darwin.read(descriptor, &byte, 1)
    if count == 1 {
      result.append(byte)
      if byte == 0x0a { return result }
      continue
    }
    if count == 0 { throw UnixSocketError.incompleteMessage }
    if errno == EINTR { continue }
    throw UnixSocketError.systemCall("read", errno)
  }
  throw UnixSocketError.messageTooLarge
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
  try data.withUnsafeBytes { buffer in
    guard let base = buffer.baseAddress else { return }
    var written = 0
    while written < buffer.count {
      let count = Darwin.write(
        descriptor,
        base.advanced(by: written),
        buffer.count - written
      )
      if count > 0 {
        written += count
      } else if count < 0, errno == EINTR {
        continue
      } else {
        throw UnixSocketError.systemCall("write", errno)
      }
    }
  }
}
