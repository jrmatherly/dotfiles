import Foundation
import Observation

public struct Edit: Equatable, Sendable {
  public enum Change: Equatable, Sendable { case set(String), reset }
  public let settingId: String
  public let change: Change
  public let shared: Bool

  public init(settingId: String, change: Change, shared: Bool) {
    self.settingId = settingId
    self.change = change
    self.shared = shared
  }

  public var arguments: [String] {
    let flag = shared ? ["--shared"] : []
    switch change {
    case .set(let value): return ["settings", "set"] + flag + [settingId, "--", value]
    case .reset: return ["settings", "reset"] + flag + [settingId]
    }
  }

  /// What a terminal user would type, for the review sheet.
  public var commandLine: String {
    (["rotm"] + arguments).map { arg in
      // zsh expands a leading = to a command's path.
      arg.range(of: #"^[A-Za-z0-9_./:=@%+,-]+$"#, options: .regularExpression) != nil && !arg.hasPrefix("=")
        ? arg : "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }.joined(separator: " ")
  }
}

@MainActor @Observable public final class SettingsModel {
  public private(set) var rows: [SettingRow] = []
  public private(set) var loading = false
  public private(set) var staged: [Edit] = []
  public private(set) var notes: [String] = []
  public private(set) var failures: [String] = []
  public var search = ""

  public var sections: [String] {
    var seen: [String] = []
    for row in rows where matches(row) && !seen.contains(row.section) { seen.append(row.section) }
    return seen
  }

  public func rows(in section: String) -> [SettingRow] {
    rows.filter { $0.section == section && matches($0) }
  }

  private let runner: CommandRunner
  private var generation = 0

  public init(runner: CommandRunner) {
    self.runner = runner
  }

  public func load() async {
    generation += 1
    let mine = generation
    loading = true
    defer { if mine == generation { loading = false } }
    do {
      let fresh = try Decode.rows(try await runner.run(["settings", "list", "--json"]).stdout)
      // A slower, older load must not overwrite a newer one.
      guard mine == generation else { return }
      rows = fresh
      staged.removeAll { !differs($0) }
    } catch {
      guard mine == generation else { return }
      failures.append("settings list: \(AppState.message(error) ?? AppState.notFound)")
    }
  }

  public func stage(_ id: String, value: String, shared: Bool) {
    put(Edit(settingId: id, change: .set(value), shared: shared))
  }

  public func stageReset(_ id: String, shared: Bool) {
    put(Edit(settingId: id, change: .reset, shared: shared))
  }

  public func unstage(_ id: String) {
    staged.removeAll { $0.settingId == id }
  }

  public func dismissResults() {
    notes = []
    failures = []
  }

  public func applyStaged() async {
    let batch = staged
    guard !batch.isEmpty else { return }
    staged = []
    notes = []
    failures = []
    for edit in batch {
      do {
        let out = try await runner.run(edit.arguments)
        if !out.stderr.isEmpty { notes.append(out.stderr) }
      } catch {
        failures.append("\(edit.settingId): \(AppState.message(error) ?? AppState.notFound)")
        // The load below drops it if it took after all; an edit staged meanwhile wins.
        if !staged.contains(where: { $0.settingId == edit.settingId }) { staged.append(edit) }
      }
    }
    await load()
  }

  private func put(_ edit: Edit) {
    guard let row = rows.first(where: { $0.settingId == edit.settingId }), row.access != "ro" else { return }
    guard differs(edit) else { return unstage(edit.settingId) }
    if let i = staged.firstIndex(where: { $0.settingId == edit.settingId }) {
      staged[i] = edit
    } else {
      staged.append(edit)
    }
  }

  /// False once the row already holds what the edit would make it, or is gone or read-only.
  private func differs(_ edit: Edit) -> Bool {
    guard let row = rows.first(where: { $0.settingId == edit.settingId }), row.access != "ro" else { return false }
    switch edit.change {
    case .reset: return row.source == "override"
    case .set(let value):
      let current = row.value ?? ""
      return row.type == "bool" ? Self.isOn(value) != Self.isOn(current) : value != current
    }
  }

  /// The words the command line takes for on (`cli.py` TRUE); every registry
  /// true_value is one of them, and off is stored as an empty value.
  public static func isOn(_ value: String) -> Bool {
    ["true", "on", "yes", "1"].contains(value.lowercased())
  }

  private func matches(_ row: SettingRow) -> Bool {
    let q = search.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return true }
    return [row.label, row.settingId, row.help].contains { $0.localizedCaseInsensitiveContains(q) }
  }
}
