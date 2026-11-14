import Foundation
import RotmCore
import RotmTestSupport
import Testing

let statusArgs = ["settings", "status", "--json"]
let checkArgs = ["update", "--check", "--json"]

final class Clock: @unchecked Sendable {
  var now = Date(timeIntervalSince1970: 1_000_000)
  func advance(minutes: Double) { now += minutes * 60 }
}

@MainActor
func makeState(_ runner: FakeRunner, located: Bool = true, clock: Clock = Clock()) -> AppState {
  AppState(
    makeRunner: { _ in runner },
    locate: { located ? URL(fileURLWithPath: "/fake/rotm") : nil },
    now: { clock.now })
}

func stubClean(_ runner: FakeRunner, status: String = Fixtures.status, check: String = Fixtures.updateCheck) {
  runner.stub(statusArgs, .success(CommandOutput(stdout: status, stderr: "")))
  runner.stub(checkArgs, .success(CommandOutput(stdout: check, stderr: "")))
}

@MainActor
func waitUntil(_ condition: () -> Bool) async {
  for _ in 0..<5000 where !condition() {
    try? await Task.sleep(nanoseconds: 2_000_000)
  }
}

@MainActor
struct AppStateTests {
  @Test func noToolIsMissingAndRunsNothing() async {
    let runner = FakeRunner()
    let state = makeState(runner, located: false)
    await state.refresh()
    guard case .missing = state.tool else { Issue.record("tool is \(state.tool)"); return }
    #expect(state.runner == nil)
    #expect(runner.calls.isEmpty)
  }

  @Test func aFailingStatusIsBrokenWithTheCommandsWords() async {
    let runner = FakeRunner()
    let words = "dotfiles-settings needs mise 2026.11.8 or newer, found 2026.11.5"
    runner.stub(statusArgs, .failure(.failed(1, words)))
    let state = makeState(runner)
    await state.refresh()
    #expect(state.tool == .broken(words))
    #expect(state.status == nil)
  }

  @Test func aGoodStatusIsReady() async throws {
    let runner = FakeRunner()
    stubClean(runner)
    let state = makeState(runner)
    await state.refresh()
    #expect(state.tool == .ready)
    #expect(state.status == (try Decode.status(Fixtures.status)))
    #expect(state.updateCheck?.behind == 2)
    #expect(state.runner != nil)
  }

  @Test func exclusiveWorkBlocksTheActionsAndThenRefreshes() async {
    let runner = FakeRunner()
    stubClean(runner)
    let state = makeState(runner)
    await state.refresh()
    let before = runner.calls.count
    await state.exclusive("Applying settings…") {
      #expect(state.blocked)
      await state.syncNow()
      await state.exclusive("again") { Issue.record("ran while blocked") }
      #expect(runner.calls.count == before)
    }
    #expect(!state.blocked)
    #expect(runner.calls.last == statusArgs)
    #expect(runner.calls.count == before + 1)
  }

  @Test func useProfileRunsOneCommandThenRefreshes() async {
    let runner = FakeRunner()
    stubClean(runner)
    let use = ["settings", "profile", "use", "--", "work"]
    runner.stub(use, .success(CommandOutput(stdout: "Open a new shell to pick this up.", stderr: "")))
    let state = makeState(runner)
    await state.refresh()
    let release = runner.hold(use)
    let action = Task { await state.useProfile("work") }
    await waitUntil { runner.calls.contains(use) }
    #expect(state.busy != nil)
    #expect(state.blocked)
    await state.syncNow()
    await state.newProfile("home")
    await state.refresh()
    #expect(runner.calls.last == use)
    release()
    await action.value
    #expect(state.busy == nil)
    #expect(!state.blocked)
    #expect(runner.calls.filter { $0 == use }.count == 1)
    #expect(Array(runner.calls.suffix(2)) == [use, statusArgs])
    #expect(state.lastOutput == "Open a new shell to pick this up.")
    #expect(state.lastError == nil)
    state.dismissOutput()
    #expect(state.lastOutput == nil)
  }

  @Test func aFailedActionSetsTheErrorAndStillRefreshes() async {
    let runner = FakeRunner()
    stubClean(runner)
    let sync = ["settings", "sync", "now"]
    runner.stub(sync, .failure(.failed(1, "sync is off. Run rotm settings sync on")))
    let state = makeState(runner)
    await state.refresh()
    await state.syncNow()
    #expect(state.lastError == "sync is off. Run rotm settings sync on")
    #expect(state.lastOutput == nil)
    #expect(Array(runner.calls.suffix(2)) == [sync, statusArgs])
  }

  @Test func newProfileRunsProfileNew() async {
    let runner = FakeRunner()
    stubClean(runner)
    let new = ["settings", "profile", "new", "--", "home"]
    runner.stub(new, .success(CommandOutput(stdout: "", stderr: "")))
    let state = makeState(runner)
    await state.refresh()
    await state.newProfile("home")
    #expect(Array(runner.calls.suffix(2)) == [new, statusArgs])
  }

