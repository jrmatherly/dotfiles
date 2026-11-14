import Foundation
import RotmCore
import RotmTestSupport
import Testing

let listArgs = ["settings", "list", "--json"]

private func ok(_ stdout: String = "", _ stderr: String = "") -> Result<CommandOutput, CommandError> {
  .success(CommandOutput(stdout: stdout, stderr: stderr))
}

@MainActor
private func loaded(_ list: String = Fixtures.list) async -> (SettingsModel, FakeRunner) {
  let runner = FakeRunner()
  runner.stub(listArgs, ok(list))
  let model = SettingsModel(runner: runner)
  await model.load()
  return (model, runner)
}

@MainActor
struct SettingsModelTests {
  @Test func loadFillsTheRows() async throws {
    let (model, runner) = await loaded()
    #expect(model.rows == (try Decode.rows(Fixtures.list)))
    #expect(model.loading == false)
    #expect(runner.calls == [listArgs])
  }

  @Test func stagingTheCurrentValueAgainRemovesTheEdit() async {
    let (model, _) = await loaded()
    model.stage("updates.slow_step_seconds", value: "20", shared: false)
    #expect(model.staged == [Edit(settingId: "updates.slow_step_seconds", change: .set("20"), shared: false)])
    model.stage("updates.slow_step_seconds", value: "10", shared: false)
    #expect(model.staged.isEmpty)
  }

  @Test func aBoolIsComparedByItsMeaning() async {
    let (model, _) = await loaded()
    model.stage("setup.skip_codegraph", value: "on", shared: false)
    #expect(model.staged.isEmpty)
    model.stage("setup.skip_codegraph", value: "off", shared: false)
    #expect(model.staged.map(\.change) == [.set("off")])
  }

  @Test func restagingKeepsTheEditsPlace() async {
    let (model, _) = await loaded()
    model.stage("updates.slow_step_seconds", value: "20", shared: false)
    model.stage("apps.obsidian_vault", value: "/tmp/v", shared: false)
    model.stage("updates.slow_step_seconds", value: "30", shared: true)
    #expect(
      model.staged == [
        Edit(settingId: "updates.slow_step_seconds", change: .set("30"), shared: true),
        Edit(settingId: "apps.obsidian_vault", change: .set("/tmp/v"), shared: false),
      ])
    model.unstage("updates.slow_step_seconds")
    #expect(model.staged.map(\.settingId) == ["apps.obsidian_vault"])
  }

  @Test func argumentsPassAValueByteForByte() {
    let value = "-a \"b\" #c"
    #expect(Edit(settingId: "t.text", change: .set(value), shared: false).arguments == ["settings", "set", "t.text", "--", value])
    #expect(Edit(settingId: "t.flag", change: .set("on"), shared: true).arguments == ["settings", "set", "--shared", "t.flag", "--", "on"])
    #expect(Edit(settingId: "t.flag", change: .reset, shared: false).arguments == ["settings", "reset", "t.flag"])
    #expect(Edit(settingId: "t.flag", change: .reset, shared: true).arguments == ["settings", "reset", "--shared", "t.flag"])
  }

  @Test func theCommandLineQuotesWhatAShellWouldEat() {
    #expect(Edit(settingId: "t.text", change: .set("-a 'b' #c"), shared: false).commandLine == #"rotm settings set t.text -- '-a '\''b'\'' #c'"#)
    #expect(Edit(settingId: "t.flag", change: .set("on"), shared: true).commandLine == "rotm settings set --shared t.flag -- on")
    #expect(Edit(settingId: "t.text", change: .set(""), shared: false).commandLine == "rotm settings set t.text -- ''")
    // zsh expands a leading = to a path: =ls is /bin/ls.
    #expect(Edit(settingId: "t.text", change: .set("=ls"), shared: false).commandLine == "rotm settings set t.text -- '=ls'")
    #expect(Edit(settingId: "t.text", change: .set("a=b"), shared: false).commandLine == "rotm settings set t.text -- a=b")
  }

  @Test func applyRunsEveryEditPastAFailureThenReloads() async {
    let (model, runner) = await loaded()
    model.stage("setup.skip_codegraph", value: "off", shared: false)
    model.stage("updates.slow_step_seconds", value: "20", shared: false)
    model.stage("apps.obsidian_vault", value: "/tmp/v", shared: false)
    let first = ["settings", "set", "setup.skip_codegraph", "--", "off"]
    let second = ["settings", "set", "updates.slow_step_seconds", "--", "20"]
    let third = ["settings", "set", "apps.obsidian_vault", "--", "/tmp/v"]
    runner.stub(first, ok("", "Run set-defaults to apply it now."))
    runner.stub(second, .failure(.readOnly("t.count is read-only")))
    runner.stub(third, ok())
    await model.applyStaged()
    #expect(runner.calls == [listArgs, first, second, third, listArgs])
    #expect(model.failures == ["updates.slow_step_seconds: t.count is read-only"])
    #expect(model.notes == ["Run set-defaults to apply it now."])
    #expect(model.staged == [Edit(settingId: "updates.slow_step_seconds", change: .set("20"), shared: false)])
  }

  @Test func aReloadDropsOnlyTheEditsThatNoLongerDiffer() async {
    let (model, runner) = await loaded()
    model.stage("updates.slow_step_seconds", value: "20", shared: false)
    model.stage("apps.obsidian_vault", value: "/tmp/v", shared: false)
    model.stageReset("setup.skip_codegraph", shared: false)
    let changed = Fixtures.list
      .replacingOccurrences(of: #""value": "10""#, with: #""value": "20""#)
      .replacingOccurrences(of: #""value": "1",\#n    "source": "override""#, with: #""value": "",\#n    "source": "default""#)
    runner.stub(listArgs, ok(changed))
    await model.load()
    #expect(model.staged == [Edit(settingId: "apps.obsidian_vault", change: .set("/tmp/v"), shared: false)])
  }

  @Test func aReadOnlyRowCannotBeStaged() async {
    let (model, _) = await loaded()
    model.stage("hindsight.llm_model", value: "x", shared: false)
    model.stageReset("hindsight.llm_model", shared: false)
    #expect(model.staged.isEmpty)
  }

  @Test func sectionsKeepTheRegistryOrderAndFollowTheSearch() async {
    let (model, _) = await loaded()
    #expect(model.sections == ["Setup", "Agents"])
    model.search = "OBSIDIAN"
    #expect(model.sections == ["Setup"])
    #expect(model.rows(in: "Setup").map(\.settingId) == ["apps.obsidian_vault"])
    model.search = "arena_runners"
    #expect(model.sections == ["Agents"])
    model.search = "one per line"
    #expect(model.rows(in: "Agents").map(\.settingId) == ["hindsight.paths"])
  }

  @Test func aFailedLoadKeepsTheRowsAndSaysWhy() async {
    let (model, runner) = await loaded()
    runner.stub(listArgs, .failure(.failed(1, "uv: not found")))
    await model.load()
    #expect(model.rows.count == 9)
    #expect(model.failures == ["settings list: uv: not found"])
  }
}
