# P5: The menu bar app, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person who never opens a terminal can see the state of their returnofthemac setup, change any setting, switch profile, sync, update the setup and update the app, from a menu bar app that runs the same commands a terminal user types.

**Architecture:** A Swift package in `app/` with a Foundation-only core (`RotmCore`: the command runner, the JSON models, the app state) and an AppKit/SwiftUI shell (`ReturnOfTheMac`: a status item with a menu, a native settings window, a console window). The app holds no settings logic: it reads `rotm settings list --json` and a new `rotm settings status --json`, and every change is one `rotm` or `mise` command. Long or interactive commands (update, install, the GitHub sign-in) run inside the app under a pseudo-terminal, so the password prompt and Touch ID behave as they do in Terminal. The app ships as a notarized DMG behind a cask in `jrmatherly/tap`, declared in a new `menubar` module, and updates itself by asking mise to upgrade that one cask.

**Tech Stack:** Swift 5.9 tools, macOS 14+, AppKit and SwiftUI, Swift Testing, no third-party Swift dependency. Python 3.11+ standard library (`settings/`), bash 3.2 (`bin/`), mise 2026.11.8, GitHub Actions on `macos-26`.

**Spec:** `docs/superpowers/specs/2026-11-11-installable-setup-profiles-and-sync.md`. Read its Goal and "Decisions the owner made" in full before Task 1, decisions 16 to 20 included. This plan implements the P5 brief and the spec's "Menu bar app" section.

**Reference:** `~/dev/claude-multipass` at tag `v0.14.0` is the app this one is modelled on. Where a task says "as the reference does", read the named file there. Copy scaffolding, never its account, Keychain, Sparkle or brew code.

## Global Constraints

