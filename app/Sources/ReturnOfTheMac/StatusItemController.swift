import AppKit
import Observation
import RotmCore
import ServiceManagement

/// Draws `MenuBuilder`'s entries and turns a chosen entry into an `AppState`
/// call, after an alert naming the command.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  private let state: AppState
  private var statusItem: NSStatusItem?
  private let menu = NSMenu()
  private var timer: Timer?
  private var settingsWindow: SettingsWindowController?
  private let console = ConsoleWindowController()

  init(state: AppState) {
    self.state = state
  }

  func install() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    menu.autoenablesItems = false
    menu.delegate = self
    item.menu = menu
    statusItem = item
    observe()
    redraw()
    timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  func popMenu() {
    statusItem?.button?.performClick(nil)
  }

  /// Until the tool is found there is nothing to show, so the menu opens and says why.
  func showSettings() {
    guard state.tool == .ready, let runner = state.runner else { return popMenu() }
    if settingsWindow == nil { settingsWindow = SettingsWindowController(state: state, runner: runner) }
    settingsWindow?.show()
  }

  /// What Quit asks while something runs, nil when nothing does.
  var quitQuestion: (message: String, detail: String)? {
    if let session = console.running { return ("Stop \(session.title) and quit?", "Quitting stops the command.") }
    return state.busy.map { ("Quit while a command is running?", $0) }
  }

  func menuWillOpen(_ menu: NSMenu) {
    redraw()
    refresh()
  }

  private func refresh() {
    Task { await state.refresh() }
  }

  // Re-armed on every change, so a refresh that lands while the menu is open
  // rebuilds its items in place.
  private func observe() {
    withObservationTracking {
      _ = MenuBuilder.entries(for: state, launchAtLogin: false)
      _ = state.needsAttention
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.redraw()
        self?.observe()
      }
    }
  }

  private func redraw() {
    let symbol = state.needsAttention ? "desktopcomputer.trianglebadge.exclamationmark" : "desktopcomputer"
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Return of the Mac")
    image?.isTemplate = true
    statusItem?.button?.image = image
    menu.removeAllItems()
    for entry in MenuBuilder.entries(for: state, launchAtLogin: Self.loginItemOn) { menu.addItem(item(entry)) }
  }

  private func item(_ entry: MenuEntry) -> NSMenuItem {
    let item: NSMenuItem
    switch entry.kind {
    case .separator:
      return .separator()
    case .info:
      item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
    case .action(let id):
      item = NSMenuItem(title: entry.title, action: #selector(chose(_:)), keyEquivalent: id == "quit" ? "q" : "")
      item.representedObject = id
    case .toggle(let on, let id):
      item = NSMenuItem(title: entry.title, action: #selector(chose(_:)), keyEquivalent: "")
      item.state = on ? .on : .off
      item.representedObject = id
    case .submenu(let entries):
      item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
      let sub = NSMenu()
      sub.autoenablesItems = false
      entries.forEach { sub.addItem(self.item($0)) }
      item.submenu = sub
    }
    item.target = self
    item.isEnabled = entry.enabled
    return item
  }

  @objc private func chose(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if id.hasPrefix(MenuBuilder.profilePrefix) {
      let name = String(id.dropFirst(MenuBuilder.profilePrefix.count))
      if confirm("Switch to the profile \(name)?", "rotm settings profile use \(name)", "Switch") {
        Task { await state.useProfile(name) }
      }
      return
    }
    switch id {
    case "newProfile": newProfile()
    case "syncNow":
      if confirm("Sync your settings now?", "rotm settings sync now", "Sync") { Task { await state.syncNow() } }
    case "dismiss": state.dismissOutput()
    case "settings": showSettings()
    case "launchAtLogin": toggleLaunchAtLogin()
    case "quit": NSApp.terminate(nil)
    default:
      if let command = ConsoleCommand.named(id) { runConsole(command) }
    }
  }

  private func runConsole(_ command: ConsoleCommand) {
    guard !state.blocked, confirm(command.question, "\(command.commandLine) in a console window", command.button),
      !state.blocked
    else { return }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let session = ConsoleSession(
      title: command.title, command: command.command(home: home), environment: ConsoleCommand.environment(home: home),
      logDirectory: home.appendingPathComponent("Library/Logs/returnofthemac"))
    // The settings window reloads itself when sessionRunning clears (SettingsWindowController.watchActions).
    state.sessionRunning = true
    console.run(session) { [weak self] in
      guard let self else { return }
      self.state.sessionRunning = false
      Task { await self.state.refresh(recheckUpdates: true) }
    }
  }

  private func confirm(_ message: String, _ command: String, _ button: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = "This runs \(command)"
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func newProfile() {
    let alert = NSAlert()
    alert.messageText = "New profile"
    alert.informativeText = "Name it with lowercase letters, digits or hyphens. This runs rotm settings profile new <name>."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = field.stringValue.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    Task { await state.newProfile(name) }
  }

  // A login item waiting for approval reads as on, so a second click does not register it again.
  private static var loginItemOn: Bool {
    [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
  }

  private func toggleLaunchAtLogin() {
    do {
      if Self.loginItemOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
    } catch {
      let alert = NSAlert(error: error)
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
    }
    redraw()
  }
}
