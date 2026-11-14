import RotmCore
import SwiftUI

/// A jstack role's seats: a model and an effort picker per seat, and add and
/// remove buttons for the roles that take a list.
struct SeatsEditor: View {
  let row: SettingRow
  let value: String
  let stage: (String) -> Void

  private var seats: [Seat] { Seats.parse(value) }

  var body: some View {
    VStack(alignment: .trailing, spacing: 6) {
      // A grid, so seats with model names of different lengths line up.
      Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(Array(seats.enumerated()), id: \.offset) { n, seat in
          GridRow {
            if row.seatList { Text("\(n + 1).").foregroundStyle(.secondary).monospacedDigit().fixedSize() }
            Picker("Model", selection: Binding(get: { seat.model }, set: { replace(n, seat.with(model: $0)) })) {
              if seat.model.isEmpty { Text("unset").tag("") }
              ForEach(models(seat), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().fixedSize()
            .gridColumnAlignment(.leading)
            .accessibilityLabel(label("model", n))
            if Seats.noEffort.contains(seat.model) {
              Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            } else {
              Picker("Effort", selection: Binding(get: { effort(seat) }, set: { replace(n, Seat(model: seat.model, effort: $0)) })) {
                ForEach(efforts(seat), id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden().fixedSize()
              .accessibilityLabel(label("effort", n))
            }
          }
        }
      }
      if row.seatList {
        HStack(spacing: 6) {
          Button("Remove Seat") { stage(Seats.format(Array(seats.dropLast()))) }
            .disabled(seats.count < 2)
            .accessibilityLabel("Remove the last seat from \(row.label)")
          Button("Add Seat") { stage(Seats.format(seats + [Seat(model: "opus", effort: "medium")])) }
            .accessibilityLabel("Add a seat to \(row.label)")
        }
        .controlSize(.small)
      }
    }
  }

  // A full model id written in a terminal stays selectable, so opening the row never changes it.
  private func models(_ seat: Seat) -> [String] {
    seat.model.isEmpty || row.seatModels.contains(seat.model) ? row.seatModels : row.seatModels + [seat.model]
  }

  private func effort(_ seat: Seat) -> String { seat.effort.isEmpty ? "medium" : seat.effort }

  private func efforts(_ seat: Seat) -> [String] {
    row.seatEfforts.contains(effort(seat)) ? row.seatEfforts : row.seatEfforts + [effort(seat)]
  }

  private func replace(_ n: Int, _ seat: Seat) {
    var next = seats
    next[n] = seat
    stage(Seats.format(next))
  }

  private func label(_ what: String, _ n: Int) -> String {
    row.seatList ? "\(row.label), seat \(n + 1) \(what)" : "\(row.label) \(what)"
  }
}
