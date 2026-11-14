import Foundation
import Observation

/// The commands the console runs, one row per menu action.
public struct ConsoleCommand: Equatable, Sendable {
  public let action: String
  public let title: String
  public let question: String
  public let button: String
  let program: String
  let arguments: [String]

  public static let all = [
    ConsoleCommand(
      action: "update", title: "Update", question: "Update your setup?", button: "Update",
      program: "rotm", arguments: ["update", "-y"]),
    ConsoleCommand(
      action: "runSetup", title: "Run Setup Again", question: "Run setup again?", button: "Run Setup",
      program: "rotm", arguments: ["install", "-y"]),
    ConsoleCommand(
      action: "applyMacOS", title: "Apply macOS Preferences", question: "Apply the macOS preferences?", button: "Apply",
      program: "set-defaults", arguments: []),
    ConsoleCommand(
      action: "turnOnSync", title: "Turn On Sync", question: "Turn on sync?", button: "Turn On",
      program: "rotm", arguments: ["settings", "sync", "on"]),
  ]

  public static func named(_ action: String) -> ConsoleCommand? { all.first { $0.action == action } }

  public func command(home: URL) -> [String] {
    [home.appendingPathComponent("dotfiles/bin/\(program)").path] + arguments
  }

  /// What the confirmation alert names.
  public var commandLine: String {
    ([program == "rotm" ? "rotm" : "~/dotfiles/bin/\(program)"] + arguments).joined(separator: " ")
  }

  /// Without GH_ACCESSIBLE_PROMPTER, gh's sign-in prompt asks the terminal
  /// where the cursor is and waits forever for a reply `script` never sends.
  public static func environment(home: URL) -> [String: String] {
    ["PATH": CLI.searchPath(home: home), "TERM": "dumb", "GH_ACCESSIBLE_PROMPTER": "1"]
  }
}

/// One command run under `/usr/bin/script`, so it has a terminal for its
/// prompts, with its output kept as text, as the same text in styled runs,
/// and in a private log.
@MainActor @Observable public final class ConsoleSession {
  public enum Phase: Equatable { case running, finished(Int32), stopped }

  public private(set) var text = ""
  /// `text` cut where the colour or weight changes: their texts joined are always `text`.
  public private(set) var runs: [StyledRun] = []
  public private(set) var phase: Phase = .running
  public private(set) var wantsSecret = false
  public let title: String
  public let logURL: URL

  static let cap = 200_000
  private static let keptLogs = 20
  private static let partialEscape = "\u{1B}(\\[[0-9;?]*|\\][^\u{07}\u{1B}]*|[()])?\\z"
  private static let secretPrompt = "(?i)password.*:\\s*$"

  private let command: [String]
  private let environment: [String: String]
  @ObservationIgnored private var process: Process?
  @ObservationIgnored private var input: FileHandle?
  @ObservationIgnored private var log: FileHandle?
  @ObservationIgnored private var pending = Data()
  @ObservationIgnored private var parser = AnsiParser()
  @ObservationIgnored private var carriage = false
  @ObservationIgnored private var exitStatus: Int32?
  @ObservationIgnored private var outputDone = false
  @ObservationIgnored private var stopping = false

