import RotmCore
import RotmTestSupport
import Testing

@Test func rowsDecodeFromTheListFixture() throws {
  let rows = try Decode.rows(Fixtures.list)
  #expect(rows.count == 9)
  #expect(rows[0].settingId == "setup.skip_codegraph")
  #expect(rows[0].id == rows[0].settingId)
  #expect(rows[1].choices == ["genie", "scale", "suck"])
  let seats = try #require(rows.first { $0.settingId == "jstack.feature_refactoring" })
  #expect(!seats.seatModels.isEmpty)
  #expect(!seats.seatEfforts.isEmpty)
  #expect(!seats.seatList)
  let list = try #require(rows.first { $0.settingId == "jstack.arena_runners" })
  #expect(list.seatList)
  #expect(rows[0].seed == nil)
  #expect(rows.first { $0.settingId == "apps.obsidian_vault" }?.drift == true)
}

@Test func statusDecodesFromTheStatusFixture() throws {
  let status = try Decode.status(Fixtures.status)
  #expect(status.mode == "clone")
  #expect(status.branch == "main")
  #expect(status.profile.active == "default")
  #expect(status.profile.names == ["work"])
  #expect(status.profile.missing == nil)
  #expect(!status.profile.miseEnv)
  #expect(!status.sync.connected)
  #expect(status.sync.conflicts == nil)
}

@Test func updateCheckDecodesFromItsFixture() throws {
  let check = try Decode.updateCheck(Fixtures.updateCheck)
  #expect(check.behind == 2)
  #expect(check.mode == "installed")
  #expect(try Decode.updateCheck(#"{"mode":"clone","branch":"main","behind":null}"#).behind == nil)
}

@Test func badJSONThrowsBadJSON() {
  #expect(throws: CommandError.badJSON("nope")) { try Decode.rows("nope") }
  #expect(throws: CommandError.badJSON("{}")) { try Decode.status("{}") }
  let long = String(repeating: "x", count: 500)
  #expect(throws: CommandError.badJSON(String(long.prefix(200)))) { try Decode.updateCheck(long) }
}
