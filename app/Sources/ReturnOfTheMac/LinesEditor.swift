import RotmCore
import SwiftUI

/// A list setting: one text field per entry, with add and remove.
struct LinesEditor: View {
  let row: SettingRow
  let value: String
  let stage: (String) -> Void
  // Held here so a new, still blank entry stays on screen; the value drops blank lines.
  @State private var entries: [String] = []

  var body: some View {
    VStack(alignment: .trailing, spacing: 6) {
      ForEach(entries.indices, id: \.self) { n in
        HStack(spacing: 6) {
          TextField("Entry \(n + 1)", text: Binding(get: { entries[safe: n] }, set: { edit(n, $0) }))
            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
            .accessibilityLabel("\(row.label), entry \(n + 1)")
          Button {
            entries.remove(at: n)
            stage(Lines.format(entries))
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .help("Remove this entry")
          .accessibilityLabel("Remove entry \(n + 1) from \(row.label)")
        }
      }
      Button("Add Entry") { entries.append("") }
        .controlSize(.small)
        .accessibilityLabel("Add an entry to \(row.label)")
    }
    .onAppear { entries = Lines.parse(value) }
    .onChange(of: value) { if Lines.format(entries) != value { entries = Lines.parse(value) } }
  }

  private func edit(_ n: Int, _ text: String) {
    guard entries.indices.contains(n) else { return }
    entries[n] = text
    stage(Lines.format(entries))
  }
}

extension Array where Element == String {
  fileprivate subscript(safe n: Int) -> String { indices.contains(n) ? self[n] : "" }
}
