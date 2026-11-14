import RotmCore
import Testing

struct SeatsTests {
  @Test func threeSeats() {
    #expect(
      Seats.parse("fable medium, opus medium, opus medium") == [
        Seat(model: "fable", effort: "medium"), Seat(model: "opus", effort: "medium"), Seat(model: "opus", effort: "medium"),
      ])
  }

  @Test(arguments: ["fable medium, opus medium, opus medium", "inherit", "codex", "sonnet medium", "claude-fable-5-2 medium"])
  func formatUndoesParse(_ value: String) {
    #expect(Seats.format(Seats.parse(value)) == value)
  }

  @Test func anEmptyValueIsOneEmptySeat() {
    #expect(Seats.parse("") == [Seat(model: "", effort: "")])
    #expect(Seats.format(Seats.parse("")) == "")
  }

  @Test func aSeatWithNoModelIsDropped() {
    #expect(Seats.format([Seat(model: "opus", effort: "high"), Seat(model: "", effort: "medium")]) == "opus high")
  }

  @Test func switchingModelKeepsOrClearsTheEffort() {
    let seat = Seat(model: "opus", effort: "high")
    #expect(seat.with(model: "inherit") == Seat(model: "inherit", effort: ""))
    #expect(seat.with(model: "sonnet") == Seat(model: "sonnet", effort: "high"))
    #expect(Seat(model: "codex", effort: "").with(model: "opus") == Seat(model: "opus", effort: "medium"))
  }

  @Test func linesAreTrimmedAndBlankOnesDropped() {
    #expect(Lines.parse("~/dev\n~/src") == ["~/dev", "~/src"])
    #expect(Lines.format(["  ~/dev ", "", "   ", "~/src"]) == "~/dev\n~/src")
    #expect(Lines.parse("") == [])
  }
}