  @Test func theUpdateCheckRunsAtMostHourly() async {
    let runner = FakeRunner()
    stubClean(runner)
    let clock = Clock()
    let state = makeState(runner, clock: clock)
    await state.refresh()
    clock.advance(minutes: 1)
    await state.refresh()
    #expect(runner.calls.filter { $0 == checkArgs }.count == 1)
    clock.advance(minutes: 61)
    await state.refresh()
    #expect(runner.calls.filter { $0 == checkArgs }.count == 2)
    #expect(runner.calls.filter { $0 == statusArgs }.count == 3)
  }

  // After the console's update, "2 updates waiting" must not stand for the rest of the hour.
  @Test func aRecheckRunsTheUpdateCheckWithinTheHour() async {
    let runner = FakeRunner()
    stubClean(runner)
    let clock = Clock()
    let state = makeState(runner, clock: clock)
    await state.refresh()
    #expect(state.updateCheck?.behind == 2)
    runner.stub(checkArgs, .success(CommandOutput(stdout: #"{"mode":"installed","branch":"stable","behind":0}"#, stderr: "")))
    clock.advance(minutes: 1)
    await state.refresh(recheckUpdates: true)
    #expect(runner.calls.filter { $0 == checkArgs }.count == 2)
    #expect(state.updateCheck?.behind == 0)
  }

  // A status read or a git fetch beside `rotm update` in the console would race it.
  @Test func refreshRunsNothingWhileACommandRuns() async {
    let runner = FakeRunner()
    stubClean(runner)
    let state = makeState(runner)
    await state.refresh()
    let before = runner.calls.count
    state.sessionRunning = true
    await state.refresh(recheckUpdates: true)
    #expect(runner.calls.count == before)
    state.sessionRunning = false
    await state.refresh()
    #expect(runner.calls.last == statusArgs)
  }

  @Test func quitAsksWhileACommandOrStagedEditsWouldBeLost() async {
    let runner = FakeRunner()
    stubClean(runner)
    let state = makeState(runner)
    await state.refresh()
    #expect(state.quitDecision(sessionTitle: nil, stagedEdits: 0) == .allow)
    #expect(
      state.quitDecision(sessionTitle: "Update", stagedEdits: 2)
        == .ask(message: "Stop Update and quit?", detail: "Quitting stops the command."))
    #expect(
      state.quitDecision(sessionTitle: nil, stagedEdits: 1)
        == .ask(message: "Quit and discard 1 change?", detail: "The settings window has a change you have not applied."))
    #expect(
      state.quitDecision(sessionTitle: nil, stagedEdits: 3)
        == .ask(message: "Quit and discard 3 changes?", detail: "The settings window has changes you have not applied."))

    let sync = ["settings", "sync", "now"]
    runner.stub(sync, .success(CommandOutput(stdout: "", stderr: "")))
    let release = runner.hold(sync)
    let action = Task { await state.syncNow() }
    await waitUntil { state.busy != nil }
    #expect(state.quitDecision(sessionTitle: nil, stagedEdits: 0) == .ask(message: "Quit while a command is running?", detail: "Syncing…"))
    release()
    await action.value
  }

  // Killing mise between removing and placing the bundle is the one way to lose the app.
  @Test func quitIsRefusedWhileTheAppUpgrades() async {
    let state = makeState(FakeRunner())
    let mise = FakeRunner()
    let release = mise.hold(AppUpdate.upgradeArguments)
    let upgrade = Task { await state.upgradeApp(mise: mise, app: URL(fileURLWithPath: "/nonexistent.app"), expected: "0.2.0") }
    await waitUntil { state.upgrading }
    #expect(state.quitDecision(sessionTitle: "Update", stagedEdits: 2) == .refuse)
    #expect(state.quitDecision(sessionTitle: nil, stagedEdits: 0) == .refuse)
    release()
    _ = await upgrade.value
    #expect(state.quitDecision(sessionTitle: nil, stagedEdits: 0) == .allow)
  }

  @Test func needsAttention() async {
    let clean = FakeRunner()
    stubClean(clean, check: #"{"mode":"installed","branch":"stable","behind":0}"#)
    let cleanState = makeState(clean)
    await cleanState.refresh()
    #expect(!cleanState.needsAttention)

    let behind = FakeRunner()
    stubClean(behind)
    let behindState = makeState(behind)
    await behindState.refresh()
    #expect(behindState.needsAttention)

    let conflicted = FakeRunner()
    stubClean(
      conflicted,
      status: Fixtures.status
        .replacingOccurrences(of: #""connected": false"#, with: #""connected": true"#)
        .replacingOccurrences(of: #""conflicts": null"#, with: #""conflicts": "a conflict to settle""#),
      check: #"{"mode":"installed","branch":"stable","behind":0}"#)
    let conflictedState = makeState(conflicted)
    await conflictedState.refresh()
    #expect(conflictedState.status?.sync.conflicts != nil)
    #expect(conflictedState.needsAttention)
  }
}
