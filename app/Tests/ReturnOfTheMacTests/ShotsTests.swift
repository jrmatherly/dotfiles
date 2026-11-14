import AppKit
import Foundation
import RotmCore
import RotmTestSupport
import SwiftUI
import Testing

@testable import ReturnOfTheMac

/// Renders the windows to PNGs in light and dark, from the fixtures. Runs only
/// with UI_SHOTS_DIR set: `pnpm shots`, or
/// `UI_SHOTS_DIR=.shots swift test --package-path app --filter Shots`.
private let shotsDir = ProcessInfo.processInfo.environment["UI_SHOTS_DIR"]

@MainActor
private func fixtureState() async -> (AppState, FakeRunner) {
  let runner = FakeRunner()
  runner.stub(["settings", "list", "--json"], .success(CommandOutput(stdout: Fixtures.list, stderr: "")))
  runner.stub(["settings", "status", "--json"], .success(CommandOutput(stdout: Fixtures.status, stderr: "")))
  runner.stub(["update", "--check", "--json"], .success(CommandOutput(stdout: Fixtures.updateCheck, stderr: "")))
  let state = AppState(makeRunner: { _ in runner }, locate: { URL(fileURLWithPath: "/fake/rotm") })
  await state.refresh()
  return (state, runner)
}

/// The settings window, loaded before it is shown so the shot never catches the progress indicator.
@MainActor
private func settingsWindow(section: String? = nil) async -> SettingsWindowController {
  let (state, runner) = await fixtureState()
  let controller = SettingsWindowController(state: state, runner: runner, section: section)
  await controller.model.load()
  controller.show()
  return controller
}

/// A view that is not a window of its own (a sheet), in a borderless window of its fitting size.
@MainActor
private func hosting(_ view: some View) -> NSWindow {
  let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
  host.frame = CGRect(origin: .zero, size: host.fittingSize)
  let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  return window
}

/// Writes `<name>-light.png` and `<name>-dark.png`, opening a fresh window for each.
@MainActor
private func shoot(_ name: String, _ open: () async throws -> NSWindow) async throws {
  defer { NSApp.appearance = nil }
  for dark in [false, true] {
    // Set before the window exists, so every view is made in this appearance.
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = try await open()
    try await Task.sleep(nanoseconds: 500_000_000)
    let view = try #require(window.contentView?.superview ?? window.contentView)
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let png = try #require(rep.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: shotsDir!).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    window.close()
  }
}

/// The console running a temp script, never `rotm`, once `ready` holds.
@MainActor
private func consoleWindow(_ body: String, sessions: inout [ConsoleSession], ready: (ConsoleSession) -> Bool) async throws
  -> NSWindow
{
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotm-shots-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let script = dir.appendingPathComponent("update")
  try "#!/bin/bash\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
  let session = ConsoleSession(
    title: "Update", command: [script.path], environment: ["TERM": "dumb"], logDirectory: dir.appendingPathComponent("logs"))
  sessions.append(session)
  let controller = ConsoleWindowController()
  controller.run(session) {}
  let deadline = Date().addingTimeInterval(20)
  while !ready(session), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
  #expect(ready(session), "the script reached the state the shot is of")
  return controller.window
}

private let updateOutput = """
  echo "Already on 'stable'"
  echo "Your branch is up to date with 'origin/stable'."
  echo 'Updating 2 packages with mise bootstrap'
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "  [ok]  ~/.config/tool-$n -> ~/dotfiles/tilde/.config/tool-$n"; done
  echo 'A long line that a narrow window has to wrap rather than clip, so nothing past the right edge is lost from view.'
  """

private func editableFields(in view: NSView) -> [NSTextField] {
  let mine = (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
  return mine + view.subviews.flatMap(editableFields)
}

@Suite(.serialized, .enabled(if: shotsDir != nil)) @MainActor struct Shots {
  init() throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(atPath: shotsDir!, withIntermediateDirectories: true)
  }

  @Test func settings() async throws {
    try await shoot("settings-setup") { await settingsWindow().window }
    try await shoot("settings-agents") { await settingsWindow(section: "Agents").window }
    try await shoot("settings-agents-staged") {
      let controller = await settingsWindow(section: "Agents")
      controller.model.stage("jstack.arena_runners", value: "claude-fable-5-2 medium, opus medium, inherit", shared: false)
      controller.model.stage("hindsight.paths", value: "~/dev\n~/src\n~/work", shared: false)
      return controller.window
    }
  }

  @Test func review() async throws {
    let (_, runner) = await fixtureState()
    let model = SettingsModel(runner: runner)
    await model.load()
    model.stage("updates.mac_password_op", value: #"-a "b" #c"#, shared: false)
    model.stage("jstack.arena_runners", value: "claude-fable-5-2 medium, opus medium, sonnet high", shared: false)
    #expect(model.staged.count == 2)
    try await shoot("settings-review") { hosting(ReviewSheet(edits: model.staged, blocked: false, apply: {}, cancel: {})) }
  }

  @Test func console() async throws {
    var sessions: [ConsoleSession] = []
    try await shoot("console-running") {
      try await consoleWindow(updateOutput + "\necho 'Installing packages…'; sleep 60", sessions: &sessions) {
        $0.text.contains("Installing packages")
      }
    }
    try await shoot("console-password") {
      try await consoleWindow(
        updateOutput + "\necho '/!\\ Activate sudo /!\\'; stty -echo; printf 'Password:'; read -r p", sessions: &sessions
      ) { $0.wantsSecret }
    }
    sessions.forEach { $0.stop() }
    for session in sessions {
      let deadline = Date().addingTimeInterval(10)
      while session.phase == .running, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
      #expect(session.phase == .stopped)
    }
  }

  @Test func noFieldTakesFocusOnOpen() async throws {
    let controller = await settingsWindow()
    try await Task.sleep(nanoseconds: 500_000_000)
    let frame = try #require(controller.window.contentView?.superview)
    #expect(!editableFields(in: frame).isEmpty, "the window has no text field, so the check proves nothing")
    #expect(!(controller.window.firstResponder is NSText), "a text field took focus on open")
    controller.window.close()
  }
}
