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

  @Test func noFieldTakesFocusOnOpen() async throws {
    let controller = await settingsWindow()
    try await Task.sleep(nanoseconds: 500_000_000)
    let frame = try #require(controller.window.contentView?.superview)
    #expect(!editableFields(in: frame).isEmpty, "the window has no text field, so the check proves nothing")
    #expect(!(controller.window.firstResponder is NSText), "a text field took focus on open")
    controller.window.close()
  }
}
