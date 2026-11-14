import Foundation

/// A foreground colour a command asked for: one of the 16 basic colours,
/// which the view maps to its palette, or an exact 24-bit colour.
public enum ConsoleColor: Equatable, Sendable {
  case basic(Int)
  case rgb(UInt8, UInt8, UInt8)

  /// The 256-colour form `38;5;n`.
  static func indexed(_ n: Int) -> ConsoleColor {
    switch n {
    case ..<16: return .basic(max(n, 0))
    case 16..<232:
      let level = { (v: Int) in UInt8(v == 0 ? 0 : 55 + 40 * v) }
      let i = n - 16
      return .rgb(level(i / 36), level(i / 6 % 6), level(i % 6))
    default:
      let grey = UInt8(8 + 10 * (min(n, 255) - 232))
      return .rgb(grey, grey, grey)
    }
  }
}

public struct TextStyle: Equatable, Sendable {
  public var foreground: ConsoleColor?
  public var bold: Bool

  public init(foreground: ConsoleColor? = nil, bold: Bool = false) {
    self.foreground = foreground
    self.bold = bold
  }
}

public struct StyledRun: Equatable, Sendable {
  public let text: String
  public let style: TextStyle

  public init(text: String, style: TextStyle) {
    self.text = text
    self.style = style
  }
}

/// Turns terminal output into styled text: SGR colour and bold become the
/// style, every other escape sequence is dropped. The style carries over from
/// one call to the next. Input must not end inside an escape sequence.
public struct AnsiParser: Sendable {
  public private(set) var style = TextStyle()

  static let escape = try! NSRegularExpression(
    pattern: "\u{1B}(\\[[0-9;?]*[A-Za-z]|\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|[()][A-Z0-9]|[=>])|\u{07}")

  public init() {}

  public mutating func parse(_ string: String) -> [StyledRun] {
    var runs: [StyledRun] = []
    let add = { (text: Substring, style: TextStyle, runs: inout [StyledRun]) in
      guard !text.isEmpty else { return }
      if let last = runs.last, last.style == style {
        runs[runs.count - 1] = StyledRun(text: last.text + text, style: style)
      } else {
        runs.append(StyledRun(text: String(text), style: style))
      }
    }
    var start = string.startIndex
    for match in Self.escape.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
      guard let range = Range(match.range, in: string) else { continue }
      add(string[start..<range.lowerBound], style, &runs)
      let sequence = string[range]
      if sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("m") {
        apply(sequence.dropFirst(2).dropLast())
      }
      start = range.upperBound
    }
    add(string[start...], style, &runs)
    return runs
  }

  private mutating func apply(_ parameters: Substring) {
    // An empty parameter means 0, so `ESC[m` and `ESC[;1m` reset as terminals do.
    let codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
    var i = 0
    while i < codes.count {
      let code = codes[i]
      i += 1
      switch code {
      case 0: style = TextStyle()
      case 1: style.bold = true
      case 22: style.bold = false
      case 30...37: style.foreground = .basic(code - 30)
      case 90...97: style.foreground = .basic(code - 90 + 8)
      case 39: style.foreground = nil
      case 38, 48:
        // The colour's own numbers follow, and must not be read as codes.
        let mode = i < codes.count ? codes[i] : -1
        let count = mode == 5 ? 1 : mode == 2 ? 3 : 0
        let values = codes.dropFirst(i + 1).prefix(count).map { UInt8(clamping: $0) }
        if code == 38, values.count == count {
          if mode == 5 { style.foreground = ConsoleColor.indexed(codes[i + 1]) }
          if mode == 2 { style.foreground = .rgb(values[0], values[1], values[2]) }
        }
        i += 1 + count
      default: break
      }
    }
  }
}
