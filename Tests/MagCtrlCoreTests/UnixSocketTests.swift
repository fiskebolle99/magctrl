import Foundation
import Testing

@testable import MagCtrlCore

@Suite("Unix socket transport", .serialized)
struct UnixSocketTests {
  @Test func clientAndServerExchangeOneBoundedMessage() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("magctrl.sock").path
    let server = UnixSocketServer(path: path)
    try server.open()

    let response = try await withCheckedThrowingContinuation { continuation in
      Thread.detachNewThread {
        do {
          _ = try server.serveNext(timeoutMilliseconds: 2_000) { request in
            #expect(request == Data("GREEN\n".utf8))
            return Data("OK\n".utf8)
          }
        } catch {
          Issue.record(error)
        }
      }
      do {
        let data = try UnixSocketClient(path: path)
          .exchange(Data("GREEN\n".utf8))
        continuation.resume(returning: data)
      } catch {
        continuation.resume(throwing: error)
      }
    }

    #expect(response == Data("OK\n".utf8))
    server.close()
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test func serverRefusesToReplaceARegularFile() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("magctrl.sock")
    try Data("do not replace".utf8).write(to: url)

    let server = UnixSocketServer(path: url.path)
    #expect(throws: UnixSocketError.self) {
      try server.open()
    }
    #expect(try String(contentsOf: url, encoding: .utf8) == "do not replace")
  }

  @Test func transportRejectsOverlongPath() {
    let server = UnixSocketServer(path: "/tmp/" + String(repeating: "x", count: 200))
    #expect(throws: UnixSocketError.self) {
      try server.open()
    }
  }

  private func temporaryDirectory() throws -> URL {
    let suffix = UUID().uuidString.prefix(8)
    let url = URL(fileURLWithPath: "/tmp/magctrl-\(suffix)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
