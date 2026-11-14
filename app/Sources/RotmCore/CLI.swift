import Foundation

public struct CommandOutput: Equatable, Sendable {
  public let stdout: String
  public let stderr: String

  public init(stdout: String, stderr: String) {
    self.stdout = stdout
    self.stderr = stderr
  }
}

public enum CommandError: Error, Equatable {
  case toolMissing(String)
  case readOnly(String)
  case invalid(String)
  case failed(Int32, String)
  case timedOut
  case badJSON(String)
}

public protocol CommandRunner: Sendable {
  func run(_ args: [String]) async throws -> CommandOutput
}

/// Runs `rotm` as a subprocess. Exit 3 is a read-only setting, exit 2 a usage
/// error, anything else non-zero a failure; each carries the command's stderr.
public final class CLI: CommandRunner {
  public let tool: URL
  public let home: URL
  public let timeout: TimeInterval

  public init(tool: URL, home: URL, timeout: TimeInterval = 120) {
    self.tool = tool
    self.home = home
    self.timeout = timeout
  }

  /// A GUI app inherits launchd's PATH, which has neither mise nor uv.
  public static func searchPath(home: URL) -> String {
    let h = home.path
    return "\(h)/.local/bin:\(h)/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  }

  public static func locate(override: String?, home: URL) -> URL? {
    let fm = FileManager.default
    if let override, !override.isEmpty, fm.isExecutableFile(atPath: override) {
      return URL(fileURLWithPath: override)
    }
    let linked = home.appendingPathComponent("dotfiles/bin/rotm")
    return fm.isExecutableFile(atPath: linked.path) ? linked : nil
  }

  public func run(_ args: [String]) async throws -> CommandOutput {
    guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw CommandError.toolMissing(tool.path) }
    let process = Process()
    process.executableURL = tool
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = Self.searchPath(home: home)
    env["TERM"] = "dumb"
    process.environment = env
    process.currentDirectoryURL = home
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = FileHandle.nullDevice

    let exit = Exit()
    process.terminationHandler = { p in exit.finish(status: p.terminationStatus) }
    do {
      try process.run()
    } catch {
      throw CommandError.toolMissing(tool.path)
    }

    // Drain both pipes while the command runs, or a chatty command fills a
    // pipe buffer and never ends. The reads run on GCD through
    // readabilityHandler: a blocking read on a cooperative thread can starve
    // the pool and the watchdog below never runs.
    let outData = PipeDrain(stdout.fileHandleForReading)
    let errData = PipeDrain(stderr.fileHandleForReading)
    // Process makes the child a group leader and terminate() signals that
    // group, so the kills below reach the command's own children too.
    let group = -process.processIdentifier
    let limit = timeout
    let watchdog = Task {
      try await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
      exit.markTimedOut()
      process.terminate()
      try await Task.sleep(nanoseconds: 2_000_000_000)
      kill(group, SIGKILL)
    }
    let status = await exit.wait()
    watchdog.cancel()
    if exit.timedOut {
      // bash can die to the SIGTERM while a child that ignores it lives on.
      kill(group, SIGKILL)
      outData.stop()
      errData.stop()
      throw CommandError.timedOut
    }
    // A backgrounded grandchild can hold the write ends open after the child
    // exited; after 2 s take what was read rather than wait for an EOF.
    let drainLimit = Task {
      try await Task.sleep(nanoseconds: 2_000_000_000)
      outData.stop()
      errData.stop()
    }
    let out = await outData.value()
    let err = await errData.value()
    drainLimit.cancel()
    let message = Self.plainText(err).trimmingCharacters(in: .whitespacesAndNewlines)
    switch status {
    case 0:
      let text = Self.plainText(out)
      return CommandOutput(stdout: String(text.reversed().drop { $0.isNewline }.reversed()), stderr: message)
    case 2: throw CommandError.invalid(message)
    case 3: throw CommandError.readOnly(message)
    default: throw CommandError.failed(status, message)
    }
  }

  private static func plainText(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]|\u{1B}\\([A-Z]", with: "", options: .regularExpression)
  }
}

/// Bridges `terminationHandler` to async, once, from whichever thread fires it.
private final class Exit: @unchecked Sendable {
  private let lock = NSLock()
  private var status: Int32?
  private var waiter: CheckedContinuation<Int32, Never>?
  private var didTimeOut = false
  var timedOut: Bool { lock.withLock { didTimeOut } }

  func finish(status: Int32) {
    lock.lock()
    self.status = status
    let w = waiter
    waiter = nil
    lock.unlock()
    w?.resume(returning: status)
  }

  func markTimedOut() {
    lock.withLock { didTimeOut = true }
  }

  func wait() async -> Int32 {
    await withCheckedContinuation { c in
      lock.lock()
      if let status {
        lock.unlock()
        c.resume(returning: status)
      } else {
        waiter = c
        lock.unlock()
      }
    }
  }
}

/// Collects a pipe to EOF on GCD and hands the bytes to one async waiter.
private final class PipeDrain: @unchecked Sendable {
  private let lock = NSLock()
  private let handle: FileHandle
  private var data = Data()
  private var done = false
  private var waiter: CheckedContinuation<Data, Never>?

  init(_ handle: FileHandle) {
    self.handle = handle
    handle.readabilityHandler = { [weak self] h in
      let chunk = h.availableData
      guard let self else { return }
      if chunk.isEmpty {
        self.finish()
      } else {
        self.lock.withLock { self.data.append(chunk) }
      }
    }
  }

  func value() async -> Data {
    await withCheckedContinuation { c in
      lock.lock()
      if done {
        lock.unlock()
        c.resume(returning: data)
      } else {
        waiter = c
        lock.unlock()
      }
    }
  }

  /// Stop reading and release the handle; nothing waits for the bytes.
  func stop() {
    finish()
  }

  private func finish() {
    lock.lock()
    let first = !done
    done = true
    let w = waiter
    waiter = nil
    let bytes = data
    lock.unlock()
    if first {
      handle.readabilityHandler = nil
      try? handle.close()
    }
    w?.resume(returning: bytes)
  }
}
