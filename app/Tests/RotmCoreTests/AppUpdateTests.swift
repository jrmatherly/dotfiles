import Foundation
import RotmCore
import RotmTestSupport
import Testing

private let multipassCask = """
  cask "claude-multipass-app" do
    version "0.14.0"
    sha256 "2e0bce238c824f8f0bfe01feb152a9129a62e95267a7862990c21877658ceef6"

    url "https://github.com/jrmatherly/claude-multipass/releases/download/v#{version}/claude-multipass-app_#{version}_arm64.dmg"
    name "Claude Multipass"
    desc "Menu bar app to switch Claude Desktop between saved claude.ai accounts"
    homepage "https://github.com/jrmatherly/claude-multipass"

    depends_on formula: "jrmatherly/tap/claude-multipass"
    depends_on arch: :arm64
    depends_on macos: :sonoma

    app "Claude Multipass.app"

    zap trash: [
      "~/Library/Caches/net.matherly.claude-multipass",
      "~/Library/HTTPStorages/net.matherly.claude-multipass",
      "~/Library/Preferences/net.matherly.claude-multipass.plist",
    ]
  end
  """

// docs/superpowers/specs/2026-11-13-p5-probe/guest-2026.11.8/row4-5-upgrade-no-terminal.txt,
// run while the app was running: exit 0, and the old process lived on.
private let upgradedWhileRunning = """
  mise brew: all formulae already poured
  hdiutil: WARNING: 'hdiutil detach ...' is deprecated. Please use 'diskutil eject ...' instead.
  "disk7" ejected.
  mise WARN  brew-cask: replacing /Applications/Claude Multipass.app — macOS may revoke Privacy & Security permissions for this app (Accessibility, Screen Recording, Full Disk Access, etc.); re-grant them in System Settings if prompted. To take over an existing app without replacing it, set adopt = true or [bootstrap.brew] adopt = true
  mise brew-cask:jrmatherly/tap/claude-multipass-app ✓ 0.14.0
  mise brew-cask: upgraded jrmatherly/tap/claude-multipass-app 0.13.0 -> 0.14.0
  """

// Measured 2026-11-13 with mise 2026.11.8 from $HOME, `--dry-run` only: the real
// upgrade was not run on this Mac. With the cask absent from the tap:
private let caskNotInTap: Result<CommandOutput, CommandError> = .failure(
  .failed(
    1,
    """
    mise ERROR published cask metadata was unavailable (failed to fetch Homebrew cask 'returnofthemac-app') and mise could not evaluate Casks/returnofthemac-app.rb
    mise ERROR tap has no Casks/returnofthemac-app.rb
    mise ERROR HTTP status client error (404 Not Found) for url (https://raw.githubusercontent.com/jrmatherly/homebrew-tap/4f5ec6485454d8accbe741312008f5046ec5074c/Casks/r/returnofthemac-app.rb)
    mise ERROR Version: 2026.11.8 macos-arm64 (2026-11-13)
    mise ERROR Run with --verbose or MISE_VERBOSE=1 for more information
    """))
// With a cask the tap has and no config declares (`brew-cask:hex-fiend`):
private let caskNotDeclared: Result<CommandOutput, CommandError> = .success(
  CommandOutput(stdout: "", stderr: "mise WARN  brew-cask: 1 package(s) not installed — run `mise bootstrap packages apply` first"))

private func makeBundle(version: String?, name: String = "Return of the Mac.app") throws -> URL {
  let app = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
  try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
  try writeVersion(version, to: app)
  return app
}

private func writeVersion(_ version: String?, to app: URL) throws {
  var info: [String: String] = ["CFBundleIdentifier": "net.matherly.returnofthemac"]
  info["CFBundleShortVersionString"] = version
  let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
  try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
}

private struct Offline: Error {}

final class FetchCount: @unchecked Sendable {
  var count = 0
}

@MainActor
struct AppUpdateTests {
  @Test func readsTheVersionLineOfACask() {
    #expect(AppUpdate.version(inCask: multipassCask) == "0.14.0")
    #expect(AppUpdate.version(inCask: "cask \"x\" do\nend\n") == nil)
    #expect(AppUpdate.version(inCask: "  version \"1.2,3\"\n") == nil)
  }

  @Test func comparesVersionsNumerically() {
    #expect(AppUpdate.isNewer("0.10.0", than: "0.9.9"))
    #expect(!AppUpdate.isNewer("0.2.0", than: "0.2.0"))
    #expect(!AppUpdate.isNewer("0.2", than: "0.2.0"))
    #expect(!AppUpdate.isNewer("x", than: "0.1.0"))
  }

  @Test func theUpgradeIsOneMiseCommandForTheAppsCask() {
    #expect(AppUpdate.upgradeArguments == ["bootstrap", "packages", "upgrade", "--yes", "brew-cask:jrmatherly/tap/returnofthemac-app"])
  }

  @Test func aNewerCaskOffersTheUpdate() async {
    let state = makeState(FakeRunner())
    await state.checkAppUpdate(fetch: { _ in "  version \"0.2.0\"\n" }, current: "0.1.0")
    #expect(state.appUpdate == "0.2.0")
  }