  public init(title: String, command: [String], environment: [String: String], logDirectory: URL) {
    self.title = title
    self.command = command
    self.environment = environment
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    logURL = logDirectory.appendingPathComponent("\(formatter.string(from: Date()))-\(title).log")
    let fd = open(logURL.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
    if fd >= 0 {
      fchmod(fd, 0o600)
      log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    Self.prune(logDirectory, keeping: logURL.lastPathComponent)
  }

  public func start() {
    guard process == nil, phase == .running else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
    p.arguments = ["-q", "/dev/null"] + command
    // setup.sh records its run under a second `script` unless this is set.
    p.environment = ProcessInfo.processInfo.environment
      .merging(environment) { $1 }
      .merging(["DOTFILES_SETUP_LOG": logURL.path]) { $1 }
    // An anonymous pipe: `script` refuses a named one as stdin.
    let stdin = Pipe()
    let output = Pipe()
    p.standardInput = stdin
    p.standardOutput = output
    p.standardError = output
    // A write racing the child's exit returns EPIPE instead of killing the app.
    _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    p.terminationHandler = { p in
      let status = p.terminationStatus
      DispatchQueue.main.async { MainActor.assumeIsolated { self.exited(status) } }
    }
    output.fileHandleForReading.readabilityHandler = { h in
      let chunk = h.availableData
      if chunk.isEmpty { h.readabilityHandler = nil }
      DispatchQueue.main.async { MainActor.assumeIsolated { self.receive(chunk) } }
    }
    do {
      try p.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      text = "Could not start \(command.first ?? "the command"): \(error.localizedDescription)\n"
      runs = [StyledRun(text: text, style: TextStyle())]
      phase = .finished(127)
      return
    }
    process = p
    input = stdin.fileHandleForWriting
  }

  public func send(_ line: String) {
    guard phase == .running, let input else { return }
    wantsSecret = false
    try? input.write(contentsOf: Data((line + "\n").utf8))
  }

  public func stop() {
    guard phase == .running, let process else { return }
    stopping = true
    try? input?.write(contentsOf: Data([0x03]))
    let pid = process.processIdentifier
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      MainActor.assumeIsolated {
        guard self.exitStatus == nil, self.phase == .running else { return }
        // The command dies of the hangup when its terminal's master side closes.
        kill(pid, SIGKILL)
      }
    }
  }

  private func exited(_ status: Int32) {
    exitStatus = status
    finishIfDone()
    // A grandchild holding the output open must not keep the session running.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      MainActor.assumeIsolated {
        self.outputDone = true
        self.finishIfDone()
      }
    }
  }

  private func finishIfDone() {
    guard phase == .running, let status = exitStatus, outputDone else { return }
    phase = stopping ? .stopped : .finished(status)
    wantsSecret = false
    try? input?.close()
    input = nil
    try? log?.close()
    log = nil
    process?.terminationHandler = nil
    process = nil
  }

  func receive(_ chunk: Data) {
    guard !chunk.isEmpty else {
      outputDone = true
      finishIfDone()
      return
    }
    guard phase == .running else { return }
    pending.append(chunk)
    let whole = Self.completeUTF8(pending)
    var string = String(decoding: pending.prefix(whole), as: UTF8.self)
    pending = pending.suffix(from: pending.startIndex + whole)
    if let partial = string.range(of: Self.partialEscape, options: .regularExpression) {
      pending = Data(string[partial].utf8) + pending
      string.removeSubrange(partial)
    }
    var logged = String.UnicodeScalarView()
    for run in parser.parse(string) { append(run.text, run.style, logged: &logged) }
    if text.utf8.count > Self.cap, text.count > Self.cap {
      let scalars = text.unicodeScalars.count
      text.removeFirst(text.count - Self.cap)
      dropFirstScalars(scalars - text.unicodeScalars.count)
    }
    try? log?.write(contentsOf: Data(String(logged).utf8))
    let lastLine = text.lastIndex(of: "\n").map { text[text.index(after: $0)...] } ?? text[...]
    wantsSecret = lastLine.range(of: Self.secretPrompt, options: .regularExpression) != nil
  }

  /// A bare \r starts the line over; \r\n, which the terminal makes of every
  /// \n, is a newline. A \r at the end of a chunk waits for the next one.
  private func append(_ plain: String, _ style: TextStyle, logged: inout String.UnicodeScalarView) {
    var shown = String.UnicodeScalarView()
    for scalar in plain.unicodeScalars {
      if carriage, scalar != "\n", scalar != "\r" {
        add(String(shown), style)
        shown = String.UnicodeScalarView()
        startLineOver()
        logged.append("\r")
      }
      carriage = scalar == "\r"
      if !carriage {
        shown.append(scalar)
        logged.append(scalar)
      }
    }
    add(String(shown), style)
  }

  private func add(_ shown: String, _ style: TextStyle) {
    guard !shown.isEmpty else { return }
    text += shown
    if let last = runs.last, last.style == style {
      runs[runs.count - 1] = StyledRun(text: last.text + shown, style: style)
    } else {
      runs.append(StyledRun(text: shown, style: style))
    }
  }

  /// A newline is a character of its own, so cutting the text and the runs
  /// after their last one keeps them equal.
  private func startLineOver() {
    if let newline = text.lastIndex(of: "\n") {
      text.removeSubrange(text.index(after: newline)...)
    } else {
      text = ""
    }
    while let last = runs.last {
      if let newline = last.text.unicodeScalars.lastIndex(of: "\n") {
        let kept = String(last.text.unicodeScalars[...newline])
        if kept != last.text { runs[runs.count - 1] = StyledRun(text: kept, style: last.style) }
        return
      }
      runs.removeLast()
    }
  }

  private func dropFirstScalars(_ count: Int) {
    var left = count
    var whole = 0
    for run in runs {
      let length = run.text.unicodeScalars.count
      guard length <= left else { break }
      left -= length
      whole += 1
    }
    runs.removeFirst(whole)
    if left > 0, let first = runs.first {
      runs[0] = StyledRun(text: String(first.text.unicodeScalars.dropFirst(left)), style: first.style)
    }
  }

  /// The length of the longest prefix that does not end inside a UTF-8 sequence.
  private static func completeUTF8(_ data: Data) -> Int {
    let bytes = [UInt8](data.suffix(4))
    for back in stride(from: 1, through: bytes.count, by: 1) {
      let byte = bytes[bytes.count - back]
      guard byte & 0xC0 == 0x80 else {
        let length = byte < 0x80 ? 1 : byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
        return length > back ? data.count - back : data.count
      }
    }
    return data.count
  }

  private static func prune(_ directory: URL, keeping current: String) {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
    let others = names.filter { $0.hasSuffix(".log") && $0 != current }.sorted(by: >)
    for name in others.dropFirst(keptLogs - 1) { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
  }
}
