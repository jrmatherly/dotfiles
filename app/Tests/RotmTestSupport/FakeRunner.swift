import Foundation
import RotmCore

public final class FakeRunner: CommandRunner, @unchecked Sendable {
  private let lock = NSLock()
  private var stubs: [String: Result<CommandOutput, CommandError>] = [:]
  private var gates: [String: Gate] = [:]
  private var recorded: [[String]] = []

  public init() {}

  public var calls: [[String]] { lock.withLock { recorded } }

  public func stub(_ args: [String], _ result: Result<CommandOutput, CommandError>) {
    lock.withLock { stubs[Self.key(args)] = result }
  }

  public func hold(_ args: [String]) -> () -> Void {
    let gate = Gate()
    lock.withLock { gates[Self.key(args)] = gate }
    return gate.open
  }

  public func run(_ args: [String]) async throws -> CommandOutput {
    let key = Self.key(args)
    let gate = lock.withLock {
      recorded.append(args)
      return gates[key]
    }
    await gate?.wait()
    let result = lock.withLock { stubs[key] } ?? .failure(.failed(127, "no stub: \(key)"))
    return try result.get()
  }

  private static func key(_ args: [String]) -> String { args.joined(separator: " ") }
}

private final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open() {
    let pending = lock.withLock {
      isOpen = true
      defer { waiters = [] }
      return waiters
    }
    pending.forEach { $0.resume() }
  }

  func wait() async {
    await withCheckedContinuation { c in
      let resumeNow = lock.withLock {
        if isOpen { return true }
        waiters.append(c)
        return false
      }
      if resumeNow { c.resume() }
    }
  }
}
