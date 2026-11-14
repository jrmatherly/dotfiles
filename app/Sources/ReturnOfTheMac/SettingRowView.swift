import RotmCore
import SwiftUI

/// One setting: its label and help, a control by type, and badges for an
/// override, a staged change and a read-only row.
struct SettingRowView: View {
  let row: SettingRow
  let model: SettingsModel
  let shared: Bool

  private var pending: Edit.Change? { model.staged.first { $0.settingId == row.settingId }?.change }
  private var readOnly: Bool { row.access == "ro" }

  private var text: Binding<String> {
    Binding(
      get: {
        if case .set(let value) = pending { return value }
        return row.value ?? ""
      },
      set: { model.stage(row.settingId, value: $0, shared: shared) })
  }

  var body: some View {
    Group {
      if row.widget.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          labels
          Spacer(minLength: 16)
          control.disabled(readOnly)
          actions
        }
      } else {
        // A compound editor sits under its label, so its width never squeezes the label.
        VStack(alignment: .trailing, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            labels
            Spacer(minLength: 16)
            actions
          }
          control.disabled(readOnly)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var labels: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(row.label)
        if readOnly {
          Image(systemName: "lock.fill")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Read-only")
            .help("Read-only")
        }
        if row.source == "override" { badge("Override", "Changed from the default") }
        if pending == .reset { badge("Reset staged", "Goes back to the default when applied") } else if pending != nil {
          badge("Changed", "Not applied yet")
        }
      }
      if !row.help.isEmpty {
        Text(row.help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder private var actions: some View {
    if pending != nil {
      Button("Undo") { model.unstage(row.settingId) }
        .accessibilityLabel("Undo the change to \(row.label)")
    } else if row.source == "override" && !readOnly {
      Button("Reset") { model.stageReset(row.settingId, shared: shared) }
        .accessibilityLabel("Reset \(row.label)")
    }
  }

  @ViewBuilder private var control: some View {
    // The compound editors label each of their own controls.
    switch row.widget {
    case "seats": SeatsEditor(row: row, value: text.wrappedValue, stage: { text.wrappedValue = $0 })
    case "lines": LinesEditor(row: row, value: text.wrappedValue, stage: { text.wrappedValue = $0 })
    default: simple.accessibilityLabel(row.label)
    }
  }

  @ViewBuilder private var simple: some View {
    switch row.type {
    case _ where !row.widget.isEmpty:
      // A widget this app has no editor for yet shows its value read-only.
      Text(row.value ?? "").font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        .frame(maxWidth: 280, alignment: .trailing)
    case "bool":
      Toggle(row.label, isOn: Binding(get: { SettingsModel.isOn(text.wrappedValue) }, set: { text.wrappedValue = $0 ? "on" : "off" }))
        .toggleStyle(.switch).labelsHidden()
    case "enum":
      Picker(row.label, selection: text) {
        ForEach(row.choices, id: \.self) { Text($0).tag($0) }
      }
      .labelsHidden().fixedSize()
    case "int":
      TextField(row.label, text: text).labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80)
    default:
      TextField(row.label, text: text).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
    }
  }

  private func badge(_ title: String, _ help: String) -> some View {
    Text(title)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(.quaternary, in: Capsule())
      .help(help)
      .accessibilityLabel("\(title): \(help)")
  }
}