- macOS only (decision 4). Minimum macOS 14, arm64, as the reference app.
- The app adds no logic (spec, "Menu bar app"). Every action is one command that also works in a terminal. A value the app needs and the command line does not print is added to the command line, never computed in Swift.
- The app confirms before `set`, `reset`, `apply`, a profile switch, a sync, an update and an install (P5 brief).
- Code lives in this repository under `app/` (decision 16). It lands on `main` like everything else, behind `pnpm check`.
- No Sparkle, no appcast, no `brew`. The app updates through `mise bootstrap packages upgrade <its cask>` (decision 18). It tells the user an update exists and installs it only when the user chooses to.
- Nothing leaves the base, and every group has an opt-out (decisions 3 and 12). The app's cask is a module of its own, `menubar`, on by default.
- An installed copy stays fast-forwardable: the app never writes inside the checkout. Its own files are `~/Library/Logs/returnofthemac/` and its `UserDefaults` domain.
- mise floor stays 2026.11.8. Every `mise` call runs from `$HOME`.
- A GUI app has no shell PATH. The app runs `~/dotfiles/bin/rotm` by absolute path (setup always makes that link) with `PATH` set to `~/.local/bin:~/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`. Measured 2026-11-13: `rotm settings profile list` runs under `env -i` with that PATH.
- The owner's Mac is a development clone. Never run `./setup.sh`, `sysup`, `rotm install`, `rotm update`, `rotm settings sync on|off|now|apply`, `rotm settings profile use|new`, `rotm settings set|reset|apply`, `mise bootstrap` (other than `status`, `--help` and `--dry-run`) or `rotm-modules set|sync` against the real home, and never launch the built app against the real home. Swift tests use a fake runner or a temp script. Python and bash self-checks use scratch homes, as `settings/tests/test_cli.py` and `bin/lib/test-profiles` do.
- A real install, update, sync, profile switch or app update is run in the macOS VM by the owner (the spec's testing rule). When a step needs the VM, the session running it writes the owner a numbered runbook at that moment, not before (owner, 2026-11-13).
- The Swift app target uses the Observation macros, whose compiler plugin ships with Xcode. Every script that builds or tests the package sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when `xcode-select -p` is the Command Line Tools and Xcode is installed, as the reference's `test/check.sh:76-79` does. Without Xcode the gate skips the Swift job with one line on stderr, as it does for `uv`.
- `pnpm check` runs before every commit. Edit and commit in separate Bash calls. One commit per task, with the subject the task names.
- Docs mirror behaviour: a change to setup or settings behaviour has its `README.md`, `settings/README.md` or `docs/` edit in the same commit. A docs page is never named after a command.
- An owner-pointing value (bundle id, tap, signing team, release URL) gets its row in `docs/forking.md` in the commit that adds it (decision 12).
- Swift style: two-space indent, no comment that restates the code, one type per file where the file would pass 200 lines.

## Decided while writing this plan

Each of these is a default the owner can change before Task 3. None was asked.

- **Names.** The app is "Return of the Mac" (`Return of the Mac.app`), bundle id `net.matherly.returnofthemac`, cask `jrmatherly/tap/returnofthemac-app`, DMG `returnofthemac-app_<version>_arm64.dmg`, release tags `app-v<version>`. The app's version is the one line in `app/VERSION`, starting at `0.1.0`. It is separate from the checkout, which has no version.
- **A menu, not a popover.** The status item opens an `NSMenu`. The reference's popover exists to show account rows with usage rings, which this app does not have. A menu is a fraction of the code and reads the same to VoiceOver.
- **Edits are staged.** The settings window collects changes and shows a bar, "3 changes", with Review. Review lists each `rotm settings set` line, and Apply runs them. That is the confirmation the brief asks for, once per batch and not once per toggle.
- **How the app learns of its own update.** It reads the cask file in the tap (`https://raw.githubusercontent.com/jrmatherly/homebrew-tap/HEAD/Casks/returnofthemac-app.rb`) once a day and when the menu opens, and compares its `version "…"` line with its own. The tap is what mise reads, so the notice and the upgrade always agree. The output of `mise … upgrade --dry-run` when an update is waiting has never been seen, so the app does not parse it.
- **The terminal UI stays.** The owner's end goal removes the browser variant (`rotm settings serve`). The terminal UI is part of the command line and keeps the per-project plugin stack screen, which the app does not get: a menu bar app has no project folder.
- **No notification banner.** "Notify" is a badge on the status item and a line at the top of the menu. A `UNUserNotification` needs a permission prompt on first launch, and is not built.

## Measured for this plan (2026-11-13, this Mac, mise 2026.11.8)

| Fact | How |
| --- | --- |
| mise upgrades one cask by name with no `brew` | `mise bootstrap packages upgrade --dry-run brew-cask:jrmatherly/tap/claude-multipass-app` printed "already up to date", exit 0. Its `--help`: "Name packages as `manager:package` to upgrade only those" |
| mise records the casks it installed | `mise bootstrap packages status --json` has `"managed_by":"mise"` and `installed_version` on that row. The Caskroom holds `.mise-cask.toml` and a link to the app |
| The reference app cannot update on a rotm Mac | `Updates.swift:26-48` returns `homebrewMissing` when the Caskroom link exists and `<prefix>/bin/brew` does not, which is this Mac's state. Read, not launched |
| `rotm update` does not upgrade a cask | `setup.sh:401` runs `packages upgrade` only under `-- --upgrade` |
| `list --json` is 111 rows with 11 fields and no `kind` | Ran it. `cli.py:40-43` |
| `profile list` and `sync status` are text only, and nothing prints clone or installed | `cli.py:102-107`, `bin/lib/rotm-mode` |
| `sync on` refuses to sign in without a terminal | `sync.py:251-252` |
| `setup.sh` asks for the password once only when stdin is a terminal | `setup.sh:315-321` |
| `/usr/bin/script -q /dev/null <cmd>` gives the command a terminal when the caller has none | `printf 'x\n' \| script -q /dev/null sh -c 'test -t 0 && echo tty'` printed `tty`. The piped line itself did not reach `read`, because `printf` closed the pipe first. Task 5's test pins delivery over a pipe that stays open |
| `rotm` runs from a bare environment | `env -i HOME=… PATH=<the list above> ~/dotfiles/bin/rotm settings profile list` printed `* default`, exit 0 |

From mise's cask page (`mise.jdx.dev/bootstrap/packages/brew-cask.html`, read 2026-11-13): `upgrade` "installs the current version of each configured cask whose installed version differs from Homebrew's"; a self-updating cask is replaced only when "the app is not running"; a step that needs root, run without a terminal, "fails instead of waiting for a password"; replacing a bundle can drop its Privacy permissions. Not stated there: whether an ordinary cask is replaced while its app runs. Task 0 measures it.

## Review Focus

1. **The command is missing or broken.** `~/dotfiles/bin/rotm` absent, `uv` absent, or mise below the floor. The menu must say which, in the command's own words, with nothing else enabled. Test in Task 4.
2. **A setting changed underneath the app.** A terminal `rotm settings set`, a profile switch or a sync lands while the settings window holds staged edits. The window must reload and keep only the staged edits that still differ. Test in Task 6.
3. **A command that never ends or asks a question the app does not expect.** `rotm update` waiting on a prompt the console does not recognise. The console must show the raw output and always offer an input line and a Stop button. Test in Task 5.
4. **A value with characters a shell would eat.** A string setting holding spaces, quotes, `#` or a leading `-`. The app passes arguments as an array and puts `--` before a value, so the command receives it byte for byte. Tests in Tasks 1 and 6.
5. **The app is replaced while it runs.** The self-update swaps the bundle under the running process, or fails halfway. The version on disk decides the outcome, and the app relaunches only when it is the new one. Test in Task 10.

---

### Task 0: Probes in the VM (the owner runs them)

This task changes no file in the repository. It gates Task 5's console design and Task 10's upgrade call, and nothing else: Tasks 1 to 4 and 6 start without it.

**Files:**
- Create: `docs/superpowers/specs/2026-11-13-p5-probe/` (the results, one text file per row, and `probe.sh`)

- [ ] **Step 1: Write `probe.sh`** from the rows below, modelled on `docs/superpowers/specs/2026-11-13-p4-probe/probe.sh`, and write the owner a numbered runbook for the UTM guest (start from a snapshot taken after a clean install, share `~/vm-proof/p5/`, run under `/bin/bash`).
- [ ] **Step 2: The owner runs it.** Rows:

| Row | Command, on an installed guest | Records |
| --- | --- | --- |
| 1 | `rotm update -y < /dev/null > out 2>&1`, no terminal | Exit code, and whether any step asked for or failed on a password |
| 2 | `( sleep 600 ) \| script -q /dev/null rotm update -y`, typed password when asked | That the one `sudo -v` prompt appears, where in the output, its exact text, and that the run completes |
| 3 | Row 2 with Touch ID configured (`sudo_local`), if the guest has it | Whether the system dialog appears with no terminal window. Skip on a guest without Touch ID |
| 4 | Install `claude-multipass-app` at the version before the tap's current one, launch it, then `mise bootstrap packages upgrade --dry-run brew-cask:jrmatherly/tap/claude-multipass-app` and the same with `--yes`, from a login with no terminal (`ssh` is not available: run it from a LaunchAgent plist the probe writes, or from Script Editor) | The dry run's exact output when an update waits; whether the running app is replaced, skipped or refused; whether a password was needed; the bundle version on disk afterwards |
| 5 | `gh auth login --hostname github.com --git-protocol https --web` under `script -q /dev/null`, stdin a pipe held open | Every prompt's exact text, in order |

- [ ] **Step 3: Copy the results in** and commit: "Record the P5 probes". Add each row to the spec's "Verified facts".

If row 2 fails (no prompt reaches a piped stdin, or the run stops), stop and tell the owner: Task 5's console then needs a real pseudo-terminal opened by the app (`openpty` and `login_tty` in a small helper), which this plan does not specify.

---

### Task 1: The command line tells a GUI what it needs

**Files:**
- Modify: `settings/src/dotfiles_settings/cli.py` (`to_json`, `parser`, `run`)
- Modify: `settings/src/dotfiles_settings/sync.py` (split `status`, add `pending`)
- Modify: `settings/src/dotfiles_settings/profile.py` (add `state`)
- Modify: `settings/tests/test_cli.py`, `settings/tests/test_sync.py`, `settings/tests/test_profile.py`
- Create: `app/Tests/Fixtures/list.json`, `app/Tests/Fixtures/status.json` (written by the test in Step 5)
- Modify: `settings/README.md`

**Interfaces:**
- Produces: `rotm settings list --json` rows gain `kind`, `help`, `scope`, and for a `widget == "seats"` row `seat_models: [str]` and `seat_efforts: [str]` (empty lists on every other row).
- Produces: `rotm settings status [--json]`. JSON, exactly these keys:

```json
{
  "mode": "clone",
  "branch": "main",
  "commit": "a7bff71",
  "profile": { "active": "default", "names": ["work"], "missing": null, "mise_env": false },
  "sync": { "connected": false, "origin": null, "waiting": [], "conflicts": null },
  "pending": { "install": false, "defaults": false }
}
```

  `mode` is `clone` or `installed`. `profile.active` is `default` when no profile is in effect. `profile.missing` is the saved profile's name when it has no settings file here, else null. `sync.conflicts` is mise's conflict text, else null. `pending.install` and `pending.defaults` are what `sync apply` would print as its `rotm install` and `set-defaults` lines.
- Produces: `profile.state() -> dict`, `sync.state() -> dict`, `sync.pending() -> dict`, each returning the object above under its key. `sync.status()` and `profile.listing()` keep their text and are built from them.

- [ ] **Step 1: Write the failing tests.** In `test_cli.py`: `list --json` rows have exactly the keys `access, choices, drift, help, kind, label, scope, seat_efforts, seat_models, section, seed, setting_id, source, type, value, widget`; `status --json` has exactly the top-level keys `branch, commit, mode, pending, profile, sync` and the nested keys above; `status` without `--json` prints one line per fact and exits 0; `set t.text -- '-a "b" #c'` followed by `get t.text` prints `-a "b" #c` (add a string setting `t.text` to the fixture registry). In `test_sync.py`: `pending()` reports `install: True` after a module is switched off in the scratch home and leaves the remembered-state file byte-identical; `state()` is `connected: False` with no origin. In `test_profile.py`: `state()` for no profile, an active one, and a saved one with no file.
- [ ] **Step 2: Run them and see them fail.** `python3 settings/tests/test_cli.py` (and the other two). Expected: the new assertions fail, the old ones pass.
- [ ] **Step 3: Implement.** `to_json` adds the five fields; the seat lists come from `adapters/tool.py` (`MODELS`, `EFFORTS`, plus `inherit`, plus `codex` for a role in `CODEX_ROLES`, in the order `tui_agents.py:88` builds them). `sync.pending()` compares `_effective()` with the remembered file and writes nothing. `status` reads `mode` from `mise.installed(Path(os.environ["DOTFILES"]))`, `branch` and `commit` from `git -C $DOTFILES` (`symbolic-ref -q --short HEAD`, `rev-parse --short HEAD`; null when either fails). `status` must not call `registry.load()`.
- [ ] **Step 4: Run the three tests.** Expected: every line `ok`.
- [ ] **Step 5: Write the fixtures.** Add to `test_cli.py` a final block that, when `ROTM_WRITE_FIXTURES=1`, writes the scratch home's `list --json` and `status --json` to `app/Tests/Fixtures/`, and otherwise asserts each fixture's key set equals the live output's. Run once with the variable to create them. These two files are the contract Task 3's Swift decoder tests read, so a field renamed on one side fails the gate on the other.
- [ ] **Step 6: Document** `status` and the new fields in `settings/README.md`. `pnpm check`, then commit: "Tell a GUI the mode, the profile, the sync state and what is pending".

---

### Task 2: `rotm update --check`

**Files:**
- Modify: `bin/rotm` (the header's tldr block, `update`)
- Modify: `bin/lib/test-rotm`
- Modify: `docs/updating.md`

**Interfaces:**
- Produces: `rotm update --check [--json]`. It fetches the installed copy's branch and installs nothing. Text: `Up to date.` or `2 updates are waiting. Run rotm update.`. JSON: `{"mode":"installed","branch":"stable","behind":2}`. On a clone: `{"mode":"clone","branch":"main","behind":null}` and the text `This is a development clone. Pull it yourself.`, exit 0 both ways. Exit 1 with one line on stderr when the fetch fails.

- [ ] **Step 1: Write the failing cases** in `bin/lib/test-rotm`, with its existing stubs: an installed scratch copy two commits behind its bare origin prints `"behind":2` and leaves `git status --short` empty and `HEAD` where it was; a copy level with origin prints `"behind":0`; a clone prints `"behind":null`; an unreachable origin exits 1; `rotm update --check` runs no `mise` and no `setup.sh` (the stubs record calls).
- [ ] **Step 2: Run** `bash bin/lib/test-rotm`. Expected: fails at the first new case.
- [ ] **Step 3: Implement** in `update()`, before the mode refusal: `git -C "$DOTFILES" fetch --quiet origin "$branch"` then `git -C "$DOTFILES" rev-list --count "HEAD..origin/$branch"`.
- [ ] **Step 4: Run** `bash bin/lib/test-rotm` and `help rotm`. Expected: pass, and the new line renders.
- [ ] **Step 5:** `pnpm check`, commit: "Say whether an update is waiting without installing it".

---

### Task 3: The app package, its command runner and the gate

**Files:**
- Create: `app/Package.swift`, `app/VERSION` (`0.1.0`)
- Create: `app/Sources/RotmCore/CLI.swift`, `app/Sources/RotmCore/Models.swift`
- Create: `app/Sources/ReturnOfTheMac/App.swift` (an `NSApplicationDelegate` that sets an empty status item, nothing more)
- Create: `app/Tests/RotmCoreTests/CLITests.swift`, `app/Tests/RotmCoreTests/ModelsTests.swift`
- Modify: `bin/lib/check` (one Swift job), `.github/workflows/check.yml` (timeout 15 to 20 minutes), `.gitignore` and `.prettierignore` (`app/.build/`, `app/dist/`)
- Modify: `CLAUDE.md` (the Architecture block gains `app/`), `README.md` if it lists top-level folders

**Interfaces:**
- Produces, in `RotmCore`:

```swift
public struct CommandOutput: Equatable, Sendable { public let stdout: String; public let stderr: String }
public enum CommandError: Error, Equatable {
  case toolMissing(String)          // the path that was tried
  case readOnly(String)             // exit 3, stderr
  case invalid(String)              // exit 2, stderr
  case failed(Int32, String)        // any other exit, stderr
  case timedOut
  case badJSON(String)              // first 200 characters
}
public protocol CommandRunner: Sendable {
  func run(_ args: [String]) async throws -> CommandOutput     // args after `rotm`
}
public final class CLI: CommandRunner {
  public static let searchPath: String                          // the PATH in Global Constraints, ~ expanded
  public static func locate(override: String?) -> URL?          // override, else ~/dotfiles/bin/rotm, when executable
  public init(tool: URL, timeout: TimeInterval = 120)
}
public struct SettingRow: Codable, Identifiable, Equatable, Sendable {
  public var id: String { settingId }
  public let settingId: String, label: String, section: String, help: String, kind: String, scope: String
  public let type: String, access: String, widget: String, source: String
  public let value: String?, seed: String?
  public let drift: Bool
  public let choices: [String], seatModels: [String], seatEfforts: [String]
}
public struct Status: Codable, Equatable, Sendable {
  public struct Profile: Codable, Equatable, Sendable { public let active: String; public let names: [String]; public let missing: String?; public let miseEnv: Bool }
  public struct Sync: Codable, Equatable, Sendable { public let connected: Bool; public let origin: String?; public let waiting: [String]; public let conflicts: String? }
  public struct Pending: Codable, Equatable, Sendable { public let install: Bool; public let defaults: Bool }
  public let mode: String, branch: String?, commit: String?
  public let profile: Profile, sync: Sync, pending: Pending
}
public struct UpdateCheck: Codable, Equatable, Sendable { public let mode: String; public let branch: String?; public let behind: Int? }
public enum Decode { public static func rows(_ json: String) throws -> [SettingRow]; public static func status(_ json: String) throws -> Status; public static func updateCheck(_ json: String) throws -> UpdateCheck }
```

  JSON keys are snake_case, decoded with `.convertFromSnakeCase` (so `setting_id` is `settingId`). A decode failure throws `CommandError.badJSON`.

- [ ] **Step 1: Write `Package.swift`** as the reference's (`app/Package.swift` there), with the names `RotmCore`, `ReturnOfTheMac`, `RotmCoreTests`, `ReturnOfTheMacTests`, no dependency and no linker settings. Give the `RotmCoreTests` target `resources: [.copy("../Fixtures")]`.
- [ ] **Step 2: Write the failing tests.** `ModelsTests`: `Decode.rows` on `Fixtures/list.json` returns as many rows as the file has objects and a row's `settingId`, `kind` and `help` are non-empty; `Decode.status` on `Fixtures/status.json` returns `mode == "clone"`; `Decode.rows("nope")` throws `.badJSON`. `CLITests`, against a temp bash script as `CLITests.swift:5-33` in the reference builds one: exit 0 returns stdout and stderr; exit 3 throws `.readOnly` with stderr; exit 2 throws `.invalid`; exit 1 throws `.failed(1, …)`; a script that sleeps past a 1 s timeout throws `.timedOut` and is gone from `pgrep` afterwards; an argument `-a "b" #c` arrives as one argument, byte for byte; the child's `PATH` equals `CLI.searchPath` and its stdin is `/dev/null`; `CLI.locate(override: nil)` is nil when `~/dotfiles/bin/rotm` is not executable (inject the home directory).
- [ ] **Step 3: Run** `swift test --package-path app`. Expected: a compile failure naming the missing types.
- [ ] **Step 4: Implement** `Models.swift` and `CLI.swift`. Take the pipe draining, the process-group kill and the ANSI stripping from the reference's `CLI.swift:76-163`; drop its candidates list, version parsing and prompt-free table.
- [ ] **Step 5: Run** `swift test --package-path app`. Expected: all pass.
- [ ] **Step 6: Wire the gate.** In `bin/lib/check`, after the `uv` block: when `swift` and an Xcode with the macro plugin are present, `job quiet swift test --package-path app`, with `DEVELOPER_DIR` exported as Global Constraints says; otherwise `echo "check: Xcode not found, skipping the app tests" >&2`. Raise `check.yml`'s `timeout-minutes` to 20.
- [ ] **Step 7:** `pnpm check` (note its wall time before and after in the commit body), commit: "Add the menu bar app's package, its command runner and its models".

---

### Task 4: The app state and the menu

**Files:**
- Create: `app/Sources/RotmCore/AppState.swift`
- Create: `app/Sources/ReturnOfTheMac/StatusItemController.swift`, `app/Sources/ReturnOfTheMac/MenuBuilder.swift`
- Modify: `app/Sources/ReturnOfTheMac/App.swift`
- Create: `app/Tests/RotmCoreTests/AppStateTests.swift`, `app/Tests/RotmCoreTests/FakeRunner.swift`, `app/Tests/ReturnOfTheMacTests/MenuBuilderTests.swift`

**Interfaces:**
- Consumes: `CommandRunner`, `Decode`, `Status`, `UpdateCheck`, `CommandError` (Task 3).
- Produces:

```swift
@MainActor @Observable public final class AppState {
  public enum Tool: Equatable { case checking, ready, missing(String), broken(String) }   // broken carries the command's stderr
  public private(set) var tool: Tool
  public private(set) var status: Status?
  public private(set) var updateCheck: UpdateCheck?
  public private(set) var busy: String?            // "Switching to work…", nil when idle
  public private(set) var lastError: String?
  public var needsAttention: Bool { get }          // conflicts, waiting sync, pending, behind > 0, or an app update
  public init(makeRunner: @escaping (URL) -> CommandRunner, locate: @escaping () -> URL?, now: @escaping () -> Date = Date.init)
  public func refresh() async                      // status --json; update --check --json at most once an hour
  public func useProfile(_ name: String) async     // settings profile use <name>
  public func newProfile(_ name: String) async     // settings profile new <name>
  public func syncNow() async                      // settings sync now
  public func applySync() async                    // settings sync apply
}
public struct MenuEntry: Equatable { public enum Kind: Equatable { case info, action(String), toggle(Bool, String), separator, submenu([MenuEntry]) }; public let title: String; public let kind: Kind; public let enabled: Bool }
enum MenuBuilder { static func entries(for state: AppState, appUpdate: String?) -> [MenuEntry] }
```

  `FakeRunner` scripts responses by the joined arguments and records every call, as `AppStateTests.swift:6-52` in the reference does.

- The menu, top to bottom: an app-update line when one is waiting (Task 10 fills it); `Profile: <name>` with a submenu of every profile (the active one ticked) and `New Profile…`; `Sync: on, 2 changes waiting` or `Sync: off` with `Sync Now` or `Turn On Sync…` (Task 5 runs the latter); `Apply Changes…` only when `pending.install`; `Setup: up to date` or `Setup: 2 updates waiting` with `Update…` (Task 5); `Settings…` (Task 6); `Quit`. With `tool != .ready` the menu is the tool's message, `Settings…` disabled, and `Quit`.

- [ ] **Step 1: Write the failing tests.** `AppStateTests`: `locate` returning nil gives `.missing` and runs nothing; a runner whose `status --json` throws `.failed(1, "dotfiles-settings needs mise 2026.11.8 or newer, found 2026.11.5")` gives `.broken` with that text (Review Focus 1); a good status sets `tool == .ready` and `status`; `useProfile("work")` runs exactly `["settings","profile","use","work"]` then a status refresh, with `busy` set while the call is held and nil after; a failed action sets `lastError` to the command's stderr and still refreshes; two `refresh()` calls a minute apart run `update --check` once, and a third after 61 minutes runs it again (inject `now`); `needsAttention` is true for conflicts, for `behind == 2`, and false for a clean status. `MenuBuilderTests`: the entries for a clean status, for a status with a profile `work` active, for `.missing`, and for `behind == 2`, compared as arrays of `MenuEntry`.
- [ ] **Step 2: Run** `swift test --package-path app`. Expected: compile failure.
- [ ] **Step 3: Implement** `AppState`, `MenuBuilder`, and `StatusItemController` (builds an `NSMenu` from the entries in `menuNeedsUpdate`, refreshes on open and every 5 minutes, draws the SF Symbol `desktopcomputer` with a dot when `needsAttention`). A profile switch, a sync and an apply each show an `NSAlert` naming the command that will run before they call `AppState`.
- [ ] **Step 4: Run** the tests. Expected: all pass.
- [ ] **Step 5:** `pnpm check`, commit: "Show the setup's state in a menu and run its quick actions".

---

### Task 5: The console: update, install and the GitHub sign-in inside the app

Starts after Task 0's rows 1, 2 and 5 are recorded. Use their exact prompt text in the tests below.

**Files:**
- Create: `app/Sources/RotmCore/ConsoleSession.swift`
- Create: `app/Sources/ReturnOfTheMac/ConsoleWindow.swift`, `app/Sources/ReturnOfTheMac/ConsoleView.swift`
- Modify: `app/Sources/ReturnOfTheMac/MenuBuilder.swift`, `StatusItemController.swift`
- Create: `app/Tests/RotmCoreTests/ConsoleSessionTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor @Observable public final class ConsoleSession {
  public enum Phase: Equatable { case running, finished(Int32), stopped }
  public private(set) var text: String              // output so far, ANSI stripped, capped at the last 200,000 characters
  public private(set) var phase: Phase
  public private(set) var wantsSecret: Bool         // the last line is a password prompt
  public let title: String, logURL: URL
  public init(title: String, command: [String], environment: [String: String], logDirectory: URL)
  public func start()                               // runs /usr/bin/script -q <logURL> <command…>, stdin a pipe held open
  public func send(_ line: String)                  // writes line + "\n" to the child's stdin; never appended to `text` or the log when wantsSecret
  public func stop()                                // SIGTERM to the process group, SIGKILL after 2 s
}
```

  The commands: `Update…` runs `~/dotfiles/bin/rotm update -y`; `Run Setup Again…` (shown when `pending.install`) runs `rotm install -y`; `Turn On Sync…` runs `gh auth login --hostname github.com --git-protocol https --web` when `gh auth status` fails, then `rotm settings sync on`. Each sets `DOTFILES_SETUP_LOG` to the session's log so `setup.sh:155` does not start a second `script`. Logs go to `~/Library/Logs/returnofthemac/<yyyymmdd-hhmmss>-<title>.log`, mode 0600, newest 20 kept.

- [ ] **Step 1: Write the failing tests**, each against a temp bash script. The child sees a terminal on stdin and stdout (`test -t 0 && test -t 1`). A line sent with `send` two seconds after start reaches the script's `read` (the case the 2026-11-13 measurement did not prove). A script that prints `Password:` with no newline sets `wantsSecret`; the line then sent is absent from `text` and from the log file. A prompt the console has no rule for (`Proceed? [y/N] `) leaves `wantsSecret` false and the input line still works (Review Focus 3). `stop()` on a script that ignores SIGTERM ends it within 3 s and sets `.stopped`. A script exiting 2 gives `.finished(2)`. 300,000 characters of output leave `text.count == 200_000` and the whole output in the log. The log file's mode is 0600.
- [ ] **Step 2: Run** `swift test --package-path app --filter ConsoleSession`. Expected: compile failure.
- [ ] **Step 3: Implement** `ConsoleSession`. `wantsSecret` matches the last line against the prompt text Task 0 recorded plus `(?i)password.*:\s*$`.
- [ ] **Step 4: Implement the window.** One reusable `NSWindow`, title from the session: a monospaced read-only text view that follows the tail, an input field that turns into a `SecureField` while `wantsSecret`, Send, Stop (Close once finished), and "Show Log in Finder". Closing a running session asks first. When a session finishes, `AppState.refresh()` runs.
- [ ] **Step 5: Run** the tests. Expected: all pass.
- [ ] **Step 6:** `pnpm check`, commit: "Run update, setup and the GitHub sign-in in a console window".

---

### Task 6: The native settings window

**Files:**
- Create: `app/Sources/RotmCore/SettingsModel.swift`
- Create: `app/Sources/ReturnOfTheMac/SettingsWindow.swift`, `SettingsView.swift`, `SettingRowView.swift`, `ReviewSheet.swift`
- Modify: `app/Sources/ReturnOfTheMac/MenuBuilder.swift` (enable `Settings…`)
- Create: `app/Tests/RotmCoreTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `SettingRow`, `CommandRunner`, `AppState.status`.
- Produces:

```swift
public struct Edit: Equatable, Sendable { public enum Change: Equatable, Sendable { case set(String), reset }; public let settingId: String; public let change: Change; public let shared: Bool
  public var arguments: [String] { get } }   // ["settings","set","--shared"?, id, "--", value] or ["settings","reset","--shared"?, id]
@MainActor @Observable public final class SettingsModel {
  public private(set) var rows: [SettingRow]
  public private(set) var loading: Bool
  public private(set) var staged: [Edit]
  public private(set) var notes: [String]           // stderr of the last applied batch, one per command that printed one
  public private(set) var failures: [String]        // "<id>: <stderr>" for each command that failed
  public var search: String
  public var sections: [String] { get }             // registry order, filtered by search
  public func rows(in section: String) -> [SettingRow]
  public init(runner: CommandRunner)
  public func load() async                          // settings list --json
  public func stage(_ id: String, value: String, shared: Bool)   // staging the row's current value removes the edit
  public func stageReset(_ id: String, shared: Bool)
  public func unstage(_ id: String)
  public func applyStaged() async                   // one command per edit, in order, continuing past a failure; then load()
}
```

  A bool's value is sent as `on` or `off`. Search matches `label`, `settingId` and `help`, case-insensitively.

- The window: a sidebar of sections, a search field, and rows. A row shows the label, the help text beneath it, a control by type (`bool` a `Toggle`, `enum` a `Picker` of `choices`, `int` a number field, `string` and `path` a text field; `widget` rows arrive in Task 7 and show their value read-only until then), a badge for `source == "override"` with a Reset button, and a lock for `access == "ro"`. With a profile active, the bottom bar has a "Write to shared settings" checkbox, which sets `shared` on every staged edit. The bar shows "3 changes" and Review. `ReviewSheet` lists each edit as the command it will run and has Apply and Cancel. After Apply, the notes (such as the "run set-defaults" line) and any failures show in the bar until dismissed.

- [ ] **Step 1: Write the failing tests** with `FakeRunner`. `load()` fills `rows` from `Fixtures/list.json`. `stage` then `stage` back to the current value leaves `staged` empty. `Edit.arguments` for a value `-a "b" #c` is `["settings","set","t.text","--","-a \"b\" #c"]` (Review Focus 4), for a shared bool is `["settings","set","--shared","t.flag","--","on"]`, for a reset is `["settings","reset","t.flag"]`. `applyStaged()` with three edits where the second throws `.readOnly("t.count is read-only")` runs all three, puts one line in `failures`, puts the first command's stderr in `notes`, and ends with a `list --json` call. A reload whose rows now equal a staged edit's value drops that edit and keeps the others (Review Focus 2). An `ro` row cannot be staged. `sections` keeps the fixture's order and drops a section with no match for `search`.
- [ ] **Step 2: Run** `swift test --package-path app --filter SettingsModel`. Expected: compile failure.
- [ ] **Step 3: Confirm `set` accepts `--`.** `argparse` treats `--` as the end of options, and Task 1's test pins it. If that test needed a parser change, it is already made.
- [ ] **Step 4: Implement** the model and the views. The window is one reused `NSWindow` hosting SwiftUI, opened by `Settings…`, as the reference's `SettingsWindow.swift:15-27`. It reloads when it becomes key and after any console session or menu action finishes. `list --json` takes about 4 s (measured), so the first load shows a progress indicator and later reloads keep the old rows visible until the new ones arrive.
- [ ] **Step 5: Run** the tests. Expected: all pass.
- [ ] **Step 6:** `pnpm check`, commit: "Add a native window for every setting, with changes reviewed before they run".

---

### Task 7: The seats and list editors, and rendered checks

**Files:**
- Create: `app/Sources/RotmCore/Seats.swift`
- Create: `app/Sources/ReturnOfTheMac/SeatsEditor.swift`, `LinesEditor.swift`
- Modify: `app/Sources/ReturnOfTheMac/SettingRowView.swift`
- Create: `app/Tests/RotmCoreTests/SeatsTests.swift`, `app/Tests/ReturnOfTheMacTests/ShotsTests.swift`
- Create: `bin/lib/app-shots`
- Modify: `package.json` (`"shots": "bin/lib/app-shots"`), `.gitignore` (`.shots/`)

**Interfaces:**
- Produces: `public enum Seats { public static func parse(_ value: String) -> [(model: String, effort: String)]; public static func format(_ seats: [(model: String, effort: String)]) -> String }`. The format is the one `tui_agents.py:78` writes: seats joined by `, `, each `<model> <effort>`, or the model alone for `inherit` and `codex`.
- Produces: a `lines` value is its entries joined by newlines, as `LinesEditor` in `tui_agents.py` writes it. Read that class before writing the Swift one, and match its join exactly.

- [ ] **Step 1: Write the failing tests.** `SeatsTests`: `parse("fable medium, opus medium, opus medium")` is three seats; `format(parse(x)) == x` for that string, for `inherit`, for `codex` and for `sonnet medium`; `parse("")` is one empty seat. `ShotsTests`, a suite enabled only when `UI_SHOTS_DIR` is set, as the reference's `ShotsTests.swift:237`: with a fixture runner serving `Fixtures/list.json` and `Fixtures/status.json`, render the settings window (first section, the Agents section, the review sheet with two edits), the console window mid-run and at a password prompt, to PNGs in light and dark; and assert that no field takes focus when the settings window opens.
- [ ] **Step 2: Run** `swift test --package-path app --filter Seats`. Expected: compile failure.
- [ ] **Step 3: Implement.** `SeatsEditor` is one row per seat with a model `Picker` from `seatModels` and an effort `Picker` from `seatEfforts` (hidden for `inherit` and `codex`), with add and remove; `LinesEditor` is an editable list with add and remove. Both stage through `SettingsModel.stage`. `bin/lib/app-shots [dir]` sets `DEVELOPER_DIR` as the gate does and runs `UI_SHOTS_DIR=<dir> swift test --package-path app --filter Shots` (default `.shots/`).
- [ ] **Step 4: Run** the tests, then `pnpm shots`, and read every PNG in both themes. Fix what is clipped, unreadable or misaligned before committing. A UI review of this app starts from these images.
- [ ] **Step 5:** `pnpm check`, commit: "Edit jstack seats and path lists natively, and render the windows for review".

---

### Task 8: Build, sign and release

**Files:**
- Create: `app/Info.plist.in`, `app/ReturnOfTheMac.entitlements` (an empty `<dict/>`: no sandbox, no Apple events)
- Create: `app/scripts/build-app.sh`, `app/scripts/sign-mac-app.sh`
- Create: `bin/lib/test-app-build`
- Create: `.github/workflows/app-release.yml`
- Modify: `bin/lib/check` (the new self-check, and that `app/VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`), `.github/workflows/check.yml` (an unsigned `app/scripts/build-app.sh` after the gate)
- Modify: `docs/forking.md` (rows: bundle id, the signing team, the five release secrets, the release URL)

**Interfaces:**
- Produces: `app/scripts/build-app.sh [--dmg]` writes `app/dist/Return of the Mac.app` and, with `--dmg`, `app/dist/returnofthemac-app_<version>_arm64.dmg` plus `.sha256`. `APP_BUNDLE_ID` defaults to `net.matherly.returnofthemac`. Unsigned unless `MACOS_SIGN_IDENTITY` or a Developer ID identity is in the keychain; `MACOS_SIGN_REQUIRED=1` makes a missing identity fatal.
- Produces: pushing a tag `app-v<version>` builds, signs, notarizes and uploads the DMG and its `.sha256` to a GitHub release of that name.

- [ ] **Step 1: Write `bin/lib/test-app-build`:** `Info.plist.in` has no placeholder but `@VERSION@` and `@BUNDLE_ID@`; after an unsigned build, `plutil -extract CFBundleShortVersionString raw` on the bundle's plist equals `app/VERSION`, `LSUIElement` is true, `LSMinimumSystemVersion` is `14.0`, and the binary is arm64 (`lipo -archs`). It skips with one line when Xcode is absent.
- [ ] **Step 2: Run** `bash bin/lib/test-app-build`. Expected: fails, no script.
- [ ] **Step 3: Write the scripts** from the reference's `scripts/build-app.sh` and `scripts/sign-mac-app.sh`, without the bundled tool, the icon step, Sparkle, the rpath check and the framework signing. `Info.plist.in` is the reference's without `NSAppleEventsUsageDescription` and the three `SU*` keys. An app icon is not part of this plan: the owner makes `app/AppIcon.icon` in Icon Composer, and the build uses it when the file exists (the reference's `compile-icon.sh` step, copied then).
- [ ] **Step 4: Write `app-release.yml`** from the reference's `release.yml`: trigger `app-v*`; a `build` job on `macos-26` with a read-only token that checks the tag equals `app-v$(cat app/VERSION)` and that `HEAD` is on `origin/main`, checks the five secrets are set, runs `pnpm check`, then `MACOS_SIGN_REQUIRED=1 app/scripts/build-app.sh --dmg`, mounts the DMG and runs `spctl -a -vv` and `stapler validate` on the app inside; a `release` job on `ubuntu-latest` with `contents: write` that uploads the two files and never replaces an asset. Secrets, by name: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8`.
- [ ] **Step 5: Run** `bash bin/lib/test-app-build`, `actionlint .github/workflows/app-release.yml`. Expected: pass.
- [ ] **Step 6:** `pnpm check`, commit: "Build, sign and release the menu bar app".
- [ ] **Step 7: The owner's steps, when reached.** Write the owner a short runbook: set the five secrets on `jrmatherly/returnofthemac` with `gh secret set` (the same values `jrmatherly/claude-multipass` holds), then `git tag -a app-v0.1.0 -m "Return of the Mac 0.1.0" && git push origin app-v0.1.0`. Confirm the run is green and the release has both assets before Task 9. Pushing a tag and setting secrets are the owner's: ask, do not do them unasked.

---

### Task 9: The cask and the `menubar` module

Starts after Task 8's release exists.

**Files:**
- Create, in `~/dev/homebrew-tap` (the owner's tap, its own repository and rules): `Casks/returnofthemac-app.rb`
- Create: `tilde/.config/mise/conf.d/60-rotm-menubar.toml`
- Modify: `bin/lib/rotm-modules:46` (the `modules` list gains `menubar`), `settings/registry.toml` (a `modules.menubar` row after `modules.media`), `bin/lib/test-modules`, `bin/lib/test-packages`, `settings/tests/test_module.py`, `settings/tests/test_registry.py` where they count or list modules
- Modify: `docs/modules.md`, `README.md` (the module count and list), `docs/forking.md` (the cask row)

**Interfaces:**
- Produces: module `menubar`, on by default, declaring `"brew-cask:jrmatherly/tap/returnofthemac-app" = "latest"`. `rotm settings set modules.menubar off` and `--without menubar` skip it.

- [ ] **Step 1: Write the cask,** modelled on `Casks/claude-multipass-app.rb` in the tap: `version`, `sha256` from the release's `.sha256` asset, `url "https://github.com/jrmatherly/returnofthemac/releases/download/app-v#{version}/returnofthemac-app_#{version}_arm64.dmg"`, `depends_on arch: :arm64`, `depends_on macos: ">= :sonoma"`, `app "Return of the Mac.app"`, a `zap` of `~/Library/Logs/returnofthemac` and `~/Library/Preferences/net.matherly.returnofthemac.plist`. No `depends_on formula` and no `auto_updates`: mise replaces a self-updating cask only when its app is not running, and this app upgrades itself through mise. Read the tap's own `CLAUDE.md` or README for how it wants changes landed, and ask the owner before pushing there.
- [ ] **Step 2: Write the failing checks.** `test-modules`: `menubar` is in the list and `set menubar off` writes `conf.d/60-rotm-menubar.toml` into `ignored_config_paths`. `test-packages`: the new fragment's package names the listed tap. `test_registry.py`: `modules.menubar` exists with `kind = "module"`, `key = "menubar"`, `default = "on"`.
- [ ] **Step 3: Run** the three. Expected: each fails on the new assertion.
- [ ] **Step 4: Implement** the fragment (with the header comment the other `60-rotm-*.toml` files carry), the list entry and the registry row (`label = "Menu bar app"`, `help = "Return of the Mac in the menu bar: the settings window, sync, profiles and updates without a terminal."`).
- [ ] **Step 5: Run** the three checks, then from `$HOME`: `mise bootstrap packages status --json | jq '.[] | select(.package | test("returnofthemac"))'`. Expected: the checks pass, and the row reads `"state":"missing"`. Do not apply it on this Mac.
- [ ] **Step 6:** `pnpm check`, commit: "Ship the menu bar app as its own module".

---

### Task 10: The app updates itself through mise

Starts after Task 0's row 4 is recorded.

**Files:**
- Create: `app/Sources/RotmCore/AppUpdate.swift`
- Modify: `app/Sources/RotmCore/AppState.swift`, `app/Sources/ReturnOfTheMac/MenuBuilder.swift`, `StatusItemController.swift`
- Create: `app/Tests/RotmCoreTests/AppUpdateTests.swift`

**Interfaces:**
- Produces:

```swift
public enum AppUpdate {
  public static let package = "brew-cask:jrmatherly/tap/returnofthemac-app"
  public static let caskURL = URL(string: "https://raw.githubusercontent.com/jrmatherly/homebrew-tap/HEAD/Casks/returnofthemac-app.rb")!
  public static func version(inCask text: String) -> String?           // the first `version "X.Y.Z"` line
  public static func isNewer(_ candidate: String, than current: String) -> Bool   // numeric, component by component
  public static let upgradeCommand = ["mise", "bootstrap", "packages", "upgrade", "--yes", package]
}
public enum UpdateOutcome: Equatable { case relaunch, unchanged(String), failed(String) }   // the text is what the user is shown
// added to the AppState class itself (a stored property cannot live in an extension):
  public private(set) var appUpdate: String?     // the waiting version, nil when none; checked at most once a day and on menu open at most once an hour
  public func checkAppUpdate(fetch: (URL) async throws -> String, current: String) async
  public static func outcome(expected: String, diskVersion: String?, exit: Int32) -> UpdateOutcome
```

- The flow: the menu's first line reads `Update Return of the Mac to 0.2.0…` and the status item shows its dot. Nothing is installed until the user chooses that line. Choosing it shows an alert naming the command, then runs `AppUpdate.upgradeCommand` from `$HOME` in a console session (Task 5). When the session ends, the app reads `CFBundleShortVersionString` from its own bundle path on disk and takes `AppState.outcome`: `.relaunch` starts `/usr/bin/open -n <bundle>` and quits; the other two show their text and leave the app running.

- [ ] **Step 1: Write the failing tests.** `version(inCask:)` on the multipass cask's text (copy it into the test) returns `0.14.0`, and nil for text with no version line. `isNewer("0.10.0", than: "0.9.9")` is true, `("0.2.0", "0.2.0")` false, `("0.2", "0.2.0")` false, `("x", "0.1.0")` false. `checkAppUpdate` sets `appUpdate` to `0.2.0` when the cask says so and the app is `0.1.0`, leaves it nil when equal, leaves it nil and `lastError` nil when the fetch throws (a failed check is silent), and does not fetch twice inside the hour. `outcome`: disk at the expected version is `.relaunch` whatever the exit code (Review Focus 5: mise can fail after the swap); disk at the old version with exit 0 is `.unchanged` with a message that says the app was not replaced and names `AppUpdate.upgradeCommand` as text to run in a terminal; a nil disk version is `.failed` and its message names the releases page. Add one case for whatever Task 0's row 4 showed mise does to a running app.
- [ ] **Step 2: Run** `swift test --package-path app --filter AppUpdate`. Expected: compile failure.
- [ ] **Step 3: Implement.** The fetch is `URLSession` with a 10 s timeout and no cache. A development build (the bundle path does not end in `.app`, or no `CFBundleShortVersionString`) never checks.
- [ ] **Step 4: Run** the tests. Expected: all pass.
- [ ] **Step 5:** `pnpm check`, commit: "Tell the user when a newer app exists and upgrade it through mise when they choose".

---

### Task 11: Docs, the spec and the proof in the VM

**Files:**
- Create: `docs/menu-bar.md` (what the app shows, each menu line and the command it runs, the console, the settings window, how it updates, where its logs are, how to switch it off)
- Modify: `README.md`, `docs/README.md` (the index), `docs/installation.md`, `docs/updating.md`, `docs/settings-sync.md` (a line each pointing at the app), `settings/README.md`
- Modify: the spec: "Verified facts" (this plan's table and Task 0's rows), "Still not verified", the "Menu bar app" design section (the menu, the console, the staged edits, the update through mise, no Sparkle), "Plans" and the P5 brief's "Shipped" line
- Move: this file to `docs/superpowers/plans/completed/`

- [ ] **Step 1: Write the docs and the spec edits.** Run the `docs-audit` skill over the pages touched.
- [ ] **Step 2:** `pnpm check`, commit: "Document the menu bar app".
- [ ] **Step 3: The VM proof (the brief's "Done when").** Write the owner the runbook when this step is reached. On a guest installed through P1 with the `menubar` module on: for each menu action, run it in the app, then run its command in a terminal on a second snapshot of the same state, and compare `rotm settings status --json` and `rotm settings list --json` between the two. Cover: a profile switch and back, a setting changed and reset through the settings window (one `env`, one macOS preference, one module, one seats row), Turn On Sync against a real private repository, Sync Now, Update with a commit waiting on `stable`, and the app's own update from `0.1.0` to a `0.1.1` cut for the test. Results go under `~/vm-proof/p5/`. This run also settles P3's and P4's owed proofs if the owner chooses to fold them in.

---

### Task 12: Retire the browser variant (waits on the owner's word)

The owner's end goal of 2026-11-13: once the native window covers what the browser was used for, `rotm settings serve` goes. Do not start this task until the owner says the window has replaced it for them.

**Files:**
- Delete: `settings/src/dotfiles_settings/serve.py`, `settings/src/dotfiles_settings/templates/` (when nothing else reads it), `settings/tests/test_serve.py`
- Modify: `settings/src/dotfiles_settings/cli.py` (the `serve` parser and branch, `ui`'s error text), `settings/pyproject.toml` and `settings/uv.lock` (drop `textual-serve` and `aiohttp` when the terminal UI does not need them: check with `uv tree --project settings`), `bin/lib/check` (the `test_serve.py` job)
- Modify: every doc that names `serve` or "browser UI" (`rg -n 'serve|browser UI' README.md docs settings/README.md bin/dotfiles-settings CLAUDE.md`)

- [ ] **Step 1: Write the failing case** in `test_cli.py`: `serve` exits 2 as an unknown command.
- [ ] **Step 2: Delete and edit** as listed. `uv lock --project settings`.
- [ ] **Step 3: Run** `test_cli.py`, the two terminal UI tests under `uv run`, and `help dotfiles-settings`. Expected: pass, and no `serve` line renders.
- [ ] **Step 4:** `pnpm check`, commit: "Remove the browser settings UI, which the menu bar app replaces".

## Not built

- An app icon (the owner's to draw), a notification banner, launch at login, a hover panel, and the per-project plugin stack screen.
- Automatic installs of anything. The app only notifies.
- A check that the app and the checkout agree on the JSON at runtime. The shared fixtures catch a mismatch in the gate; an old app against a newer checkout shows the decode error and the Update line.
