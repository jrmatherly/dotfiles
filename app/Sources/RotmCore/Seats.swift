import Foundation

/// One jstack seat. The value formats match `SeatsEditor` and `LinesEditor` in
/// `settings/src/dotfiles_settings/tui_agents.py`, byte for byte.
public struct Seat: Equatable, Sendable {
  public let model: String
  public let effort: String

  public init(model: String, effort: String) {
    self.model = model
    self.effort = effort
  }

  /// The seat after its model changes: `inherit` and `codex` take no effort,
  /// and any other model keeps the seat's effort, or medium when it had none.
  public func with(model: String) -> Seat {
    Seat(model: model, effort: Seats.noEffort.contains(model) ? "" : (effort.isEmpty ? "medium" : effort))
  }
}

public enum Seats {
  public static let noEffort: Set<String> = ["inherit", "codex"]

  /// Lenient, as the terminal UI is: a model-only seat such as `opus` opens without being rewritten.
  public static func parse(_ value: String) -> [Seat] {
    value.components(separatedBy: ", ").map { seat in
      guard let space = seat.firstIndex(of: " ") else { return Seat(model: seat, effort: "") }
      return Seat(model: String(seat[..<space]), effort: String(seat[seat.index(after: space)...]))
    }
  }

  public static func format(_ seats: [Seat]) -> String {
    seats.filter { !$0.model.isEmpty }.map { $0.effort.isEmpty ? $0.model : "\($0.model) \($0.effort)" }
      .joined(separator: ", ")
  }
}

/// A `lines` setting: one entry per line, trimmed, blank lines dropped.
public enum Lines {
  public static func parse(_ value: String) -> [String] {
    let clean = format([value])
    return clean.isEmpty ? [] : clean.components(separatedBy: "\n")
  }

  public static func format(_ entries: [String]) -> String {
    entries.flatMap { $0.components(separatedBy: .newlines) }
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
  }
}
