import AppKit
import Observation
import RotmCore
import SwiftUI

/// The one console window, reused by every session.
@MainActor
final class ConsoleWindowController: NSObject, NSWindowDelegate {
  let window: NSWindow
  private(set) var session: ConsoleSession?

  var running: ConsoleSession? { session?.phase == .running ? session : nil }

  override init() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    super.init()
    window.delegate = self
  }

  /// Shows `session`, starts it, and calls `ended` once it has finished or stopped.
  func run(_ session: ConsoleSession, ended: @escaping () -> Void) {
    self.session = session
    window.title = session.title
    window.contentViewController = NSHostingController(
      rootView: ConsoleView(session: session, close: { [weak self] in self?.window.close() }))
    if !window.isVisible {
      window.setContentSize(NSSize(width: 720, height: 480))
      window.center()
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    session.start()
    Self.watch(session, ended)
  }

  private static func watch(_ session: ConsoleSession, _ ended: @escaping () -> Void) {
    guard session.phase == .running else { return ended() }
    withObservationTracking {
      _ = session.phase
    } onChange: {
      Task { @MainActor in watch(session, ended) }
    }
  }

  // Without its window the user could neither answer the command nor stop it.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let session = running else { return true }
    let alert = NSAlert()
    alert.messageText = "Stop \(session.title)?"
    alert.informativeText = "Closing this window stops the command."
    alert.addButton(withTitle: "Stop")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    session.stop()
    return true
  }
}
