import RotmCore
import SwiftUI

/// The staged edits as the commands Apply will run, one per line, in order.
struct ReviewSheet: View {
  let edits: [Edit]
  let blocked: Bool
  let apply: () -> Void
  let cancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(edits.count == 1 ? "Apply 1 change?" : "Apply \(edits.count) changes?").font(.headline)
      Text("Apply runs these commands in order:").foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(edits.enumerated()), id: \.offset) { _, edit in
            Text(edit.commandLine).font(.body.monospaced()).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(8)
      }
      .frame(minHeight: 80, maxHeight: 260)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
      if blocked { Text("Another command is running. Apply when it finishes.").foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        Button("Apply", action: apply).keyboardShortcut(.defaultAction).disabled(blocked || edits.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 560)
  }
}
