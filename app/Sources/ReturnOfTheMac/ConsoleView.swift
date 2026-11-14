import AppKit
import RotmCore
import SwiftUI

/// A command's output, an input line that hides typing at a password prompt,
/// and Stop. The input line is always there: a prompt the app has no rule
/// for still gets its answer.
struct ConsoleView: View {
  let session: ConsoleSession
  let close: () -> Void
  @State private var input = ""
  // Its own buffer, so a prompt that stops matching never shows a typed password in the plain field.
  @State private var secret = ""
  @FocusState private var focused: Bool

  private var running: Bool { session.phase == .running }

  var body: some View {
    VStack(spacing: 0) {
      ConsoleText(runs: session.runs, title: session.title)
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          field
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(send)
            .disabled(!running)
          Button("Send", action: send).disabled(!running)
        }
        HStack {
          Text(status).foregroundStyle(.secondary)
          Spacer()
          Button("Show Log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.logURL]) }
          if running {
            Button("Stop") { session.stop() }
          } else {
            Button("Close", action: close).keyboardShortcut(.cancelAction)
          }
        }
      }
      .padding(12)
    }
    .frame(minWidth: 520, minHeight: 320)
    .onAppear { focused = true }
    .onChange(of: session.wantsSecret) {
      secret = ""
      focused = true
    }
  }

  @ViewBuilder private var field: some View {
    if session.wantsSecret {
      SecureField("Password", text: $secret).accessibilityLabel("Password")
    } else {
      TextField("Type an answer and press Return", text: $input).accessibilityLabel("Answer")
    }
  }

  private var status: String {
    switch session.phase {
    case .running: return session.wantsSecret ? "Waiting for your password. What you type is hidden." : "Running…"
    case .finished(0): return "Finished."
    case .finished(let code): return "Ended with exit code \(code)."
    case .stopped: return "Stopped."
    }
  }

  private func send() {
    session.send(session.wantsSecret ? secret : input)
    input = ""
    secret = ""
  }
}

/// A read-only monospaced text view, in the colours the command sent, that
/// keeps following the output while the user has not scrolled up.
private struct ConsoleText: NSViewRepresentable {
  let runs: [StyledRun]
  let title: String

  final class Coordinator { var shown: [StyledRun] = [] }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let view = scroll.documentView as! NSTextView
    view.isEditable = false
    view.isSelectable = true
    view.textContainerInset = NSSize(width: 8, height: 8)
    view.setAccessibilityLabel("Output of \(title)")
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
    view.setAccessibilityLabel("Output of \(title)")
    let shown = context.coordinator.shown
    guard shown != runs else { return }
    let following = scroll.documentVisibleRect.maxY >= view.bounds.maxY - 24
    // New output only grows the last run shown or adds runs after it.
    if let last = shown.indices.last, runs.count > last, runs[..<last] == shown[..<last],
      runs[last].style == shown[last].style, runs[last].text.hasPrefix(shown[last].text)
    {
      let tail = (runs[last].text as NSString).substring(from: (shown[last].text as NSString).length)
      let added = NSMutableAttributedString(string: tail, attributes: Self.attributes(runs[last].style))
      for run in runs[(last + 1)...] { added.append(NSAttributedString(string: run.text, attributes: Self.attributes(run.style))) }
      storage.append(added)
    } else {
      let all = NSMutableAttributedString()
      for run in runs { all.append(NSAttributedString(string: run.text, attributes: Self.attributes(run.style))) }
      storage.setAttributedString(all)
    }
    context.coordinator.shown = runs
    if following { view.scrollToEndOfDocument(nil) }
  }

  private static let regular = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular)
  private static let bold = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .bold)

  /// Black, white and the default are the label colour, so they read on either background.
  private static let palette: [NSColor] = [
    .labelColor, .systemRed, .systemGreen, yellow, .systemBlue, .systemPurple, .systemCyan, .labelColor,
    .secondaryLabelColor, .systemRed, .systemGreen, yellow, .systemBlue, .systemPink, .systemTeal, .labelColor,
  ]

  /// System yellow is barely visible on a white background.
  private static let yellow = NSColor(name: nil) {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? .systemYellow : NSColor(srgbRed: 0.6, green: 0.45, blue: 0, alpha: 1)
  }

  private static func attributes(_ style: TextStyle) -> [NSAttributedString.Key: Any] {
    let color: NSColor
    switch style.foreground {
    case nil: color = .textColor
    case .basic(let n): color = palette[n]
    case .rgb(let r, let g, let b):
      color = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    return [.font: style.bold ? bold : regular, .foregroundColor: color]
  }
}
