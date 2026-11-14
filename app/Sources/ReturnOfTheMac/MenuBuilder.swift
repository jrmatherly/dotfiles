import RotmCore

struct MenuEntry: Equatable {
  enum Kind: Equatable { case info, action(String), toggle(Bool, String), separator, submenu([MenuEntry]) }
  let title: String
  let kind: Kind
  let enabled: Bool
}

extension MenuEntry {
  static let separator = MenuEntry(title: "", kind: .separator, enabled: true)
  static func info(_ title: String) -> MenuEntry { MenuEntry(title: title, kind: .info, enabled: true) }
  static func action(_ title: String, _ id: String, enabled: Bool = true) -> MenuEntry {
    MenuEntry(title: title, kind: .action(id), enabled: enabled)
  }
}

/// The whole menu as data, so tests compare it and the controller only draws it.
/// The entries whose commands later tasks add (the console) are listed now
/// and stay disabled until those land.
@MainActor enum MenuBuilder {
  static let profilePrefix = "useProfile:"

  static func entries(for state: AppState, launchAtLogin: Bool) -> [MenuEntry] {
    let quit = MenuEntry.action("Quit", "quit")
    guard state.tool == .ready, let status = state.status else {
      return [.info(toolMessage(state.tool)), .separator, .action("Settings…", "settings", enabled: false), quit]
    }
    let open = !state.blocked
    let settings = MenuEntry.action("Settings…", "settings", enabled: open)
    var menu: [MenuEntry] = []
    if let version = state.appUpdate {
      menu += [.action("Update Return of the Mac to \(version)…", "appUpdate", enabled: false), .separator]
    }
    if let text = state.lastError ?? state.lastOutput {
      menu += [.info(text), .action("Dismiss", "dismiss", enabled: open), .separator]
    }

    let profile = status.profile
    var profileTitle = "Profile: \(profile.active)"
    if let missing = profile.missing { profileTitle += ", \"\(missing)\" is missing" }
    let rows = (["default"] + profile.names).map { name in
      MenuEntry(title: name, kind: .toggle(name == profile.active, profilePrefix + name), enabled: open && name != profile.active)
    }
    menu += [
      MenuEntry(title: profileTitle, kind: .submenu(rows + [.separator, .action("New Profile…", "newProfile", enabled: open)]), enabled: true),
      .separator,
    ]

    let sync = status.sync
    if sync.connected {
      var title = "Sync: on"
      if !sync.waiting.isEmpty { title += ", \(count(sync.waiting.count, "change")) waiting" }
      if sync.conflicts != nil { title += ", a conflict to settle" }
      menu += [.info(title), .action("Sync Now", "syncNow", enabled: open)]
    } else {
      menu += [.info("Sync: off"), .action("Turn On Sync…", "turnOnSync", enabled: false)]
    }

    menu += [.separator, .info(setupLine(status: status, check: state.updateCheck)), .action("Update…", "update", enabled: false), .separator]
    menu.append(
      MenuEntry(
        title: "More",
        kind: .submenu([
          .action("Run Setup Again…", "runSetup", enabled: false),
          .action("Apply macOS Preferences…", "applyMacOS", enabled: false),
          .separator,
          MenuEntry(title: "Launch at Login", kind: .toggle(launchAtLogin, "launchAtLogin"), enabled: true),
        ]),
        enabled: true))
    return menu + [settings, .separator, quit]
  }

  private static func toolMessage(_ tool: AppState.Tool) -> String {
    switch tool {
    case .checking, .ready: return "Checking returnofthemac…"
    case .missing(let message), .broken(let message): return message
    }
  }

  private static func setupLine(status: Status, check: UpdateCheck?) -> String {
    if (check?.mode ?? status.mode) == "clone" { return "Setup: development clone" }
    switch check?.behind {
    case nil: return "Setup: not checked yet"
    case 0: return "Setup: up to date"
    case let n?: return "Setup: \(count(n, "update")) waiting"
    }
  }

  private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
