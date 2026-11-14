import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static var delegate: AppDelegate?
  private var statusItem: NSStatusItem?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    Self.delegate = delegate
    app.delegate = delegate
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  }
}
