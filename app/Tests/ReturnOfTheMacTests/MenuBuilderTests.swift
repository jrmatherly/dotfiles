import AppKit
import Foundation
import RotmCore
import RotmTestSupport
import Testing

@testable import ReturnOfTheMac

private let installed = Fixtures.status.replacingOccurrences(of: #""mode": "clone""#, with: #""mode": "installed""#)
private let upToDate = #"{"mode":"installed","branch":"stable","behind":0}"#

@MainActor
private func state(status: String = installed, check: String = upToDate, located: Bool = true) async -> AppState {
  let runner = FakeRunner()
  runner.stub(["settings", "status", "--json"], .success(CommandOutput(stdout: status, stderr: "")))
  runner.stub(["update", "--check", "--json"], .success(CommandOutput(stdout: check, stderr: "")))
  runner.stub(["settings", "sync", "now"], .success(CommandOutput(stdout: "Synced.", stderr: "")))
  let state = AppState(makeRunner: { _ in runner }, locate: { located ? URL(fileURLWithPath: "/fake/rotm") : nil })
  await state.refresh()
  return state
}

private func profiles(active: String, enabled: Bool = true) -> MenuEntry {
  MenuEntry(
    title: "Profile: \(active)",
    kind: .submenu([
      MenuEntry(title: "default", kind: .toggle(active == "default", "useProfile:default"), enabled: enabled && active != "default"),
      MenuEntry(title: "work", kind: .toggle(active == "work", "useProfile:work"), enabled: enabled && active != "work"),
      .separator,
      .action("New Profile…", "newProfile", enabled: enabled),
    ]),
    enabled: true)
}

private let more = MenuEntry(
  title: "More",
  kind: .submenu([
    .action("Run Setup Again…", "runSetup", enabled: false),
    .action("Apply macOS Preferences…", "applyMacOS", enabled: false),
    .separator,
    MenuEntry(title: "Launch at Login", kind: .toggle(false, "launchAtLogin"), enabled: true),
  ]),
  enabled: true)

private func menu(profile: MenuEntry, sync: [MenuEntry], setup: String) -> [MenuEntry] {
  [profile, .separator] + sync + [
    .separator,
    .info(setup),
    .action("Update…", "update", enabled: false),
    .separator,
    more,
    .action("Settings…", "settings", enabled: false),
    .separator,
    .action("Quit", "quit"),
  ]
}

private let syncOff: [MenuEntry] = [.info("Sync: off"), .action("Turn On Sync…", "turnOnSync", enabled: false)]

@MainActor
struct MenuBuilderTests {
  @Test func aCleanStatus() async {
    let entries = MenuBuilder.entries(for: await state(), launchAtLogin: false)
    #expect(entries == menu(profile: profiles(active: "default"), sync: syncOff, setup: "Setup: up to date"))
  }

  @Test func theWorkProfileIsTicked() async {
    let work = installed.replacingOccurrences(of: #""active": "default""#, with: #""active": "work""#)
    let entries = MenuBuilder.entries(for: await state(status: work), launchAtLogin: false)
    #expect(entries == menu(profile: profiles(active: "work"), sync: syncOff, setup: "Setup: up to date"))
  }

  @Test func aMissingToolIsItsMessageAndQuit() async {
    let s = await state(located: false)
    guard case .missing(let message) = s.tool else { Issue.record("tool is \(s.tool)"); return }
    #expect(
      MenuBuilder.entries(for: s, launchAtLogin: true) == [
        .info(message), .separator, .action("Settings…", "settings", enabled: false), .action("Quit", "quit"),
      ])
  }

  @Test func twoUpdatesWaiting() async {
    let entries = MenuBuilder.entries(for: await state(check: Fixtures.updateCheck), launchAtLogin: false)
    #expect(entries == menu(profile: profiles(active: "default"), sync: syncOff, setup: "Setup: 2 updates waiting"))
  }

  @Test func aDevelopmentClone() async {
    let clone = #"{"mode":"clone","branch":"main","behind":null}"#
    let entries = MenuBuilder.entries(for: await state(status: Fixtures.status, check: clone), launchAtLogin: false)
    #expect(entries == menu(profile: profiles(active: "default"), sync: syncOff, setup: "Setup: development clone"))
  }

  @Test func blockedDisablesEveryAction() async {
    let on = installed
      .replacingOccurrences(of: #""connected": false"#, with: #""connected": true"#)
      .replacingOccurrences(of: #""waiting": []"#, with: #""waiting": ["a", "b"]"#)
    let s = await state(status: on)
    let open = [MenuEntry.info("Sync: on, 2 changes waiting"), .action("Sync Now", "syncNow")]
    #expect(MenuBuilder.entries(for: s, launchAtLogin: false) == menu(profile: profiles(active: "default"), sync: open, setup: "Setup: up to date"))
    s.sessionRunning = true
    let closed = [MenuEntry.info("Sync: on, 2 changes waiting"), .action("Sync Now", "syncNow", enabled: false)]
    #expect(
      MenuBuilder.entries(for: s, launchAtLogin: false)
        == menu(profile: profiles(active: "default", enabled: false), sync: closed, setup: "Setup: up to date"))
  }

  @Test func theLastOutputLeadsWithDismiss() async {
    let s = await state()
    await s.syncNow()
    let entries = MenuBuilder.entries(for: s, launchAtLogin: false)
    #expect(Array(entries.prefix(3)) == [.info("Synced."), .action("Dismiss", "dismiss"), .separator])
  }

  @Test func theAttentionSymbolExists() {
    #expect(NSImage(systemSymbolName: "desktopcomputer.trianglebadge.exclamationmark", accessibilityDescription: nil) != nil)
  }
}
