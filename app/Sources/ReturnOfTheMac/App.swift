import AppKit
import RotmCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static var delegate: AppDelegate?
  private var statusItem: StatusItemController?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    Self.delegate = delegate
    app.delegate = delegate
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let state = AppState(
      makeRunner: { CLI(tool: $0, home: home) },
      locate: { CLI.locate(override: nil, home: home) })
    MainMenu.install()
    let controller = StatusItemController(state: state)
    controller.install()
    statusItem = controller
  }

  // A command under `script` dies with the app, so quitting mid-run stops it.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let question = statusItem?.quitQuestion else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = question.message
    alert.informativeText = question.detail
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  // A second launch that showed nothing would read as a failed one.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    statusItem?.showSettings()
    return false
  }
}
