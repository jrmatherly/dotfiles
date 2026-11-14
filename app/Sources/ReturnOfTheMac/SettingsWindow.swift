import AppKit
import Observation
import RotmCore
import SwiftUI

/// One settings window, kept alive across closes. It reloads the settings
/// whenever it becomes key and whenever a menu action or console session ends.
@MainActor
final class SettingsWindowController {
  let window: NSWindow
  let model: SettingsModel
  private let state: AppState

  init(state: AppState, runner: CommandRunner, section: String? = nil) {
    self.state = state
    model = SettingsModel(runner: runner)
    let hosting = NSHostingController(rootView: SettingsView(model: model, state: state, section: section))
    window = NSWindow(contentViewController: hosting)
    window.title = "Return of the Mac Settings"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 860, height: 580))
    window.isReleasedWhenClosed = false
    NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.reload() }
    }
    watchActions()
  }

  func show() {
    if !window.isVisible { window.center() }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    // A text field would otherwise take focus and select its text on open.
    window.makeFirstResponder(nil)
  }

  /// The console (Task 5) can call this when a session ends; `watchActions`
  /// already covers it through `AppState.sessionRunning`.
  func reload() {
    guard window.isVisible else { return }
    Task { await model.load() }
  }

  private func watchActions() {
    let wasBlocked = state.blocked
    withObservationTracking {
      _ = state.blocked
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        if wasBlocked && !self.state.blocked { self.reload() }
        self.watchActions()
      }
    }
  }
}
