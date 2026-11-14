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
  /// True while mise replaces the app; Quit is refused, because this is the one command that outlives a console.
  public private(set) var upgrading = false
  public var blocked: Bool { busy != nil || sessionRunning || upgrading }
  public private(set) var lastOutput: String?
  public private(set) var lastError: String?
  public private(set) var appUpdate: String?

  public enum QuitDecision: Equatable {
    case allow, refuse
    case ask(message: String, detail: String)
  }

  public var needsAttention: Bool {
    guard let status else { return false }
    return status.sync.conflicts != nil || !status.sync.waiting.isEmpty || status.profile.missing != nil
      || (updateCheck?.behind ?? 0) > 0 || appUpdate != nil
  }

  private let makeRunner: (URL) -> CommandRunner
  private let locate: () -> URL?
  private let now: () -> Date
  private var checkedAt: Date?
  private var appCheckedAt: Date?

  public init(makeRunner: @escaping (URL) -> CommandRunner, locate: @escaping () -> URL?, now: @escaping () -> Date = Date.init) {
    self.makeRunner = makeRunner
    self.locate = locate
    self.now = now
  }

  /// `recheckUpdates` runs `update --check` now instead of at most hourly, as after the console's update.
  /// Runs nothing while a command runs: its own end refreshes.
  public func refresh(recheckUpdates: Bool = false) async {
    guard !blocked else { return }
    await read(recheckUpdates: recheckUpdates)
  }

  private func read(recheckUpdates: Bool = false) async {
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
    if !recheckUpdates, let checkedAt, now().timeIntervalSince(checkedAt) < 3600 { return }
    checkedAt = now()
    // A failed check keeps the last answer: no network is not worth a message.
    if let out = try? await runner.run(["update", "--check", "--json"]), let check = try? Decode.updateCheck(out.stdout) {
      updateCheck = check
    }
  }

  /// Reads the cask in the tap, at most once a day. A failed check is silent.
  public func checkAppUpdate(fetch: (URL) async throws -> String, current: String) async {
    if let appCheckedAt, now().timeIntervalSince(appCheckedAt) < 86400 { return }
    guard let text = try? await fetch(AppUpdate.caskURL) else { return }
    appCheckedAt = now()
    guard let version = AppUpdate.version(inCask: text) else { return }
    appUpdate = AppUpdate.isNewer(version, than: current) ? version : nil
  }

  /// Whatever mise says, the version on disk decides: mise can fail after the bundle was swapped.
  public func upgradeApp(mise: CommandRunner, app: URL, expected: String) async -> UpdateOutcome {
    guard !blocked else { return .unchanged("Wait for the command that is running to finish.") }
    upgrading = true
    defer { upgrading = false }
    var said: String
    do {
      let out = try await mise.run(AppUpdate.upgradeArguments)
      said = [out.stdout, out.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    } catch {
      said = Self.message(error, tool: "mise") ?? "mise was not found at ~/.local/bin/mise."
    }
    switch Self.outcome(expected: expected, diskVersion: AppUpdate.diskVersion(app)) {
    case .relaunch: return .relaunch
    case .unchanged(let text): return .unchanged(said.isEmpty ? text : "\(text)\n\nmise said:\n\(said)")
    case .failed(let text): return .failed(said.isEmpty ? text : "\(text)\n\nmise said:\n\(said)")
    }
  }

  public static func outcome(expected: String, diskVersion: String?) -> UpdateOutcome {
    guard let disk = diskVersion else {
      return .failed(
        "Return of the Mac could not be read after the update. Download it again from \(AppUpdate.releasesURL)")
    }
    if disk == expected || AppUpdate.isNewer(disk, than: expected) { return .relaunch }
    return .unchanged(
      "Return of the Mac was not replaced and is still version \(disk). To try again, run this in Terminal:\n"
        + "mise bootstrap packages upgrade \(AppUpdate.package)")
  }

  public func useProfile(_ name: String) async {
    await perform("Switching to \(name)…", ["settings", "profile", "use", "--", name])
  }

  public func newProfile(_ name: String) async {
    await perform("Creating \(name)…", ["settings", "profile", "new", "--", name])
  }

  public func syncNow() async {
    await perform("Syncing…", ["settings", "sync", "now"])
  }

  public func dismissOutput() {
    lastOutput = nil
    lastError = nil
  }

  /// Work another part of the app does through its own runner (the settings
  /// window's Apply), counted as the one thing running.
  public func exclusive(_ label: String, _ work: () async -> Void) async {
    guard !blocked else { return }
    busy = label
    await work()
    await read()
    busy = nil
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
    await read()
    busy = nil
  }

  /// What Quit does now. `sessionTitle` names the console's running command.
  public func quitDecision(sessionTitle: String?, stagedEdits: Int) -> QuitDecision {
    if upgrading { return .refuse }
    if let sessionTitle { return .ask(message: "Stop \(sessionTitle) and quit?", detail: "Quitting stops the command.") }
    if let busy { return .ask(message: "Quit while a command is running?", detail: busy) }
    if stagedEdits == 1 {
      return .ask(message: "Quit and discard 1 change?", detail: "The settings window has a change you have not applied.")
    }
    if stagedEdits > 1 {
      return .ask(
        message: "Quit and discard \(stagedEdits) changes?", detail: "The settings window has changes you have not applied.")
    }
    return .allow
  }

  static let notFound = "rotm was not found at ~/dotfiles/bin/rotm."

  /// nil when the tool itself is gone.
  static func message(_ error: Error, tool: String = "rotm") -> String? {
    switch error as? CommandError {
    case .toolMissing: return nil
    case .readOnly(let s), .invalid(let s): return s
    case .failed(let code, let s): return s.isEmpty ? "\(tool) exited \(code)" : s
    case .timedOut: return "\(tool) did not finish in time."
    case .badJSON(let s): return "rotm printed something that is not JSON: \(s)"
    case nil: return error.localizedDescription
    }
  }
}