  @Test func theSameVersionOffersNothing() async {
    let state = makeState(FakeRunner())
    await state.checkAppUpdate(fetch: { _ in "  version \"0.1.0\"\n" }, current: "0.1.0")
    #expect(state.appUpdate == nil)
  }

  @Test func aFailedCheckIsSilent() async {
    let state = makeState(FakeRunner())
    await state.checkAppUpdate(fetch: { _ in throw Offline() }, current: "0.1.0")
    #expect(state.appUpdate == nil)
    #expect(state.lastError == nil)
  }

  @Test func checksAtMostOnceADay() async {
    let clock = Clock()
    let state = makeState(FakeRunner(), clock: clock)
    let fetches = FetchCount()
    let fetch: (URL) async throws -> String = { url in
      #expect(url == AppUpdate.caskURL)
      fetches.count += 1
      return "  version \"0.2.0\"\n"
    }
    await state.checkAppUpdate(fetch: fetch, current: "0.1.0")
    clock.advance(minutes: 23 * 60)
    await state.checkAppUpdate(fetch: fetch, current: "0.1.0")
    #expect(fetches.count == 1)
    clock.advance(minutes: 61)
    await state.checkAppUpdate(fetch: fetch, current: "0.1.0")
    #expect(fetches.count == 2)
  }

  @Test func diskVersionReadsThePlistOnDiskEachTime() throws {
    let app = try makeBundle(version: "0.1.0")
    #expect(AppUpdate.diskVersion(app) == "0.1.0")
    try writeVersion("0.2.0", to: app)
    #expect(AppUpdate.diskVersion(app) == "0.2.0")
  }

  @Test func aDevelopmentBuildHasNoVersionToCheck() throws {
    #expect(AppUpdate.runningVersion(try makeBundle(version: "0.1.0", name: "debug")) == nil)
    #expect(AppUpdate.runningVersion(try makeBundle(version: nil)) == nil)
    #expect(AppUpdate.runningVersion(try makeBundle(version: "0.1.0")) == "0.1.0")
  }

  @Test func theVersionOnDiskDecidesTheOutcome() {
    #expect(AppState.outcome(expected: "0.2.0", diskVersion: "0.2.0") == .relaunch)
    #expect(AppState.outcome(expected: "0.2.0", diskVersion: "0.3.0") == .relaunch)
    guard case .unchanged(let text) = AppState.outcome(expected: "0.2.0", diskVersion: "0.1.0") else {
      Issue.record("not unchanged")
      return
    }
    #expect(text.contains("was not replaced"))
    #expect(text.contains("mise bootstrap packages upgrade brew-cask:jrmatherly/tap/returnofthemac-app"))
    guard case .failed(let missing) = AppState.outcome(expected: "0.2.0", diskVersion: nil) else {
      Issue.record("not failed")
      return
    }
    #expect(missing.contains("https://github.com/jrmatherly/returnofthemac/releases"))
  }

  /// Review Focus 5: mise can fail after the bundle was swapped.
  @Test func aFailureAfterTheSwapStillRelaunches() async throws {
    let app = try makeBundle(version: "0.1.0")
    let mise = FakeRunner()
    mise.stub(AppUpdate.upgradeArguments, .failure(.failed(1, "mise ERROR something after the swap")))
    let release = mise.hold(AppUpdate.upgradeArguments)
    let state = makeState(FakeRunner())
    let upgrade = Task { await state.upgradeApp(mise: mise, app: app, expected: "0.2.0") }
    await waitUntil { state.upgrading }
    #expect(state.upgrading)
    #expect(state.blocked)
    try writeVersion("0.2.0", to: app)
    release()
    #expect(await upgrade.value == .relaunch)
    #expect(!state.upgrading)
    #expect(mise.calls == [AppUpdate.upgradeArguments])
  }

  @Test func miseReplacingTheRunningAppRelaunches() async throws {
    let app = try makeBundle(version: "0.1.0")
    let mise = FakeRunner()
    mise.stub(AppUpdate.upgradeArguments, .success(CommandOutput(stdout: upgradedWhileRunning, stderr: "")))
    let release = mise.hold(AppUpdate.upgradeArguments)
    let state = makeState(FakeRunner())
    let upgrade = Task { await state.upgradeApp(mise: mise, app: app, expected: "0.2.0") }
    await waitUntil { state.upgrading }
    try writeVersion("0.2.0", to: app)
    release()
    #expect(await upgrade.value == .relaunch)
  }

  @Test(arguments: [(caskNotInTap, "tap has no Casks/returnofthemac-app.rb"), (caskNotDeclared, "not installed")])
  func aCaskNoConfigDeclaresLeavesTheAppAsItWas(result: Result<CommandOutput, CommandError>, words: String) async throws {
    let app = try makeBundle(version: "0.1.0")
    let mise = FakeRunner()
    mise.stub(AppUpdate.upgradeArguments, result)
    let state = makeState(FakeRunner())
    guard case .unchanged(let text) = await state.upgradeApp(mise: mise, app: app, expected: "0.2.0") else {
      Issue.record("not unchanged")
      return
    }
    #expect(text.contains("was not replaced"))
    #expect(text.contains(words))
    #expect(!state.upgrading)
  }
}
