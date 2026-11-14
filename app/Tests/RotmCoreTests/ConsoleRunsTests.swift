import Foundation
import RotmTestSupport
import Testing

@testable import RotmCore

private let esc = "\u{1B}"
private let red = TextStyle(foreground: .basic(1))
private let green = TextStyle(foreground: .basic(2))

/// A session that is never started, fed output directly.
@MainActor
private func session() -> ConsoleSession {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotm-runs-tests-\(UUID().uuidString)")
  return ConsoleSession(title: "Test", command: ["/usr/bin/false"], environment: [:], logDirectory: dir)
}

@MainActor
private func fed(_ chunks: [Data]) -> ConsoleSession {
  let s = session()
  chunks.forEach(s.receive)
  return s
}

@MainActor
private func fed(_ chunks: String...) -> ConsoleSession { fed(chunks.map { Data($0.utf8) }) }

private func chunks(_ data: Data, of size: Int) -> [Data] {
  stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
}

/// The runs spell the text, with no empty run and no two neighbours in the same style.
@MainActor
private func expectConsistent(_ s: ConsoleSession, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(s.runs.map(\.text).joined() == s.text, sourceLocation: sourceLocation)
  #expect(s.runs.map(\.text).joined().unicodeScalars.elementsEqual(s.text.unicodeScalars), sourceLocation: sourceLocation)
  #expect(!s.runs.contains { $0.text.isEmpty }, sourceLocation: sourceLocation)
  #expect(!zip(s.runs, s.runs.dropFirst()).contains { $0.style == $1.style }, sourceLocation: sourceLocation)
}

@MainActor
struct ConsoleRunsTests {
  @Test(arguments: [1, 2, 3, 7, 64, 1000, Int.max])
  func theProbeOutputKeepsItsColoursAtEveryChunkSize(size: Int) {
    let whole = fed([Fixtures.updateConsole])
    let s = fed(chunks(Fixtures.updateConsole, of: min(size, Fixtures.updateConsole.count)))
    expectConsistent(s)
    #expect(s.text == whole.text)
    #expect(s.runs == whole.runs)
    #expect(!s.text.contains(esc))
    let maskRed = TextStyle(foreground: .rgb(214, 40, 40), bold: true)
    let redBlocks = s.runs.filter { $0.style == maskRed && $0.text.contains("█") }
    #expect(redBlocks.count >= 10, "the mask's red rows")
    #expect(s.runs.contains { $0.style.foreground == .rgb(20, 20, 20) && $0.text.contains("█") })
    #expect(s.runs.contains { $0.style == green && $0.text == "✔" })
    #expect(s.runs.contains { $0.style == TextStyle(foreground: .basic(3)) && $0.text == "!" })
  }

  @Test func aBareReturnStartsTheLineOverAcrossRuns() {
    let s = fed("keep\n\(esc)[31mab\(esc)[32mcd\re\n")
    expectConsistent(s)
    #expect(s.text == "keep\ne\n")
    #expect(s.runs == [StyledRun(text: "keep\n", style: TextStyle()), StyledRun(text: "e\n", style: green)])

    let first = fed("\(esc)[31mred\(esc)[0m plain\r\(esc)[32mgreen\n")
    expectConsistent(first)
    #expect(first.runs == [StyledRun(text: "green\n", style: green)])
  }

  @Test func aReturnAtTheEndOfAWriteWaitsForTheNext() {
    let s = fed("x\(esc)[31my\r", "z")
    expectConsistent(s)
    #expect(s.runs == [StyledRun(text: "z", style: red)])

    let newline = fed("\(esc)[31mdone\r", "\n\(esc)[32mnext")
    expectConsistent(newline)
    #expect(newline.runs == [StyledRun(text: "done\n", style: red), StyledRun(text: "next", style: green)])
  }

  @Test func anEscapeOrCharacterSplitAcrossWritesKeepsItsStyle() {
    let s = fed([Data("\(esc)[3".utf8), Data("1mr\u{C3}".utf8.dropLast()), Data([0xA9]) + Data("\(esc)[".utf8), Data("0mx".utf8)])
    expectConsistent(s)
    #expect(s.runs == [StyledRun(text: "ré", style: red), StyledRun(text: "x", style: TextStyle())])
  }

  @Test func theCapDropsTheOldestCharactersFromTheRunsToo() {
    let line = "\(esc)[31m0123456789\(esc)[32mabcdefghij\(esc)[0m\n"
    let s = fed([String](repeating: String(repeating: line, count: 500), count: 25).map { Data($0.utf8) })
    expectConsistent(s)
    #expect(s.text.count == ConsoleSession.cap)
    #expect(s.text.hasSuffix("0123456789abcdefghij\n"))
    // 200,000 characters are 9,523 lines of 21 and the last 17 of the line before, which starts at its 4.
    #expect(Array(s.runs.prefix(3)) == [
      StyledRun(text: "456789", style: red), StyledRun(text: "abcdefghij", style: green), StyledRun(text: "\n", style: TextStyle()),
    ])
    #expect(s.runs.count == 3 * 9_524)
  }
}
