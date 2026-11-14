import RotmCore
import Testing

private let esc = "\u{1B}"

private func run(_ text: String, _ foreground: ConsoleColor? = nil, bold: Bool = false) -> StyledRun {
  StyledRun(text: text, style: TextStyle(foreground: foreground, bold: bold))
}

struct AnsiParserTests {
  @Test func colourAndBoldComeFromSGR() {
    var parser = AnsiParser()
    let runs = parser.parse("a\(esc)[1mb\(esc)[32mc\(esc)[22md\(esc)[0;33me\(esc)[39mf\(esc)[1;31mg\(esc)[mh")
    #expect(
      runs == [
        run("a"), run("b", bold: true), run("c", .basic(2), bold: true), run("d", .basic(2)), run("e", .basic(3)), run("f"),
        run("g", .basic(1), bold: true), run("h"),
      ])
  }

  @Test func brightAnd24BitForegrounds() {
    var parser = AnsiParser()
    let runs = parser.parse("\(esc)[91mx\(esc)[38;2;214;40;40m█\(esc)[38;2;300;0;0my")
    #expect(runs == [run("x", .basic(9)), run("█", .rgb(214, 40, 40)), run("y", .rgb(255, 0, 0))])
  }

  @Test(arguments: [
    (1, ConsoleColor.basic(1)), (15, .basic(15)), (16, .rgb(0, 0, 0)), (196, .rgb(255, 0, 0)), (110, .rgb(135, 175, 215)),
    (232, .rgb(8, 8, 8)), (255, .rgb(238, 238, 238)),
  ])
  func the256ColourFormMapsToBasicOrRGB(index: Int, color: ConsoleColor) {
    var parser = AnsiParser()
    #expect(parser.parse("\(esc)[38;5;\(index)mx") == [run("x", color)])
  }

  @Test func backgroundColoursAreIgnoredWithTheirNumbers() {
    var parser = AnsiParser()
    // Misread as separate codes, 48;2;1;2;3 would turn bold on and 48;5;31 would turn red.
    #expect(parser.parse("\(esc)[48;2;1;2;3ma\(esc)[48;5;31mb\(esc)[44;49;100;4mc") == [run("abc")])
    #expect(parser.parse("\(esc)[48;5;1;31mx") == [run("x", .basic(1))])
  }

  @Test func otherSequencesAreStripped() {
    var parser = AnsiParser()
    let runs = parser.parse("\(esc)[2Ka\(esc)]0;title\u{07}b\(esc)(Bc\u{07}\(esc)[?25ld\(esc)=e")
    #expect(runs == [run("abcde")])
  }

  @Test func theStyleCarriesFromOneCallToTheNext() {
    var parser = AnsiParser()
    #expect(parser.parse("\(esc)[1;31m") == [])
    #expect(parser.style == TextStyle(foreground: .basic(1), bold: true))
    #expect(parser.parse("x") == [run("x", .basic(1), bold: true)])
  }
}
