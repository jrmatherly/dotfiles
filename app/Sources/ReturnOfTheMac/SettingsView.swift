import RotmCore
import SwiftUI

/// A sidebar of sections, the selected section's rows, and a bar holding the
/// staged changes and the last batch's notes and failures.
struct SettingsView: View {
  @Bindable var model: SettingsModel
  let state: AppState
  @State private var section: String?
  @State private var shared = false
  @State private var reviewing = false

  init(model: SettingsModel, state: AppState, section: String? = nil) {
    self.model = model
    self.state = state
    _section = State(initialValue: section)
  }

  private var profileActive: Bool { (state.status?.profile.active ?? "default") != "default" }
  private var writeShared: Bool { shared && profileActive }
  private var shown: String? { section.flatMap { model.sections.contains($0) ? $0 : nil } ?? model.sections.first }

  var body: some View {
    NavigationSplitView {
      List(model.sections, id: \.self, selection: Binding(get: { shown }, set: { section = $0 })) { Text($0) }
        .navigationSplitViewColumnWidth(min: 150, ideal: 180)
    } detail: {
      detail
    }
    .searchable(text: $model.search, placement: .sidebar, prompt: "Search settings")
    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    .sheet(isPresented: $reviewing) {
      ReviewSheet(edits: model.staged, blocked: state.blocked, apply: apply, cancel: { reviewing = false })
    }
    .onChange(of: writeShared) { restage() }
  }

  @ViewBuilder private var detail: some View {
    if model.rows.isEmpty && model.loading {
      ProgressView("Reading your settings…").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let shown {
      Form {
        Section(shown) {
          ForEach(model.rows(in: shown)) { SettingRowView(row: $0, model: model, shared: writeShared) }
        }
      }
      .formStyle(.grouped)
    } else {
      Text(model.search.isEmpty ? "No settings" : "No setting matches \"\(model.search)\"")
        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var bar: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !model.notes.isEmpty || !model.failures.isEmpty {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(model.failures, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            ForEach(model.notes, id: \.self) { Label($0, systemImage: "info.circle") }
          }
          .textSelection(.enabled)
          Spacer()
          Button("Dismiss") { model.dismissResults() }
        }
        Divider()
      }
      HStack {
        if profileActive {
          Toggle("Write to shared settings", isOn: $shared)
            .help("With a profile active, change the shared settings instead of the profile's")
        }
        if model.loading && !model.rows.isEmpty { ProgressView().controlSize(.small).accessibilityLabel("Reloading") }
        Spacer()
        Text(changes).foregroundStyle(.secondary)
        Button("Review…") { reviewing = true }
          .keyboardShortcut(.defaultAction)
          .disabled(model.staged.isEmpty || state.blocked)
      }
    }
    .padding(10)
    .background(.bar)
  }

  private var changes: String {
    switch model.staged.count {
    case 0: return "No changes"
    case 1: return "1 change"
    case let n: return "\(n) changes"
    }
  }

  private func apply() {
    reviewing = false
    Task { await state.exclusive("Applying settings…") { await model.applyStaged() } }
  }

  // The checkbox covers every staged edit, not only the ones made after it changed.
  private func restage() {
    for edit in model.staged {
      switch edit.change {
      case .set(let value): model.stage(edit.settingId, value: value, shared: writeShared)
      case .reset: model.stageReset(edit.settingId, shared: writeShared)
      }
    }
  }
}
