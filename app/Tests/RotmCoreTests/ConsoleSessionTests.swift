import Foundation
import RotmCore
import Testing

private func tempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotm-console-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

/// A session that runs `body` as a bash script, logging to a fresh directory.
@MainActor
private func session(_ body: String, environment: [String: String] = ["TERM": "dumb"]) throws -> ConsoleSession {
  let dir = try tempDir()
  let script = dir.appendingPathComponent("child")
  try "#!/bin/bash\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
  return ConsoleSession(
    title: "Test", command: [script.path], environment: environment, logDirectory: dir.appendingPathComponent("logs"))
}

/// Polls until `condition` holds, so a slow machine only makes the test slower.
@MainActor
private func until(_ seconds: Double = 20, _ condition: () -> Bool) async -> Bool {
  let deadline = Date().addingTimeInterval(seconds)
  while !condition() {
    if Date() > deadline { return false }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
  return true
}

@MainActor
private func ended(_ s: ConsoleSession, within seconds: Double = 20) async -> Bool {
  await until(seconds) { s.phase != .running }
}

private func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

@MainActor
struct ConsoleSessionTests {
  @Test func theChildSeesATerminal() async throws {
    let s = try session("if test -t 0 && test -t 1; then echo tty; else echo notty; fi")
    s.start()
    #expect(await ended(s))
    #expect(s.phase == .finished(0))
    #expect(lines(s.text) == ["tty"])
  }

  @Test func aLineSentLaterReachesRead() async throws {
    let s = try session(#"read -r line; echo "got:$line""#)
    s.start()
    try await Task.sleep(nanoseconds: 2_000_000_000)
    s.send("hello there")
    #expect(await ended(s))
    #expect(lines(s.text).contains("got:hello there"))
  }

  // sudo's prompt, as row 2 of the P5 probe recorded it under `rotm update -y`. Like sudo, echo goes off before the prompt.
  @Test func aPasswordPromptHidesTheField() async throws {
    let s = try session(#"echo '/!\ Activate sudo /!\'; stty -echo; printf 'Password:'; read -r secret; stty echo; echo; echo "len:${#secret}""#)
    s.start()
    #expect(await until { s.text.hasSuffix("Password:") })
    #expect(s.wantsSecret)
    s.send("hunter2-secret")
    #expect(await ended(s))
    #expect(s.phase == .finished(0))
    #expect(lines(s.text).contains("len:14"), "the line reached the child")
    #expect(!s.text.contains("hunter2"))
    let log = try String(contentsOf: s.logURL, encoding: .utf8)
    #expect(log.contains("len:14"))
    #expect(!log.contains("hunter2"))
    #expect(!s.wantsSecret)
  }

  // The last two are gh's prompts from the probe's row 5, with GH_ACCESSIBLE_PROMPTER=1
  @Test(arguments: [
    "Proceed? [y/N] ",
    "Authenticate Git with your GitHub credentials? (default: yes) [Y/n] ",
    "Press Enter to open https://github.com/login/device in your browser... ",
  ])
  func anUnknownPromptKeepsAVisibleInputLine(prompt: String) async throws {
    let s = try session(#"printf '%s' '\#(prompt)'; read -r a; echo "answer:$a""#)
    s.start()
    #expect(await until { s.text.hasSuffix(prompt) })
    #expect(!s.wantsSecret)
    s.send("y")
    #expect(await ended(s))
    #expect(lines(s.text).contains("answer:y"))
  }

  @Test func stopInterruptsTheCommand() async throws {
    let s = try session("trap 'echo interrupted; exit 3' INT; echo ready; while true; do sleep 0.1; done")
    s.start()
    #expect(await until { lines(s.text).contains("ready") })
    s.stop()
    #expect(await ended(s))
    #expect(s.phase == .stopped)
    #expect(lines(s.text).contains { $0.hasSuffix("interrupted") })
  }

  @Test func stopEndsACommandThatIgnoresTheInterrupt() async throws {
    let s = try session("trap '' INT; echo ready; sleep 30")
    s.start()
    #expect(await until { lines(s.text).contains("ready") })
    let start = Date()
    s.stop()
    #expect(await ended(s, within: 3))
    #expect(Date().timeIntervalSince(start) < 3)
    #expect(s.phase == .stopped)
  }

  @Test func theExitCodeComesBack() async throws {
    let s = try session("echo bye; exit 7")
    s.start()
    #expect(await ended(s))
    #expect(s.phase == .finished(7))
    s.send("too late")
    s.stop()
    #expect(s.phase == .finished(7))
  }

  @Test func theTextKeepsTheLast200000CharactersAndTheLogKeepsAll() async throws {
    let s = try session("yes 0123456789012345678 | head -n 15000")
    s.start()
    #expect(await ended(s, within: 60))
    #expect(s.phase == .finished(0))
    #expect(s.text.count == 200_000)
    #expect(s.text.hasSuffix("0123456789012345678\n"))
    let log = try String(contentsOf: s.logURL, encoding: .utf8)
    #expect(log == String(repeating: "0123456789012345678\n", count: 15000))
  }

  @Test func theLogIsPrivate() throws {
    let s = try session("true")
    let mode = try FileManager.default.attributesOfItem(atPath: s.logURL.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
    #expect(s.logURL.lastPathComponent.hasSuffix("-Test.log"))
  }

  @Test func aBareReturnStartsTheLineOver() async throws {
    let s = try session(#"printf 'a\rb\n'; printf '50%%\r100%%\r\n'; printf 'one\r\r\ntwo\n'"#)
    s.start()
    #expect(await ended(s))
    #expect(s.text == "b\n100%\none\ntwo\n")
  }

  @Test func aCharacterOrAnEscapeSplitAcrossWritesArrivesWhole() async throws {
    let s = try session(#"printf '\303'; sleep 0.3; printf '\251\n'; printf '\033[3'; sleep 0.3; printf '1mred\033[0m\n'"#)
    s.start()
    #expect(await ended(s))
    #expect(s.text == "é\nred\n")
  }

  @Test func theNewest20LogsAreKept() throws {
    let logs = try tempDir()
    let old = logs.appendingPathComponent("20200101-000000-Old.log")
    try "".write(to: old, atomically: true, encoding: .utf8)
    var last: ConsoleSession?
    for n in 1...21 {
      last = ConsoleSession(title: String(format: "t%02d", n), command: ["/usr/bin/true"], environment: [:], logDirectory: logs)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: logs.path)
    #expect(names.count == 20)
    #expect(!names.contains(old.lastPathComponent))
    #expect(names.contains(try #require(last).logURL.lastPathComponent))
  }

  @Test func theChildGetsTheTableEnvironmentAndTheSessionLog() async throws {
    let home = URL(fileURLWithPath: "/Users/someone")
    let s = try session(
      #"printf '%s\n' "$PATH" "$TERM" "$GH_ACCESSIBLE_PROMPTER" "$DOTFILES_SETUP_LOG""#,
      environment: ConsoleCommand.environment(home: home))
    s.start()
    #expect(await ended(s))
    #expect(lines(s.text) == [CLI.searchPath(home: home), "dumb", "1", s.logURL.path])
  }
}

struct ConsoleCommandTests {
  @Test func oneRowPerMenuAction() {
    let home = URL(fileURLWithPath: "/Users/someone")
    let rows = ConsoleCommand.all.map { [$0.action, $0.title] + $0.command(home: home) }
    #expect(
      rows == [
        ["update", "Update", "/Users/someone/dotfiles/bin/rotm", "update", "-y"],
        ["runSetup", "Run Setup Again", "/Users/someone/dotfiles/bin/rotm", "install", "-y"],
        ["applyMacOS", "Apply macOS Preferences", "/Users/someone/dotfiles/bin/set-defaults"],
        ["turnOnSync", "Turn On Sync", "/Users/someone/dotfiles/bin/rotm", "settings", "sync", "on"],
      ])
    #expect(ConsoleCommand.named("update")?.commandLine == "rotm update -y")
    #expect(ConsoleCommand.named("applyMacOS")?.commandLine == "~/dotfiles/bin/set-defaults")
    #expect(ConsoleCommand.named("syncNow") == nil)
  }

  @Test func theEnvironmentIsTheGUIPathADumbTerminalAndGhsLinePrompts() {
    let home = URL(fileURLWithPath: "/Users/someone")
    #expect(
      ConsoleCommand.environment(home: home)
        == ["PATH": CLI.searchPath(home: home), "TERM": "dumb", "GH_ACCESSIBLE_PROMPTER": "1"])
  }
}
