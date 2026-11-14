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
      ConsoleText(text: session.text, title: session.title)
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

/// A read-only monospaced text view that keeps following the output while
/// the user has not scrolled up.
private struct ConsoleText: NSViewRepresentable {
  let text: String
  let title: String

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let view = scroll.documentView as! NSTextView
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = false
    view.textContainerInset = NSSize(width: 8, height: 8)
    view.setAccessibilityLabel("Output of \(title)")
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
    view.setAccessibilityLabel("Output of \(title)")
    let shown = storage.string
    guard shown != text else { return }
    let following = scroll.documentVisibleRect.maxY >= view.bounds.maxY - 24
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular),
      .foregroundColor: NSColor.textColor,
    ]
    if !shown.isEmpty, text.hasPrefix(shown) {
      storage.append(NSAttributedString(string: (text as NSString).substring(from: storage.length), attributes: attributes))
    } else {
      storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
    if following { view.scrollToEndOfDocument(nil) }
  }
}
