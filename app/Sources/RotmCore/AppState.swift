import Foundation
import Observation

@MainActor @Observable public final class AppState {
  public enum Tool: Equatable { case checking, ready, missing(String), broken(String) }

  public private(set) var tool: Tool = .checking
  public private(set) var runner: CommandRunner?
  public private(set) var status: Status?
  public private(set) var updateCheck: UpdateCheck?
  public private(set) var busy: String?
  public var sessionRunning = false
  public var blocked: Bool { busy != nil || sessionRunning }
  public private(set) var lastOutput: String?
  public private(set) var lastError: String?
  public private(set) var appUpdate: String?

  public var needsAttention: Bool {
    guard let status else { return false }
    return status.sync.conflicts != nil || !status.sync.waiting.isEmpty || status.profile.missing != nil
      || (updateCheck?.behind ?? 0) > 0 || appUpdate != nil
  }

  private let makeRunner: (URL) -> CommandRunner
  private let locate: () -> URL?
  private let now: () -> Date
  private var checkedAt: Date?

  public init(makeRunner: @escaping (URL) -> CommandRunner, locate: @escaping () -> URL?, now: @escaping () -> Date = Date.init) {
    self.makeRunner = makeRunner
    self.locate = locate
    self.now = now
  }

  public func refresh() async {
    if runner == nil {
      guard let tool = locate() else {
        self.tool = .missing(Self.notFound)
        return
      }
      runner = makeRunner(tool)
    }
    guard let runner else { return }
    do {
      status = try Decode.status(try await runner.run(["settings", "status", "--json"]).stdout)
      tool = .ready
    } catch {
      status = nil
      if let message = Self.message(error) {
        tool = .broken(message)
      } else {
        self.runner = nil
        tool = .missing(Self.notFound)
      }
      return
    }
    if let checkedAt, now().timeIntervalSince(checkedAt) < 3600 { return }
    checkedAt = now()
    // A failed check keeps the last answer: no network is not worth a message.
    if let out = try? await runner.run(["update", "--check", "--json"]), let check = try? Decode.updateCheck(out.stdout) {
      updateCheck = check
    }
  }

  public func useProfile(_ name: String) async {
    await perform("Switching to \(name)…", ["settings", "profile", "use", name])
  }

  public func newProfile(_ name: String) async {
    await perform("Creating \(name)…", ["settings", "profile", "new", name])
  }

  public func syncNow() async {
    await perform("Syncing…", ["settings", "sync", "now"])
  }

  public func dismissOutput() {
    lastOutput = nil
    lastError = nil
  }

  private func perform(_ label: String, _ args: [String]) async {
    guard !blocked, let runner else { return }
    busy = label
    do {
      let out = try await runner.run(args)
      let text = [out.stdout, out.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
      lastOutput = text.isEmpty ? nil : text
      lastError = nil
    } catch {
      lastOutput = nil
      lastError = Self.message(error) ?? Self.notFound
    }
    await refresh()
    busy = nil
  }

  private static let notFound = "rotm was not found at ~/dotfiles/bin/rotm."

  /// nil when the tool itself is gone.
  private static func message(_ error: Error) -> String? {
    switch error as? CommandError {
    case .toolMissing: return nil
    case .readOnly(let s), .invalid(let s): return s
    case .failed(let code, let s): return s.isEmpty ? "rotm exited \(code)" : s
    case .timedOut: return "rotm did not finish in time."
    case .badJSON(let s): return "rotm printed something that is not JSON: \(s)"
    case nil: return error.localizedDescription
    }
  }
}
