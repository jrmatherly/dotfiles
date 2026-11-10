# A3 macOS Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The macOS preferences `setup/macos.sh` wrote become TOML that mise applies and checks for drift, and the settings UI can read and change them.

**Architecture:** `tilde/.config/mise/conf.d/20-macos.toml` declares 79 preferences as raw `[bootstrap.macos.defaults."<domain>"]` tables and `[[bootstrap.macos.defaults_entries]]`. `setup/macos-extras.sh` does what TOML cannot (sudo, `$HOME` paths, `pmset`, file flags, sandboxed apps, app restarts, and the preference groups a user can switch off) and is run by the `pre-defaults` and `post-defaults` hooks and by `set-defaults`. It reads nine `env` settings that the settings UI shows: four switches for the preference groups the old script asked about, two security switches (the firewall with stealth mode, and turning Time Machine off), all six on unless switched off, and three per-machine opt-ins (HiDPI, off unless switched on, and the computer name and local hostname, empty unless set). The `macos-default` adapter reads `mise bootstrap macos defaults status --json` and writes by a minimal text edit of the tracked fragment plus one `defaults write` of that key.

**Tech Stack:** mise 2026.11.5 (`bootstrap.macos`), bash, Python 3.11+ standard library (`tomllib`, `json`, `subprocess`).

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A3. macOS defaults", and its "Decisions" section: 1 (setup never applies macOS preferences), 2 (the security opt-ins are env settings in the UI; the firewall and turning Time Machine off are on by default, HiDPI is off and the computer name empty), 7 (the `mise bootstrap*` ask rule is A7's, not this plan's) and 9 (a UI switch for each preference group that used to ask). Phases A1 and A2 have landed.

**Line numbers** are from commit `9af6244`. An earlier phase may have moved them, so find the quoted text with `grep -n` before editing.

## Global Constraints

- Minimum mise version: 2026.11.5.
- Python 3.11 or newer for the package (`tomllib`). The package's core (registry, adapters, CLI) imports nothing outside the standard library, so its tests run with plain `python3`.
- Tests that isolate mise use `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`.
- Bash scripts start with `#!/bin/bash` and a tldr-style header, define their output helpers inline, and pass `pnpm check`.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix.
- Every phase updates the docs that describe what it changed, in the same commit (D12).
- The phase ends with `pnpm check` passing and `python3 setup/tests/macos-defaults.py` passing. `mise bootstrap status --missing` is informational: apps rewrite preferences without anyone changing the config, so it can exit 1 without cause. No step requires it to exit 0.
- Setup never applies macOS preferences. Only `bin/set-defaults` does, as today. `setup.sh` runs `mise bootstrap --skip macos-defaults` (A6 writes that line).
- Commits name their paths. No `git add -A`, no `git add .`, no bare directory. The working tree holds an unrelated uncommitted change to `agents/claude-settings.json` that must never enter a commit of this plan.
- Comments carry the why. Every explanatory comment in `setup/macos.sh` moves beside the key or command it explains.
- Use the spec's names exactly: `Setting`, `Value`, `Source` (`OVERRIDE`, `SEED`, `DEFAULT`, `UNSET`), `Adapter` (`read`, `write`, `reset`), kind `macos-default`.
- Do not run `set-defaults`, `mise bootstrap` or `mise bootstrap macos defaults apply` without `--dry-run` from an agent session. They change the machine. Task 7 is the user's step and needs the user's explicit go-ahead.

## Facts this plan rests on

Measured on this Mac on 2026-11-09 with mise 2026.11.5, in a scratch `MISE_CONFIG_DIR`.

- `conf.d/*.toml` beside the global `config.toml` loads. `config.local.toml` in the same directory loads too and outranks it (a `tilesize = 99` there replaced the fragment's 38 in `status`).
- The full fragment in Task 2, as first drafted with the screenshot, Time Machine new-disk and Software Update tables still in it, parsed with no warning. `status --json` listed 88 entries: 86 `set`, 2 `differs`, 0 `unset`. Those three tables now move to the extras script (Decision 9), taking 9 entries that were all `set` (`defaults read-type` on 2026-11-09: `type` and `name` strings, `disable-shadow`, `showsCursor`, `DoNotOfferNewDisksForBackup` and `AutomaticCheckEnabled` booleans, the other three Software Update keys integers). The fragment as written below, copied into a scratch `MISE_CONFIG_DIR/conf.d/` on 2026-11-09, parsed with no warning and listed 79: 77 `set`, 2 `differs`. The Task 2 coverage script, run against it, printed `91 defaults write lines, 79 declared preferences, 0 problems`.
- The two that differ are real drift on this Mac, not parse problems. `com.apple.finder DesktopViewSettings.IconViewSettings.arrangeBy` is `name` (declared `grid`). `com.apple.symbolichotkeys AppleSymbolicHotKeys.64.enabled` is the integer `0` (declared the string `"0"`, which is what the old script wrote and what key `65` still holds).
- `status --json` prints `{"macos_defaults": {"available": true, "entries": [{"domain", "host", "path", "key", "value", "current", "state"}]}}`. `state` is `set`, `differs` or `unset`. `current` is always a string. A config with no macOS section prints `{}`.
- Values are not templated. `"file://{{ env.HOME }}/"` was compared literally. So a `$HOME` path cannot live in the fragment.
- Hook commands are templated, and `{{ config_root }}` renders as `$HOME` for a global fragment, not the repo. Hooks run as `sh -o errexit -c '<command>'`.
- The `pre-defaults` and `post-defaults` hooks run under `mise bootstrap` when its `macos-defaults` part runs. `mise bootstrap macos defaults apply --dry-run` printed no hook. The review measured that `mise bootstrap --skip macos-defaults` drops the part and both hooks.
- Two runs of `status --json` with nothing changed in between print byte-identical output, so `cmp` of a before and an after tells whether an apply wrote anything.
- `defaults write <plist> k -string <v>` followed by `defaults read` returned the exact string for `Sh"ot \ #1`, the empty string and `-x` (run against a scratch plist).
- A wrong type, an unknown named key or a TOML date prints `mise WARN` on stderr and exits 0. The entry is dropped. A TOML syntax error also prints `mise WARN` and exits 0.
- `mise config set --file <fragment> --type integer 'bootstrap.macos.defaults."com.apple.dock".tilesize' 44` writes the nested key, and deletes every comment inside the table it edits. There is no `mise config unset`. So the adapter cannot use it.
- `defaults read com.apple.TextEdit` from an agent shell fails with `Domain '~/Library/Containers/com.apple.TextEdit/...' not found`, while `~/Library/Preferences/com.apple.TextEdit.plist` holds the three values the old script wrote. mise reported those keys, `com.apple.Preview` and `com.apple.helpviewer` as `unset`. The completed plan `docs/superpowers/plans/completed/2026-10-27-setup-robustness.md` (Task 10) records that the owner proved the TextEdit and Preview writes are honoured.
- `pmset -g cap` on this Mac does not list `lidwake`, and `pmset -g custom` does not report it.
- `setup.sh` does not run `setup/macos.sh`. Only `bin/set-defaults` does.
- The state of the sudo opt-ins reads without sudo. `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` printed `Firewall is enabled. (State = 1)` and `--getstealthmode` printed `Firewall stealth mode is on`. `socketfilterfw` is not on `PATH` (`command -v` finds nothing). `defaults read /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled` printed `Domain 'com.apple.windowserver' not found` (HiDPI never enabled here). `defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup` printed `0`. `scutil --get ComputerName` printed the current name. Re-measured on 2026-11-09 for the new defaults of Decision 2: the firewall and stealth mode read as above, `tmutil destinationinfo` printed `tmutil: No destinations configured.`, `/Library/Preferences/com.apple.TimeMachine` holds only `AutoBackup = 0` and `PreferencesVersion = 6`, and `socketfilterfw --getblockall` printed `Firewall has block all state set to disabled.` (block-all is reported by its own flag, not by `--getglobalstate`). So with the two switches on by default, this Mac already matches and asks for no sudo.
- An `env` setting set to false reaches a shell as an empty, set variable. In a scratch `MISE_CONFIG_DIR`, `mise set --override DOTFILES_MACOS_SCREENSHOTS=` stored `""`, and `mise env --dotenv` printed `DOTFILES_MACOS_SCREENSHOTS=`, which A1's `zsh/override-env.zsh` exports as `''`. So `${VAR-1}` tells "switched off" (empty) from "never set" (unset, on by default). A value with an apostrophe (`Jason's MacBook Pro`) round-tripped unchanged.

From mise's docs, not run here: mise never uses `sudo` for a preference, never deletes one, and does not restart apps. A declared value replaces the whole preference, except a `defaults_entries` item with `path`, which replaces one dictionary key and creates missing dictionaries. Two conflicting `defaults_entries` are rejected before any write.

## Classification of `setup/macos.sh`

The file has 91 uncommented `defaults write` lines (the spec's first draft said 87, and it now says 91). 2 use `sudo`, 2 use `-currentHost`. The hot-corner loop (lines 386 and 387) is 2 lines and 8 writes.

| Where it goes | Lines | Count |
| --- | --- | --- |
| `[bootstrap.macos.defaults."<domain>"]` tables | every `defaults write` line not listed below | 62 lines, 68 keys |
| `[[bootstrap.macos.defaults_entries]]` with `host = "current"` | 131, 529 | 2 |
| `[[bootstrap.macos.defaults_entries]]` with `path` (were `-dict-add`) | 281, 434, 437 | 3 |
| `[[bootstrap.macos.defaults_entries]]` with `path` (were `PlistBuddy Set`) | 266, 267, 268, 276, 277, 278 | 6 |
| Not declared, documented as a `config.local.toml` opt-in (prompts that defaulted to No) | 101, 260, 261, 262, 364, 365 | 6 |
| `setup/macos-extras.sh`: `sudo defaults` | 72, 194 | 2 |
| `setup/macos-extras.sh`: value holds `$HOME` | 180, 217 | 2 |
| `setup/macos-extras.sh`: sandboxed app domain mise cannot read back | 108, 495, 496, 497, 522 | 5 |
| `setup/macos-extras.sh`: a preference group behind a UI switch (Decision 9) | 182, 184, 186, 188 (screenshots), 463 (Time Machine new disks), 506, 508, 510, 512 (Software Update) | 9 |

Total declared: 68 + 2 + 3 + 6 = 79 preferences. Of the 91 lines, 67 move to TOML, 6 become opt-ins and 18 go to the extras script.

Why the three groups leave the fragment: Decision 9 gives each group that used to ask a switch, and a switch that is off must leave the group alone. mise applies every declared preference, has no per-domain filter (`mise bootstrap macos defaults apply --help` lists only `--dry-run` and `--yes`), does not template values, and `config.local.toml` can pin another value but cannot undeclare one. So a switchable group can only live in the extras script. The cost: those 9 preferences are no longer in `status` (no drift report) and no longer editable one by one in the UI. The owner accepted it: these groups are choices, not mandated settings, so a drift report for them is not needed (Decision 9). TextEdit and the screenshot folder were already in the extras script.

Named keys. 14 of the 62 table lines have a named equivalent: `dock.tilesize` (316), `dock.autohide` (341), `dock.show_recents` (375), `finder.show_all_files` (224), `finder.show_status_bar` (233), `finder.show_pathbar` (236), `finder.sort_folders_first` (239), `finder.show_extensions_warning` (245), `finder.preferred_view_style` (285), `keyboard.automatic_capitalization` (111), `keyboard.automatic_spelling_correction` (123), `keyboard.press_and_hold` (135), `keyboard.key_repeat` (138), `keyboard.initial_key_repeat` (140). The opt-in lines 364 and 365 match `dock.autohide_delay` and `dock.autohide_time_modifier`. No trackpad line has one. **Decision: the fragment uses no named section.** They cover 14 of 68 keys, so each domain would be split across two tables. A raw value silently beats a named one in the same file. And one addressing rule, `<domain>/<key>`, keeps the adapter free of a name-mapping table.

Commands that are not `defaults write` and cannot move to TOML, by line:

| Lines | Command | New home |
| --- | --- | --- |
| 16 to 27 | computer name prompts | env settings `DOTFILES_MACOS_COMPUTER_NAME` and `DOTFILES_MACOS_LOCAL_HOSTNAME`, or `macos-extras.sh --computer-name` and `--local-hostname` |
| 31 | `osascript` quits System Settings | `macos-extras.sh --before`, failure ignored |
| 34, 38 to 42 | `sudo -v` and its keep-alive | dropped. `sudo` is asked only when a value differs |
| 48 to 61 | `confirm()` and the two knobs | dropped. Each default-yes prompt becomes a switch that is on unless set off. Of the default-no prompts that need sudo, the firewall and turning Time Machine off become switches that are on unless set off (Decision 2: this Mac runs both), and HiDPI a switch that is off unless set on |
| 69, 70, 71 | `sudo scutil --set` | `macos-extras.sh`, when the computer name setting or flag differs from `scutil --get ComputerName` |
| 157, 160, 163, 169 | `sudo pmset -a` | `macos-extras.sh`, guarded |
| 204, 205 | `socketfilterfw` | `macos-extras.sh`, unless `DOTFILES_MACOS_FIREWALL` is set to the empty string (`--firewall` overrides that for one run), and only when the state differs |
| 292, 293, 294 | `xattr` and `chflags nohidden ~/Library` | `macos-extras.sh` |
| 297 | `sudo chflags nohidden /Volumes` | `macos-extras.sh`, guarded |
| 367, 368 | `defaults delete` of the Dock timing keys | dropped. mise never deletes. Documented in Task 3 |
| 468 | `sudo tmutil disable` | `macos-extras.sh`, unless `DOTFILES_MACOS_DISABLE_TIME_MACHINE` is set to the empty string (`--disable-time-machine` overrides that for one run), and only when backups are not already off |
| 535 to 542 | `killall` loop | `macos-extras.sh`, when the apply wrote something |

`systemsetup` appears only in a comment (line 150). No line writes a date or binary data.

## File Structure

| File | Responsibility |
| --- | --- |
| `setup/macos-extras.sh` (create) | Everything macOS that TOML cannot express. Safe to repeat. |
| `setup/tests/macos-extras.sh` (create) | Tests the extras script against stubbed commands. |
| `tilde/.config/mise/conf.d/20-macos.toml` (create) | The 79 declared preferences and the two hooks. |
| `setup/tests/macos-defaults.py` (create) | Self-check: the fragment parses clean under mise, and no declared type contradicts the live one. |
| `bin/set-defaults` (modify) | `mise bootstrap macos defaults apply`, then the extras script. |
| `setup/macos.sh` (delete) | |
| `settings/src/dotfiles_settings/adapters/macos_default.py` (create) | The `macos-default` adapter. |
| `settings/tests/test_macos_default.py` (create) | Adapter tests. |
| `settings/registry.toml` (modify) | 26 `macos-default` entries and 9 `env` entries. |
| `bin/lib/check`, `bin/lib/test-conventions` (modify) | Wire the checks and the executable-bit check for `setup/*.sh`. |
| Docs (modify) | Listed in Task 3. |

`.claude/settings.json` is not touched. The `ask` rule for `mise bootstrap*` is added by A7 in the last phase (spec Decision 7); until then the owner's go-ahead in chat guards the command.

## Decisions this plan makes

- **The fragment uses no named section** (see "Named keys" above).
- **The four groups that used to ask are switches in the extras script, not tables in the fragment** (Decision 9). `DOTFILES_MACOS_SCREENSHOTS`, `DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS`, `DOTFILES_MACOS_TEXTEDIT` and `DOTFILES_MACOS_SOFTWARE_UPDATE` are on unless set to the empty string, which is what A2 writes for a false bool. Unset means on, because the old prompts defaulted to yes. The script reads them as `${VAR-1}` (no colon), and the registry gives each `default = "1"`, the script's own fallback, as A2 defines `default`.
- **The security and per-machine opt-ins are env settings** (Decision 2). `DOTFILES_MACOS_FIREWALL` and `DOTFILES_MACOS_DISABLE_TIME_MACHINE` are switches that are on unless set to the empty string, read as `${VAR-1}` like the group switches, with `default = "1"`: the owner does not use Time Machine and runs the firewall with stealth mode, and this Mac already matches both. `DOTFILES_MACOS_HIDPI` stays off unless set to `1`, read as `${VAR:-}`. `DOTFILES_MACOS_COMPUTER_NAME` and `DOTFILES_MACOS_LOCAL_HOSTNAME` are text, empty meaning "leave the name alone".
- **A flag wins over its setting, in the direction it can.** `--firewall`, `--disable-time-machine` and `--hidpi` turn a switch on for one run even when its setting is off, and `--computer-name` and `--local-hostname` replace the setting's text. No `--no-*` flag is added: an empty variable on the command line already turns an on-by-default switch off for one run (`DOTFILES_MACOS_DISABLE_TIME_MACHINE= set-defaults`), because `set-defaults` passes its environment to the extras script unchanged.
- **The default disables Time Machine, and the docs say so where a fork reads first.** With nothing set, `set-defaults` (and a plain `mise bootstrap` run by hand) runs `sudo tmutil disable` on any Mac whose backups are on. That stops all Time Machine backups. The setting's help text, `set-defaults`'s header, `README.md` and `setup/README.md` each say that a Mac which uses Time Machine must switch `macos.disable_time_machine` off before its first `set-defaults`.
- **A sudo opt-in runs sudo only when the Mac's state differs**, read without sudo first. Because two of them are on by default, "differs" now includes a Mac where nothing is set: a Mac whose firewall or stealth mode is off, or whose `AutoBackup` is not `0` (including a Mac where the key cannot be read), asks for a password on its first `set-defaults`, and then no more once the write took. This Mac matches both and asks for none. Under the `post-defaults` hook the same settings apply, so a `mise bootstrap` run by hand also asks on such a Mac. Setup never runs the hook (Decision 1).
- **Turning an opt-in off changes nothing on the Mac.** The old prompts' "no" left the state as it was. The settings say so in their help text.
- **The nine env settings sit in their own section, "macOS (this Mac)"**, apart from the tracked "macOS (tracked in git)" section, because they are stored in the git-ignored override file.


## Review Focus

1. A key the UI writes is also declared in `config.local.toml`, which outranks the fragment. Expected: the write fails with a message that names `config.local.toml`, and does not report success. Test in Task 5.
2. A string value holds `"`, `\` or `#`. Expected: the fragment still parses and holds the exact string. Test in Task 5.
3. `mise bootstrap` runs inside Terminal.app. Expected: the hook does not kill the terminal that is running the bootstrap. Test in Task 1.
4. The fragment is not in git `HEAD` (a tarball checkout, or before the first commit). Expected: `read` works with `source` `SEED` and `seed` `None`, and `reset` fails with a clear message. Test in Task 5.
5. `status --json` prints `{}` (the fragment is missing, or the config has no macOS section). Expected: `read` returns `UNSET`, not a traceback. Test in Task 5.
6. A group switch set off in the UI arrives as an empty, set variable. Expected: the group is skipped, while an unset variable applies it. A `${VAR:-1}` (with a colon) would apply it in both cases. Test in Task 1.
7. A sudo opt-in is on, from its setting or by default (unset), and the Mac already matches it. Expected: no `sudo` call at all, so a repeat `set-defaults` or a `mise bootstrap` hook run does not ask for a password. Test in Task 1.
8. `DOTFILES_MACOS_DISABLE_TIME_MACHINE` or `DOTFILES_MACOS_FIREWALL` is unset, empty, or `1`. Expected: unset and `1` act when the Mac differs, empty never calls `tmutil` or `socketfilterfw --set*`. A `${VAR:-}` read would leave them off by default, and a `${VAR:-1}` read would make the UI's off do nothing, which for Time Machine means backups stopped on a Mac whose owner switched the setting off. HiDPI keeps the opposite reading: unset does nothing. Test in Task 1, and the consistency block of Task 6 ties each `default = "1"` to a `${KEY-1}` read in the script.

---

### Task 1: The extras script

**Files:**
- Create: `setup/macos-extras.sh`
- Create: `setup/tests/macos-extras.sh`
- Modify: `bin/lib/check` (after the `setup/tests/firefox-dev-path.sh` line)
- Modify: `bin/lib/test-conventions` (tracked `setup/*.sh` files are executable)

**Interfaces:**
- Produces: `setup/macos-extras.sh [--before] [--restart] [--computer-name NAME] [--local-hostname HOST] [--hidpi] [--firewall] [--disable-time-machine]`, committed with mode 755. Exit 0 on success, 2 on an unknown flag. Snapshot file: `${TMPDIR:-/tmp}/dotfiles-macos-defaults-before`, the `status --json` output taken by `--before`.
- Produces: nine environment variables, registered as `env` settings in Task 6. They are variables, not only flags, because a hook's command line is fixed and the settings UI writes variables.
  - Group switches, read as `${VAR-1}`: on unless set to the empty string. `DOTFILES_MACOS_SCREENSHOTS`, `DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS`, `DOTFILES_MACOS_TEXTEDIT`, `DOTFILES_MACOS_SOFTWARE_UPDATE`.
  - Security switches, read as `${VAR-1}` like the groups: on unless set to the empty string. `DOTFILES_MACOS_FIREWALL`, `DOTFILES_MACOS_DISABLE_TIME_MACHINE`.
  - Opt-in switch, read as `${VAR:-}`: on when non-empty. `DOTFILES_MACOS_HIDPI`.
  - The flags `--firewall`, `--disable-time-machine` and `--hidpi` turn the same switch on for one run, whatever its variable holds.
  - Text: `DOTFILES_MACOS_COMPUTER_NAME` and `DOTFILES_MACOS_LOCAL_HOSTNAME`, empty meaning unset. `--computer-name` and `--local-hostname` replace them for one run.
- Produces: the `bin/lib/test-conventions` check that every tracked `setup/*.sh` has mode 755. Later plans that add a setup script rely on it.

Behaviour, in this order. Each row keeps the comment the old script had beside that command.

| Trigger | Action | Guard that makes it safe to repeat |
| --- | --- | --- |
| not Darwin | `exit 0` | |
| `--before` | Quit System Settings: `osascript -e 'tell application "System Settings" to quit' > /dev/null 2>&1 \|\| true`. A failure (a CI runner with no Apple Events permission) must not fail the hook and stop a bootstrap. Then save the preferences as they are: `mise bootstrap macos defaults status --json > "$snapshot" 2> /dev/null \|\| rm -f "$snapshot"`. Then exit 0, doing nothing else. | |
| every other run | The script sets `trap 'rm -f "$snapshot"' EXIT` before it parses its flags, and the `--before` branch clears it with `trap - EXIT`. The snapshot is used once and never survives another run, whatever fails. | |
| `${DOTFILES_MACOS_SCREENSHOTS-1}` is non-empty | the five `com.apple.screencapture` writes (old lines 180 to 188): `location -string "$HOME/Desktop"`, `type -string png`, `disable-shadow -bool true`, `showsCursor -bool true`, `name -string Shot` | plain overwrite |
| `${DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS-1}` is non-empty | `defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true` (463) | plain overwrite |
| `${DOTFILES_MACOS_TEXTEDIT-1}` is non-empty | the three `com.apple.TextEdit` writes (495 to 497, `-int 0`, `-int 4`, `-int 4`) | plain overwrite |
| `${DOTFILES_MACOS_SOFTWARE_UPDATE-1}` is non-empty | the four `com.apple.SoftwareUpdate` writes (506 to 512): `AutomaticCheckEnabled -bool true`, `ScheduleFrequency -int 1`, `AutomaticDownload -int 1`, `CriticalUpdateInstall -int 1`. Keep the comment that the last two are integers, not booleans. | plain overwrite |
| always | `defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"` (217) | plain overwrite |
| always | `defaults write com.apple.helpviewer DevMode -bool true` (108), `defaults write com.apple.Preview ApplePersistenceIgnoreState YES` (522) | plain overwrite |
| always | the three `~/Library` lines (292 to 294), unchanged | already tolerant |
| always | for each of `lidwake 1`, `disksleep 10`, `womp 0`, `hibernatemode 3`: read `pmset -g custom \| awk -v k="$key" '$1 == k { print $2 }' \| sort -u`. Run `sudo pmset -a "$key" "$want"` only when that output is non-empty and is not exactly `$want`. | A key the Mac does not report is skipped (`lidwake` on this Mac). |
| always | `sudo chflags nohidden /Volumes` | only when `ls -ldO /Volumes` contains `hidden` |
| a computer name, from `--computer-name NAME` or else `DOTFILES_MACOS_COMPUTER_NAME` | the three `sudo scutil --set` lines and the `sudo defaults write ... NetBIOSName` line (69 to 72). The host name comes from `--local-hostname`, else `DOTFILES_MACOS_LOCAL_HOSTNAME`, else the old line 22 expression applied to the name. | only when `scutil --get ComputerName` differs from the name |
| `--hidpi` or `DOTFILES_MACOS_HIDPI` non-empty | `sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true` (194) | only when `defaults read` of that key is not `1` (it fails, domain not found, on this Mac) |
| `--firewall`, or `${DOTFILES_MACOS_FIREWALL-1}` non-empty (on by default) | the two `socketfilterfw` lines (204, 205), the tool found as `fw=$(command -v socketfilterfw \|\| echo /usr/libexec/ApplicationFirewall/socketfilterfw)` so the test can put a stub on `PATH` | `--setglobalstate on` only when `"$fw" --getglobalstate` does not contain `State = 1`, and `--setstealthmode on` only when `"$fw" --getstealthmode` does not contain `mode is on`. Both reads need no sudo. |
| `--disable-time-machine`, or `${DOTFILES_MACOS_DISABLE_TIME_MACHINE-1}` non-empty (on by default) | `hash tmutil &> /dev/null && sudo tmutil disable` (468). Keep the old comment, and add one: this is on by default and stops all backups, so a Mac that uses Time Machine switches `macos.disable_time_machine` off. | only when `defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup` does not print `0` (a read that fails, the key or the file missing, counts as "not `0`") |
| `--restart`, or the snapshot exists and differs from the status now | The second case is `[ -e "$snapshot" ] && ! mise bootstrap macos defaults status --json 2> /dev/null \| cmp -s - "$snapshot"`. Then `killall "$app" > /dev/null 2>&1 \|\| true` for Activity Monitor, Dock, Finder, NotificationCenter, SystemUIServer, Terminal. Skip Terminal and print a `warn` line when `$TERM_PROGRAM` is `Apple_Terminal`. Then print the old closing line about logout. | |

Why a snapshot and not `status --missing`: drift alone must not restart anything. Two entries differ on this Mac today, and a value macOS keeps rewriting would otherwise kill Finder and the Dock on every bootstrap. The status changes between `--before` and the later run only when the apply wrote a preference. When the user declines mise's prompt under `mise bootstrap`, the `post-defaults` hook does not run and the snapshot stays in `$TMPDIR` until the next `--before` overwrites it. `bin/set-defaults` removes it with its own trap (Task 3). One limit is left and is accepted: after a declined bootstrap, a run of `setup/macos-extras.sh` by hand compares against that old snapshot.

The four group switches exist because the old script asked before each group (default yes) and `DOTFILES_MACOS_NO=1` declined them, and Decision 9 puts each in the UI. A group's preferences are written only here, because a preference declared in the fragment cannot be switched off (see the classification). A group's writes that change only `status`-invisible preferences restart nothing under the hook; under `set-defaults` the `--restart` path always restarts.

The opt-ins run on every run that is not `--before`, so the same settings apply under `set-defaults` and under a hand-run `mise bootstrap`. Each one reads the Mac's state first and calls `sudo` only when it differs. The firewall and Time Machine switches are on when unset, so on a Mac where nothing is set the first run writes whichever of the two differs (with sudo), and later runs find it matching and call no sudo. To skip one for a single run, set its variable empty on the command line: `DOTFILES_MACOS_DISABLE_TIME_MACHINE= set-defaults`. A read that fails (a domain not found) counts as "differs" and must not stop the script under `set -e`, so each read is `$(... 2> /dev/null || true)`. Turning one off does nothing: the script never turns the firewall or HiDPI off, re-enables Time Machine or renames the Mac back.

The script uses `set -euo pipefail` and inline `info` and `warn` helpers, like the other setup scripts. Under `set -u`, `${VAR-1}` and `${VAR:-}` are both safe on an unset variable. Its header says: what it is, that mise's hooks and `set-defaults` run it, one usage line per flag, one line for the six switches that are on unless set to the empty string (the four groups, the firewall, turning Time Machine off), one for HiDPI and the two names (off or empty unless set), one line warning that by default it turns Time Machine backups off, and that `dotfiles-settings` sets all nine.

- [ ] **Step 1: Write the failing test `setup/tests/macos-extras.sh`**

Follow `setup/tests/codex-config.sh` for the `check "<name>" "<condition>"` helper, the `fails` counter and the exit code. Build a temp dir of stub commands, each appending `<name> <args>` to `$log`, and put it first on `PATH`: `sudo` (logs, then runs nothing), `defaults` (for `read`, prints the file `$reads/<last argument>` and exits 1 when it does not exist), `killall`, `osascript`, `scutil` (prints `Old Name` for `--get`), `chflags`, `xattr`, `tmutil`, `socketfilterfw` (prints `${FW_GLOBAL:-Firewall is disabled. (State = 0)}` for `--getglobalstate` and `${FW_STEALTH:-Firewall stealth mode is off}` for `--getstealthmode`), `mise` (logs, then prints the file `$status_out`), and `pmset` (prints the file `$pmset_out` for `-g custom`). Set `HOME` and `TMPDIR` to temp dirs. Before the first `run`, `unset` all nine `DOTFILES_MACOS_*` variables of Task 1, because A1's override cache may export them into the shell that runs `pnpm check`. Assertions:

```bash
# pmset reports the wanted values: no sudo pmset at all
printf ' hibernatemode 3\n womp 0\n disksleep 10\n' > "$pmset_out"
run
check "matching pmset values need no sudo" "! grep -q '^sudo pmset' '$log'"
check "no restart without a snapshot" "! grep -q '^killall' '$log'"

# the four group switches: unset means on
check "screenshots are written when unset" "grep -q 'defaults write com.apple.screencapture location -string $HOME/Desktop' '$log' && grep -q 'defaults write com.apple.screencapture name -string Shot' '$log'"
check "the Time Machine new-disk prompt is suppressed when unset" "grep -q 'defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true' '$log'"
check "TextEdit is written when unset" "grep -q 'defaults write com.apple.TextEdit RichText -int 0' '$log'"
check "Software Update is written when unset" "grep -q 'defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1' '$log'"

# the UI's false is the empty string: each group is left alone, and nothing else is
DOTFILES_MACOS_SCREENSHOTS= DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS= DOTFILES_MACOS_TEXTEDIT= DOTFILES_MACOS_SOFTWARE_UPDATE= run
check "screenshots switched off" "! grep -q 'com.apple.screencapture' '$log'"
check "Time Machine new-disk switch off" "! grep -q 'com.apple.TimeMachine' '$log'"
check "TextEdit switched off" "! grep -q 'com.apple.TextEdit' '$log'"
check "Software Update switched off" "! grep -q 'com.apple.SoftwareUpdate' '$log'"
check "the other writes still happen" "grep -q 'defaults write com.apple.helpviewer' '$log'"

# the UI's true is 1: the same as unset
DOTFILES_MACOS_SOFTWARE_UPDATE=1 run
check "a group switched on is written" "grep -q 'defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true' '$log'"

# unset (the stubs report the firewall off and AutoBackup unreadable): the firewall and Time Machine
# switches act by default (Review Focus 8), HiDPI and the name do not
run
check "the firewall is turned on by default" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -q '^sudo .*socketfilterfw --setstealthmode on$' '$log'"
check "Time Machine is turned off by default" "grep -qx 'sudo tmutil disable' '$log'"
check "HiDPI and the name are left alone by default" "! grep -q 'scutil --set\|windowserver' '$log'"

# the UI's true is 1: the same as unset for the two security switches, and HiDPI and the name act
DOTFILES_MACOS_FIREWALL=1 DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_DISABLE_TIME_MACHINE=1 DOTFILES_MACOS_COMPUTER_NAME="Jason's Mac" run
check "the firewall is turned on" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -q '^sudo .*socketfilterfw --setstealthmode on$' '$log'"
check "HiDPI is turned on" "grep -q '^sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true' '$log'"
check "Time Machine is turned off" "grep -qx 'sudo tmutil disable' '$log'"
check "the Mac is renamed" "grep -qx \"sudo scutil --set ComputerName Jason's Mac\" '$log'"
check "the local hostname is derived" "grep -qx 'sudo scutil --set LocalHostName jason-s-mac' '$log'"

# the Mac already matches: no sudo for the opt-ins, whether on by default or from a setting (Review Focus 7)
echo 1 > "$reads/DisplayResolutionEnabled"; echo 0 > "$reads/AutoBackup"
export FW_GLOBAL='Firewall is enabled. (State = 1)' FW_STEALTH='Firewall stealth mode is on'
DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_COMPUTER_NAME='Old Name' run
check "a matching Mac needs no sudo for the default-on opt-ins" "! grep -q '^sudo \(.*socketfilterfw\|tmutil\|scutil\|defaults\)' '$log'"
DOTFILES_MACOS_FIREWALL=1 DOTFILES_MACOS_HIDPI=1 DOTFILES_MACOS_DISABLE_TIME_MACHINE=1 DOTFILES_MACOS_COMPUTER_NAME='Old Name' run
check "a matching Mac needs no sudo for the opt-ins set to 1" "! grep -q '^sudo \(.*socketfilterfw\|tmutil\|scutil\|defaults\)' '$log'"
unset FW_GLOBAL FW_STEALTH
rm -f "$reads/DisplayResolutionEnabled" "$reads/AutoBackup"

# the UI's false for an opt-in, and an empty name, do nothing, on a Mac that differs (Review Focus 8)
DOTFILES_MACOS_FIREWALL= DOTFILES_MACOS_DISABLE_TIME_MACHINE= DOTFILES_MACOS_HIDPI= DOTFILES_MACOS_COMPUTER_NAME= run
check "an opt-in switched off does nothing" "! grep -q 'socketfilterfw --set\|tmutil\|scutil --set\|windowserver' '$log'"

# a flag wins over its setting for one run
DOTFILES_MACOS_FIREWALL= DOTFILES_MACOS_DISABLE_TIME_MACHINE= run --firewall --disable-time-machine
check "a flag turns a switched-off opt-in on" "grep -q '^sudo .*socketfilterfw --setglobalstate on$' '$log' && grep -qx 'sudo tmutil disable' '$log'"
DOTFILES_MACOS_COMPUTER_NAME='From Setting' run --computer-name 'From Flag' --local-hostname custom-host
check "the flag's name wins" "grep -qx 'sudo scutil --set ComputerName From Flag' '$log' && grep -qx 'sudo scutil --set LocalHostName custom-host' '$log'"

# one value differs: exactly that key is set, and an unreported key is skipped
printf ' hibernatemode 3\n womp 0\n disksleep 0\n' > "$pmset_out"
run
check "a differing value is set" "grep -qx 'sudo pmset -a disksleep 10' '$log'"
check "only that one" "[ \"\$(grep -c '^sudo pmset' '$log')\" = 1 ]"
check "an unreported key is skipped" "! grep -q 'lidwake' '$log'"

# --before: saves the status, and nothing else runs
snapshot="$TMPDIR/dotfiles-macos-defaults-before"
echo '{"state": "differs"}' > "$status_out"
run --before
check "--before saves the status" "cmp -s '$snapshot' '$status_out'"
check "--before quits System Settings" "grep -q '^osascript' '$log'"
check "--before writes nothing" "! grep -q '^defaults write' '$log'"

# drift that the apply did not touch (a declined prompt, a value macOS rewrites) restarts nothing
run
check "an unchanged status restarts nothing" "! grep -q '^killall' '$log'"
check "the snapshot is removed" "[ ! -e '$snapshot' ]"

# the apply wrote something: the status changed after --before
run --before
echo '{"state": "set"}' > "$status_out"
run
check "a changed status restarts the Dock" "grep -qx 'killall Dock' '$log'"
check "the snapshot is removed again" "[ ! -e '$snapshot' ]"

# a failing step still removes the snapshot
run --before
run --nope
check "a failed run leaves no snapshot" "[ ! -e '$snapshot' ]"

# osascript failing (no Apple Events permission) does not fail --before
OSASCRIPT_RC=1 run --before
check "--before survives a failing osascript" "[ \$rc = 0 ] && [ -e '$snapshot' ]"
rm -f "$snapshot"

# Terminal.app must not kill itself
TERM_PROGRAM=Apple_Terminal run --restart
check "Terminal.app is spared from inside Terminal.app" "! grep -qx 'killall Terminal' '$log' && grep -qx 'killall Finder' '$log'"

run --nope
check "an unknown flag exits 2" "[ \$rc = 2 ]"
```

`run` truncates `$log`, runs `"$repo/setup/macos-extras.sh" "$@" > /dev/null 2>&1` and stores the exit code in `$rc`. It runs the script directly, not through `bash`, the way the hooks do, so a missing mode bit fails every check. The `osascript` stub exits with `${OSASCRIPT_RC:-0}`.

- [ ] **Step 2: Run it to see it fail**

Run: `bash setup/tests/macos-extras.sh`
Expected: `FAIL` on every check that expects a logged command, exit 1 (the script does not exist).

- [ ] **Step 3: Write `setup/macos-extras.sh`** from the behaviour table. Do not make it executable yet.

- [ ] **Step 4: Run the test to see the mode bit matter**

Run: `bash setup/tests/macos-extras.sh`
Expected: the same `FAIL` lines, exit 1. The test runs the script directly and the shell answers `Permission denied`.

- [ ] **Step 5: Add the executable-bit check to `bin/lib/test-conventions` and see it fail**

Add after the `for s in sysup set-defaults` loop:

```bash
# Hooks and setup.sh run these directly, and a test that runs `bash "$script"` cannot see a missing mode bit.
# :(glob) keeps * from crossing a slash, so setup/tests/*.sh (run with bash) is not matched.
notexec=$(git ls-files -s ':(glob)setup/*.sh' | awk '$1 != "100755" { print $4 }')
[ -z "$notexec" ] || fail "setup scripts must be executable (chmod +x): $notexec"
```

Add the clause "that every setup/*.sh is executable" to the list in the file's header comment. The check reads the index, so stage the file first.

Run: `git add setup/macos-extras.sh && bash bin/lib/test-conventions`
Expected: `FAIL: setup scripts must be executable (chmod +x): setup/macos-extras.sh`, exit 1.

- [ ] **Step 6: Make it executable and run both again**

Run: `chmod +x setup/macos-extras.sh && git add setup/macos-extras.sh && bash bin/lib/test-conventions && bash setup/tests/macos-extras.sh`
Expected: no `FAIL` line from the first, every line `ok` from the second, exit 0.

Run: `git ls-files -s setup/macos-extras.sh`
Expected: the line starts with `100755`.

- [ ] **Step 7: Wire it into `bin/lib/check`**

Add after the `firefox-dev-path.sh` line:

```bash
# setup/macos-extras.sh against stubbed sudo, pmset, defaults, socketfilterfw and killall (nothing is changed)
bash setup/tests/macos-extras.sh > /dev/null
```

- [ ] **Step 8: Run the gate**

Run: `pnpm check`
Expected: exit 0.

- [ ] **Step 9: Commit**

```bash
git add setup/macos-extras.sh setup/tests/macos-extras.sh bin/lib/check bin/lib/test-conventions
git commit -m "Add the macOS extras script for what TOML cannot express"
```

### Task 2: The preferences fragment

**Files:**
- Create: `tilde/.config/mise/conf.d/20-macos.toml`

**Interfaces:**
- Consumes: `setup/macos-extras.sh` and its `--before` flag (Task 1).
- Produces: 68 keys under `[bootstrap.macos.defaults."<domain>"]` in 9 domains, 11 `[[bootstrap.macos.defaults_entries]]`, and `[bootstrap.hooks]` with `pre-defaults` and `post-defaults`. Later tasks address a table key as `<domain>/<key>`.

`~/.config/mise` is a symlink into this repo, so the file is live the moment it exists. That is why Task 1 comes first: the hooks need the script.

- [ ] **Step 1: Save the coverage script as `/tmp/a3-coverage.py`**

It is throwaway and is not committed. It proves that every `defaults write` line of `setup/macos.sh` is either declared or on one of the two lists.

```python
"""Throwaway: every `defaults write` in setup/macos.sh is declared in 20-macos.toml or listed in EXTRAS/OPT_IN."""
import json, re, shlex, subprocess, sys

EXTRAS = {72, 108, 180, 194, 217, 495, 496, 497, 522,  # sudo, $HOME, sandboxed apps
          182, 184, 186, 188, 463, 506, 508, 510, 512}  # groups behind a UI switch
OPT_IN = {101, 260, 261, 262, 364, 365}  # documented for config.local.toml
status = json.loads(subprocess.run(["mise", "bootstrap", "macos", "defaults", "status", "--json"],
                                   capture_output=True, text=True, check=True).stdout)
declared = {(e["domain"].lower(), e["key"]) for e in status["macos_defaults"]["entries"]}
lines = open(sys.argv[1]).read().splitlines()
seen, missing = 0, []
for n, line in enumerate(lines, 1):
    m = re.match(r"\s*(?:sudo )?defaults (?:-currentHost )?write (.*)", line)
    if not m:
        continue
    seen += 1
    domain, key = shlex.split(m.group(1).rstrip("\\"))[:2]
    keys = [key.replace("${corner}", c) for c in ("tl", "tr", "bl", "br")]
    if n not in EXTRAS | OPT_IN:
        missing += [(n, domain, k) for k in set(keys) if (domain.lower(), k) not in declared]
    elif (domain.lower(), key) in declared:
        missing.append((n, domain, key + " (declared but listed as not moving)"))
print(f"{seen} defaults write lines, {len(status['macos_defaults']['entries'])} declared preferences, {len(missing)} problems")
for p in missing:
    print(" ", p)
sys.exit(1 if missing or seen != 91 else 0)
```

- [ ] **Step 2: Run it to see it fail**

Run: `python3 /tmp/a3-coverage.py setup/macos.sh`
Expected: a `KeyError: 'macos_defaults'` traceback, because no fragment exists and mise prints `{}`.

- [ ] **Step 3: Create `tilde/.config/mise/conf.d/20-macos.toml` with exactly this content**

```toml
# macOS preferences, applied by `set-defaults` (`mise bootstrap macos defaults
# apply`). setup.sh does not apply them: it runs `mise bootstrap --skip
# macos-defaults`. A plain `mise bootstrap` run by hand does apply them and
# runs both hooks at the end of this file. Based on https://mths.be/macos,
# reviewed for macOS 27. Check drift with
# `mise bootstrap macos defaults status`.
#
# One table per preference domain, keyed by the names `defaults read` shows.
# mise's named sections ([bootstrap.macos.dock] and friends) are not used: they
# cover 14 of these keys, would split a domain across two tables, and a raw
# value silently beats a named one in the same file.
#
# Types matter: mise reports a value as set only when the type matches, so
# `1` does not satisfy `true`. Keep each value's type as written here.
# mise never deletes a preference: removing a line leaves the value in place
# until you run `defaults delete <domain> <key>`.
#
# What cannot live here is in setup/macos-extras.sh, which the hooks at the end
# run: sudo writes, $HOME paths (values are not templated), pmset, file flags,
# the sandboxed apps (TextEdit, Preview, Help Viewer), whose preferences mise
# cannot read back without Full Disk Access, and the groups a user can switch
# off in dotfiles-settings (screenshots, Time Machine's new-disk prompt,
# TextEdit, Software Update): mise applies every key declared here, so a key
# that may be left alone cannot be declared.
#
# Security-sensitive and per-machine preferences are not declared here. The
# firewall, HiDPI, Time Machine and computer name are switches in
# dotfiles-settings ("macOS (this Mac)"), applied by the extras script. For the
# rest, opt in on one Mac by declaring them in the git-ignored
# config.local.toml beside config.toml, which outranks this file:
#
#   # Disable the "downloaded from the internet" confirmation (weakens security)
#   [bootstrap.macos.defaults."com.apple.LaunchServices"]
#   LSQuarantine = false
#
#   # Skip disk image (.dmg) verification (faster mounts, weakens security)
#   [bootstrap.macos.defaults."com.apple.frameworks.diskimages"]
#   skip-verify = true
#   skip-verify-locked = true
#   skip-verify-remote = true
#
#   # Dock auto-hide timing: autohide-delay is how long the pointer rests at
#   # the edge before the Dock appears; autohide-time-modifier is the slide
#   # animation's length (0 = none). Both are floats.
#   [bootstrap.macos.defaults."com.apple.dock"]
#   autohide-delay = 0.2
#   autohide-time-modifier = 0.0
#
# config.local.toml can pin another value for a key below, but it cannot say
# "leave this preference alone".

[bootstrap.macos.defaults.NSGlobalDomain]
# --- General UI/UX ---
# Set sidebar icon size to Large
NSTableViewDefaultSizeMode = 3
# Show scroll bars when scrolling
# Possible values: `WhenScrolling`, `Automatic` and `Always`
AppleShowScrollBars = "WhenScrolling"
# Expand save panel by default
NSNavPanelExpandedStateForSaveMode = true
NSNavPanelExpandedStateForSaveMode2 = true
# Expand print panel by default
PMPrintingExpandedStateForPrint = true
PMPrintingExpandedStateForPrint2 = true
# Fill window when double-clicking its title bar
AppleActionOnDoubleClick = "Fill"
# Disable automatic capitalization as it's annoying when typing code
NSAutomaticCapitalizationEnabled = false
# Disable smart dashes as they're annoying when typing code
NSAutomaticDashSubstitutionEnabled = false
# Disable automatic period substitution as it's annoying when typing code
NSAutomaticPeriodSubstitutionEnabled = false
# Disable smart quotes as they're annoying when typing code
NSAutomaticQuoteSubstitutionEnabled = false
# Disable auto-correct
NSAutomaticSpellingCorrectionEnabled = false
# --- Trackpad, keyboard and input ---
# Trackpad: disable swipe between pages (two more keys below)
AppleEnableSwipeNavigateWithScrolls = false
# Disable press-and-hold for keys in favor of key repeat
ApplePressAndHoldEnabled = false
# Set a blazingly fast keyboard repeat rate
KeyRepeat = 1
# Set a shorter delay until key repeat
InitialKeyRepeat = 10
# Set language and text formats (macOS stores the currency code in lower case)
AppleLanguages = ["en-US"]
AppleLocale = "en_US@currency=usd"
AppleMeasurementUnits = "Inches"
AppleTemperatureUnit = "Fahrenheit"
AppleMetricUnits = false
# --- Finder ---
# Finder: show all filename extensions
AppleShowAllExtensions = true
# Enable spring loading for directories
"com.apple.springing.enabled" = true
# Spring loading delay for directories (macOS default: 0.5s)
"com.apple.springing.delay" = 0.5

# Trackpad: disable swipe between pages
[bootstrap.macos.defaults."com.apple.driver.AppleBluetoothMultitouch.trackpad"]
TrackpadThreeFingerHorizSwipeGesture = 2

# Automatically quit printer app once the print jobs complete
[bootstrap.macos.defaults."com.apple.print.PrintingPrefs"]
"Quit When Finished" = true

# Disable the crash reporter
[bootstrap.macos.defaults."com.apple.CrashReporter"]
DialogType = "none"

# (Password-after-sleep lives in System Settings → Lock Screen; the old
# com.apple.screensaver askForPassword keys have had no effect since macOS 13.)

[bootstrap.macos.defaults."com.apple.finder"]
# Open new Finder windows in the home folder
# (other options: "PfDe" Desktop, "PfDo" Documents, "PfLo" custom path)
NewWindowTarget = "PfHm"
# Show icons for hard drives and external disks on the desktop
ShowExternalHardDrivesOnDesktop = true
ShowHardDrivesOnDesktop = true
# Finder: show hidden files by default
AppleShowAllFiles = true
# Finder: show sidebar
ShowSidebar = true
# Finder: show status bar
ShowStatusBar = true
# Finder: show path bar
ShowPathbar = true
# Keep folders on top when sorting by name
_FXSortFoldersFirst = true
# When performing a search, search the current folder by default
FXDefaultSearchScope = "SCcf"
# Disable the warning when changing a file extension
FXEnableExtensionChangeWarning = false
# Use list view in all Finder windows by default
# Four-letter codes for the other view modes: `icnv`, `clmv`, `glyv`
FXPreferredViewStyle = "Nlsv"
# Expand the following File Info panes:
# "General", "More Info", "Open with", "Preview", and "Sharing & Permissions"
FXInfoPanesExpanded = { General = true, MetaData = true, OpenWith = true, Preview = true, Privileges = true }

# Avoid creating .DS_Store files on network or USB volumes
[bootstrap.macos.defaults."com.apple.desktopservices"]
DSDontWriteNetworkStores = true
DSDontWriteUSBStores = true

[bootstrap.macos.defaults."com.apple.dock"]
# Enable highlight hover effect for the grid view of a stack (Dock)
mouse-over-hilite-stack = true
# Set the icon size of Dock items to 38 pixels
tilesize = 38
# Change minimize/maximize window effect
mineffect = "suck"
# Minimize windows into their application's icon
minimize-to-application = true
# Enable spring loading for all Dock items
enable-spring-load-actions-on-all-items = true
# Show indicator lights for open applications in the Dock
show-process-indicators = true
# Group windows by application in Mission Control (the Dock reads
# expose-group-apps; an earlier expose-group-by-app spelling did nothing)
expose-group-apps = true
# Disable icon bouncing
no-bouncing = true
# Automatically hide and show the Dock
autohide = true
# Make Dock icons of hidden applications translucent
showhidden = true
# Don't show suggested and recent applications in Dock
show-recents = false
# Hot corners: all four set to no action.
# (Values: 1 no action, 2 Mission Control, 3 application windows, 4 Desktop,
#  5 start screen saver, 6 disable screen saver, 10 display sleep,
#  12 Notification Center, 13 Lock Screen, 14 Quick Note.)
wvous-tl-corner = 1
wvous-tl-modifier = 0
wvous-tr-corner = 1
wvous-tr-modifier = 0
wvous-bl-corner = 1
wvous-bl-modifier = 0
wvous-br-corner = 1
wvous-br-modifier = 0

# Safari is sandboxed on modern macOS: its preferences live in its container
# and a plain write to com.apple.Safari from a terminal does not reach them.
# Configure Safari in Safari → Settings instead (search suggestions, Develop
# menu, fraud/HTTP warnings, AutoFill).

# Spotlight search categories: set in System Settings → Spotlight. (The old
# com.apple.spotlight `orderedItems` list no longer exists; current macOS
# stores Spotlight settings as DisabledUTTypes/EnabledPreferenceRules.)

[bootstrap.macos.defaults."com.apple.Terminal"]
# Only use UTF-8 in Terminal.app (a string "4", as `defaults write -array 4` wrote)
StringEncodings = ["4"]
# Enable Secure Keyboard Entry in Terminal.app
# See: https://security.stackexchange.com/a/47786/8918
SecureKeyboardEntry = true
# Disable the annoying line marks
ShowLineMarks = 0

[bootstrap.macos.defaults."com.apple.ActivityMonitor"]
# Show the main window when launching Activity Monitor
OpenMainWindow = true
# Visualize CPU usage in the Activity Monitor Dock icon
IconType = 5
# Show all processes, hierarchically
ShowCategory = 102
# Sort Activity Monitor results by CPU usage
SortColumn = "CPUUsage"
SortDirection = 0

# Entries for what a plain table cannot say: a -currentHost preference, or one
# key inside a dictionary that macOS also writes to.

# Trackpad: disable swipe between pages
[[bootstrap.macos.defaults_entries]]
domain = "NSGlobalDomain"
key = "com.apple.trackpad.threeFingerHorizSwipeGesture"
host = "current"
value = 2

# Prevent Photos from opening automatically when devices are plugged in
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.ImageCapture"
key = "disableHotPlug"
host = "current"
value = true

# Enable Stacks view on the desktop
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "DesktopViewSettings"
path = ["GroupBy"]
value = "Kind"

# Enable snap-to-grid for icons on the desktop and in other icon views
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "DesktopViewSettings"
path = ["IconViewSettings", "arrangeBy"]
value = "grid"

[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "FK_StandardViewSettings"
path = ["IconViewSettings", "arrangeBy"]
value = "grid"

[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "StandardViewSettings"
path = ["IconViewSettings", "arrangeBy"]
value = "grid"

# Increase the size of icons on the desktop and in other icon views (a float)
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "DesktopViewSettings"
path = ["IconViewSettings", "iconSize"]
value = 48.0

[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "FK_StandardViewSettings"
path = ["IconViewSettings", "iconSize"]
value = 48.0

[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "StandardViewSettings"
path = ["IconViewSettings", "iconSize"]
value = 48.0

# Spotlight search shortcut: none (frees ⌘Space for Raycast). The values are
# strings because `defaults write -dict-add` with a plist literal wrote strings.
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.symbolichotkeys"
key = "AppleSymbolicHotKeys"
path = ["64"]
value = { enabled = "0", value = { parameters = ["65535", "49", "1048576"], type = "standard" } }

# Menu Bar Spotlight shortcut: none
[[bootstrap.macos.defaults_entries]]
domain = "com.apple.symbolichotkeys"
key = "AppleSymbolicHotKeys"
path = ["65"]
value = { enabled = "0", value = { parameters = ["65535", "49", "1572864"], type = "standard" } }

# These two hooks run under `mise bootstrap` when its macos-defaults part runs,
# not under `mise bootstrap macos defaults apply` (set-defaults calls the script
# itself) and not under `mise bootstrap --skip macos-defaults` (setup.sh).
# {{ config_root }} is $HOME for a global config, so the repo is found through
# $DOTFILES (tilde/.zshenv) or the ~/dotfiles compatibility symlink.
[bootstrap.hooks]
# Quits System Settings, which would overwrite the values, and saves the
# status so the apps restart only when the apply wrote something
pre-defaults = '"${DOTFILES:-$HOME/dotfiles}/setup/macos-extras.sh" --before'
post-defaults = '"${DOTFILES:-$HOME/dotfiles}/setup/macos-extras.sh"'
```

- [ ] **Step 4: Run the coverage script**

Run: `python3 /tmp/a3-coverage.py setup/macos.sh`
Expected: `91 defaults write lines, 79 declared preferences, 0 problems`, exit 0.

To regenerate the mapping after any edit to the fragment, rerun this command. A line number in `EXTRAS` or `OPT_IN` that is also declared, or a line in neither place, is printed as a problem.

- [ ] **Step 5: Confirm mise parses it with no warning**

Run: `mise bootstrap macos defaults status --json 2>&1 > /dev/null | grep -c WARN`
Expected: `0`.

- [ ] **Step 6: Check every type against the live system (the integer-is-not-a-boolean trap)**

mise reports `set` only when the live type equals the declared type, so the state column is the first check.

Run: `mise bootstrap macos defaults status --json | jq -r '.macos_defaults.entries | group_by(.state)[] | "\(.[0].state) \(length)"'`
Expected on this Mac: `differs 2` and `set 77`. No `unset`.

Run: `mise bootstrap macos defaults status --json | jq -r '.macos_defaults.entries[] | select(.state != "set") | [.domain, .key, (.path | tostring)] | @tsv'`
Expected: `com.apple.finder DesktopViewSettings ["IconViewSettings","arrangeBy"]` and `com.apple.symbolichotkeys AppleSymbolicHotKeys ["64"]`. Any other row is a wrong value or a wrong type. Fix the fragment, not the Mac.

Then compare each top-level key with `defaults read-type` directly:

```bash
mise bootstrap macos defaults status --json \
  | jq -r '.macos_defaults.entries[] | select(.path == null) | [.host, .domain, .key, (.value | type)] | @tsv' \
  | while IFS=$'\t' read -r host domain key want; do
    if [ "$host" = current ]; then live=$(defaults -currentHost read-type "$domain" "$key" 2> /dev/null); else live=$(defaults read-type "$domain" "$key" 2> /dev/null); fi
    live=${live#Type is }
    case "$want:$live" in boolean:boolean | number:integer | number:float | string:string | array:array | object:dictionary) ;; *) echo "MISMATCH $domain $key: TOML $want, live ${live:-unset}" ;; esac
  done
```

Expected: no output.

- [ ] **Step 7: Confirm the hooks render**

Run: `mise bootstrap --dry-run 2>&1 | grep -A1 'defaults hooks'`
Expected: `sh -o errexit -c '"${DOTFILES:-$HOME/dotfiles}/setup/macos-extras.sh" --before'` under `pre-defaults hooks` and the same command without `--before` under `post-defaults hooks`.

- [ ] **Step 8: Run the gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add tilde/.config/mise/conf.d/20-macos.toml
git commit -m "Declare the macOS preferences as mise TOML"
```

### Task 3: Switch `set-defaults`, delete `setup/macos.sh`, rewrite the docs

One commit, because D12 and `.claude/rules/setup.md` require the docs to change with the behaviour.

**Files:**
- Modify: `bin/set-defaults`
- Delete: `setup/macos.sh`
- Modify: `settings/registry.toml` (only if it lists `DOTFILES_MACOS_YES` or `DOTFILES_MACOS_NO`)
- Modify: `README.md`, `setup/README.md`, `docs/macos settings.md`, `docs/macos tips & tricks.md`, `docs/mole.md`, `docs/gui/raycast.md`, `CLAUDE.md`, `bin/CLAUDE.md`, `.claude/rules/macos-defaults.md`

**Interfaces:**
- Consumes: `setup/macos-extras.sh` flags (Task 1), the fragment (Task 2).
- Produces: `set-defaults [--computer-name NAME] [--local-hostname HOST] [--hidpi] [--firewall] [--disable-time-machine]`. It is the only command in the repo that applies macOS preferences. It also honours the nine `DOTFILES_MACOS_*` settings of Task 1, which reach it through the shell it is started from.
- For A6: `setup.sh` must run `mise bootstrap --skip macos-defaults` (Decision 1), which drops the part and both hooks. `--only` and `--skip` cannot be combined, so a user's extra `--skip` list is merged into that one `--skip` argument.
- Not produced here: the `ask` rule `Bash(mise bootstrap*)` and its `test-conventions` assertion. A7 adds both in the last phase (Decision 7).

- [ ] **Step 1: Rewrite `bin/set-defaults`**

Keep the `DOTFILES` resolution lines. Replace the `exec` line with:

```bash
command -v mise > /dev/null || { echo "set-defaults: mise is not installed (run setup.sh first)" >&2; exit 1; }
# A declined prompt or a failed apply must not leave --before's snapshot behind
trap 'rm -f "${TMPDIR:-/tmp}/dotfiles-macos-defaults-before"' EXIT
"$DOTFILES/setup/macos-extras.sh" --before
# Shows the planned writes and asks before making them
mise bootstrap macos defaults apply
# The part command runs no hooks, so the extras script is called here
"$DOTFILES/setup/macos-extras.sh" --restart "$@"
```

Add `set -euo pipefail` after the header. Rewrite the header as a tldr page: description "Apply this repo's macOS preferences and restart the affected apps. By default this turns the firewall and stealth mode on and turns Time Machine backups off; on a Mac that uses Time Machine, run `dotfiles-settings set macos.disable_time_machine off` first.", then one example each for `set-defaults`, `dotfiles-settings set macos.disable_time_machine off` (described as "Keep Time Machine backups on from now on (do this before the first run on a Mac that uses Time Machine)"), `DOTFILES_MACOS_DISABLE_TIME_MACHINE= set-defaults` (described as "Leave Time Machine alone for this run only"), `set-defaults --computer-name "Jason's MacBook Pro"`, `set-defaults --hidpi`, and `dotfiles-settings set macos.software_update off` (described as "Leave Software Update alone from now on; the macOS (this Mac) section of dotfiles-settings has every switch"). `--firewall` and `--disable-time-machine` stay as flags (they turn a switched-off setting on for one run) and are listed in `setup/macos-extras.sh`'s header and `setup/README.md`, not as examples here.

- [ ] **Step 2: Render the header**

Run: `help set-defaults`
Expected: the description with its Time Machine warning, and the six examples, render.

- [ ] **Step 3: Delete the old script and check nothing names it**

```bash
git rm setup/macos.sh
```

Run: `grep -rnI 'macos\.sh\|DOTFILES_MACOS_\(YES\|NO\)' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=completed --exclude-dir=specs . | grep -v 'docs/superpowers/plans/'`
Expected before the doc edits below: hits in `CLAUDE.md:40`, `README.md:8,29,126`, `bin/CLAUDE.md:19`, `setup/README.md:15,114`, `.claude/rules/macos-defaults.md:3`, `docs/mole.md:41`, `docs/gui/raycast.md:9`, `docs/macos tips & tricks.md:109`, `docs/macos settings.md:5,298`. After Step 5: no output. Completed plans and specs keep their history and are excluded.

If `settings/registry.toml` has a `[[setting]]` for `DOTFILES_MACOS_YES` or `DOTFILES_MACOS_NO`, delete both tables.

The `ask` rule for `mise bootstrap*` is not added here: A7 adds it with its assertion in the last phase (spec Decision 7).

- [ ] **Step 4: Rewrite `.claude/rules/macos-defaults.md`**

Replace the whole file with:

```markdown
---
paths:
  - 'tilde/.config/mise/conf.d/20-macos.toml'
  - 'setup/macos-extras.sh'
---

# macOS defaults

- Preferences are declared in `conf.d/20-macos.toml` and applied by `bin/set-defaults` only. `setup.sh` never applies them. A plain `mise bootstrap` run by hand does. `setup/macos-extras.sh` holds only what TOML cannot express: sudo, `$HOME` paths, `pmset`, file flags, sandboxed apps (TextEdit, Preview, Help Viewer), the groups a user can switch off, and the app restarts.
- Security-sensitive and per-machine settings are never declared in the tracked fragment (`setup/tests/macos-defaults.py` fails on two of them). They are an `env` setting the extras script reads, or a table in the git-ignored `config.local.toml`. The firewall and turning Time Machine off are on unless set to the empty string (`${VAR-1}`, `default = "1"`); HiDPI is off unless set (`${VAR:-}`) and the computer name is empty unless set. A setting that needs sudo reads the Mac's state first and calls sudo only when it differs. Turning one off changes nothing. The Time Machine default stops all backups, so every doc that describes `set-defaults` says to switch `macos.disable_time_machine` off first on a Mac that uses Time Machine.
- `config.local.toml` can pin another value but cannot say "leave it as it is", and mise applies every declared key. So a preference group a user may want left alone (screenshots, Time Machine's new-disk prompt, TextEdit, Software Update) is written by the extras script behind a switch that is on unless set to the empty string (`${VAR-1}`, no colon: the settings UI writes `""` for off). Never move such a group back into the fragment.
- Every `DOTFILES_MACOS_*` variable the extras script reads has an `env` entry in `settings/registry.toml`, section "macOS (this Mac)". Add both together.
- Types matter: mise treats `1` and `true` as different values. Before adding a key, run `defaults read-type <domain> <key>` on a Mac where the setting is already on, and verify the domain and key against the current macOS release. Prefer leaving a value at the macOS default over pinning it.
- mise never deletes a preference, never uses sudo and never restarts an app. Removing a line leaves the value in place until `defaults delete <domain> <key>`.
- Values are not templated, and `{{ config_root }}` in a hook is `$HOME`. The `pre-defaults` and `post-defaults` hooks run under `mise bootstrap` when its `macos-defaults` part runs, and not under `mise bootstrap macos defaults apply`, so `bin/set-defaults` calls the extras script itself.
- The extras script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal when the apply wrote something, and always under `set-defaults`. Drift alone restarts nothing. Keep that list and `README.md`'s description of it in sync.
- The settings UI edits the fragment's text in place and writes that one key with `defaults write`. It never applies the whole fragment. Keep one `key = value` per line for scalar keys so that edit stays possible.
- Every `setup/*.sh` is committed executable (`bin/lib/test-conventions` checks the mode). Hooks run the script directly.
```

- [ ] **Step 5: Rewrite the user docs**

Each row quotes the stale text with its current line number. Replace it with the text given.

`README.md`:

| Line | Stale | Replace with |
| --- | --- | --- |
| 8 | "Review `setup/macos.sh` and `setup/Brewfile` before running them on a new machine." | "Review `tilde/.config/mise/conf.d/20-macos.toml`, `setup/macos-extras.sh` and `setup/Brewfile` before running them on a new machine." |
| 29 | "- Sensible [macOS defaults](setup/macos.sh), prompting for a computer name so it's reusable across machines." | "- Sensible [macOS defaults](tilde/.config/mise/conf.d/20-macos.toml), declared as TOML that mise applies and checks for drift." |
| 162 | "Setup already asks for your git identity, commit signing and computer name." | "Setup already asks for your git identity and commit signing." (nothing asks for the computer name any more; it is `macos.computer_name`) |
| "Make it yours" table, after the `setup/Brewfile` row | (new row) | "\| [`settings/registry.toml`](settings/registry.toml) \| `macos.disable_time_machine` and `macos.firewall` default to on, my choice. **If you use Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before `set-defaults`, which otherwise stops all backups.** \|" (do not tell forks to edit `default`: the extras script's `${VAR-1}` is the real default, and Task 6's consistency block requires the two to agree) |
| 126 | "Runs [`setup/macos.sh`](setup/macos.sh): keyboard, trackpad, Finder, Dock and system preferences, with prompts for the security-sensitive and per-machine ones. See [what it changes](setup/README.md#macos). At the end it force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal — so run it from Ghostty, Warp, cmux or iTerm2 rather than Terminal.app. Log out afterwards so key repeat takes effect. Safari isn't configured by it; set Safari up in Safari → Settings." | The paragraph below. |

> Applies the preferences declared in [`20-macos.toml`](tilde/.config/mise/conf.d/20-macos.toml) with `mise bootstrap macos defaults apply`, which lists the planned writes and asks first, then runs [`setup/macos-extras.sh`](setup/macos-extras.sh) for what TOML can't express. See [what it changes](setup/README.md#macos). Nothing prompts any more. The choices the old script asked about are switches in the "macOS (this Mac)" section of [`dotfiles-settings`](settings/README.md): the screenshot, Time Machine new-disk, TextEdit and Software Update groups, the firewall with stealth mode, and turning Time Machine off (all on unless you switch them off), and HiDPI and the computer name (off or empty unless you set them; `set-defaults --hidpi` and `--computer-name "Name"` do the same for one run). **By default `set-defaults` turns Time Machine backups off.** If this Mac (or your fork) uses Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before the first `set-defaults`; the same applies to a plain `mise bootstrap` run by hand. The rest are tables in the git-ignored `config.local.toml`. `mise bootstrap macos defaults status` shows which preferences have drifted. mise never deletes a preference, never uses sudo for one and doesn't restart apps by itself, so the extras script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal (Terminal is spared when you run it from Terminal.app). Log out afterwards so key repeat takes effect. Safari isn't configured by it; set Safari up in Safari → Settings.

`setup/README.md`:

| Line | Stale | Replace with |
| --- | --- | --- |
| 15 | "`macos.sh` is deliberately not part of the run; use `set-defaults`." | "The macOS preferences are deliberately not part of the run; use `set-defaults`." Do not name the `--skip macos-defaults` flag here: `setup.sh` gains it in A6, and A6's documentation task adds it to this sentence. |
| 100 | "Sane macOS defaults, run with `set-defaults`. Based on [~/.macos](https://mths.be/macos) by @mathiasbynens, reviewed for macOS 27." | "Sane macOS defaults, declared in [`20-macos.toml`](../tilde/.config/mise/conf.d/20-macos.toml) and applied with `set-defaults` only. `setup.sh` skips them. A plain `mise bootstrap` run by hand does apply them and runs both hooks. Based on [~/.macos](https://mths.be/macos) by @mathiasbynens, reviewed for macOS 27." |
| 102 | "Prompts for a computer name/local hostname (skippable) so the same script works unmodified across machines. Pre-set `COMPUTERNAME`/`LOCALHOSTNAME` env vars to skip the prompt in non-interactive runs." | "Nothing prompts. Set the computer name in `dotfiles-settings` (`macos.computer_name`, optionally `macos.local_hostname`) or run `set-defaults --computer-name \"Name\"` (with an optional `--local-hostname host`); the next `set-defaults` renames the Mac when the name differs." |
| 104 to 112 | The paragraph "A handful of higher-impact/opinionated settings are asked about interactively…" and its seven bullets | The opt-in list below. |
| 114 | "Non-interactive runs use the defaults above. `DOTFILES_MACOS_NO=1` answers every prompt no. **`DOTFILES_MACOS_YES=1` answers every prompt yes — including the two security-weakening ones and disabling Time Machine**, so avoid it unless that's really what you want." | Delete. |
| 116 | "Applied unconditionally:" | "Always declared in the fragment:" |
| 127 | "At the end the script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal (so run it from another terminal app), and key repeat needs a logout to take effect." | The behaviour list below. |

Opt-in list for lines 104 to 112:

> Higher-impact settings are per-machine choices, because the right answer varies per machine (a work laptop with its firewall or updates managed by MDM, a Mac that backs up with Time Machine):
>
> - Settings in the "macOS (this Mac)" section of `dotfiles-settings`. They need sudo, and `set-defaults` asks for it only when the Mac differs. Turning one off later changes nothing on the Mac. Two are **on unless you switch them off**: `macos.firewall` (firewall and stealth mode) and `macos.disable_time_machine`. **With its default, `set-defaults` stops all Time Machine backups.** A fork, or any Mac that uses Time Machine, must run `dotfiles-settings set macos.disable_time_machine off` (or export `DOTFILES_MACOS_DISABLE_TIME_MACHINE=` in `~/.zsh.local`) before the first `set-defaults` or plain `mise bootstrap`. To skip it for one run only: `DOTFILES_MACOS_DISABLE_TIME_MACHINE= set-defaults`. The rest are off or empty unless you set them: `macos.hidpi` (HiDPI display modes, needs a restart), and the text settings `macos.computer_name` and `macos.local_hostname` (derived from the name when empty). The `set-defaults` flags `--firewall`, `--disable-time-machine` and `--hidpi` turn a switch on for one run even when its setting is off, and `--computer-name` and `--local-hostname` replace the setting for one run.
> - Tables in the git-ignored `tilde/.config/mise/config.local.toml`, which outranks the fragment: disabling the "downloaded from the internet" confirmation and skipping disk image verification (**both weaken security**), and custom Dock auto-hide timing. The fragment's header has the tables to copy.
>
> Four groups the old script asked about are on unless you switch them off in the same section: `macos.screenshots` (save to the Desktop as PNG named "Shot", no window shadow, pointer shown), `macos.time_machine_new_disks` (stop Time Machine offering new disks for backup), `macos.textedit` (plain text and UTF-8) and `macos.software_update` (daily check, background download, security and system data installs). Switch a group off on a Mac whose updates or backups are managed by MDM; `set-defaults` then leaves it as it is. Each setting is the variable `DOTFILES_MACOS_<NAME>`, stored in the git-ignored override file, so an export in `~/.zsh.local` works too (empty means off for a group). The old script's two answer-everything variables are gone.

Behaviour list for line 127 (keep the Safari sentence that precedes it):

> What changed from the old script:
>
> - mise never deletes a preference. Removing a line from the fragment leaves the value in place; run `defaults delete <domain> <key>` to return to the macOS default. The old script deleted the Dock timing keys when you declined them.
> - mise never uses sudo. The settings that need it (`pmset`, unhiding `/Volumes`, the opt-ins) are in `setup/macos-extras.sh`, which asks for sudo only when a value differs.
> - mise doesn't restart apps. The extras script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal when the apply wrote a preference (always under `set-defaults`), and spares Terminal when it is the terminal you ran it from. Key repeat needs a logout to take effect.
> - TextEdit, Preview and Help Viewer are sandboxed, so mise can't read their preferences back; the extras script writes them and `status` doesn't list them. Finder's new-window path holds `$HOME` and is written there too, as are the four switchable groups, since mise applies every preference the fragment declares.
> - `mise bootstrap macos defaults status` lists every declared preference as set, differs or unset. `pnpm check` warns about drift and fails only on a type mismatch.

In the `README.md` paragraph above and in these lists, every sentence agrees on one thing: `set-defaults` is the only command of this repo that applies macOS preferences. Do not write that `setup.sh` or setup applies them.

`docs/macos settings.md`:

| Line | Stale | Replace with |
| --- | --- | --- |
| 5 | "- **(set-defaults)**: [`set-defaults`](../bin/set-defaults) already applies this setting by running [`setup/macos.sh`](../setup/macos.sh). You don't need to change it by hand, and running `set-defaults` again resets it to the value shown." | "- **(set-defaults)**: [`set-defaults`](../bin/set-defaults) already applies this setting from [`20-macos.toml`](../tilde/.config/mise/conf.d/20-macos.toml) or [`setup/macos-extras.sh`](../setup/macos-extras.sh). You don't need to change it by hand, and running `set-defaults` again resets it to the value shown. `mise bootstrap macos defaults status` shows which ones have drifted." |
| 6 | "- **(set-defaults, prompt)**: `set-defaults` asks before it applies this one." | "- **(set-defaults, opt-in)**: applied only when you turn on the named setting in `dotfiles-settings` (or pass the named flag to `set-defaults`), or declare it in `config.local.toml`.\n- **(set-defaults, switch)**: applied unless you turn off the named setting in `dotfiles-settings`." (two bullets) |
| 23, 24 | "(set-defaults, prompt)" twice | "(set-defaults, switch: `macos.firewall`, on by default)" |
| 55 | "(set-defaults, prompt: turns on the automatic check, download, and critical/security installs)" | "(set-defaults, switch: `macos.software_update`; turns on the automatic check, download, and critical/security installs)" |
| 60 | "(set-defaults sets it when you type a computer name at its prompt)" | "(set-defaults, opt-in: `macos.computer_name` and `macos.local_hostname`, or `--computer-name`)" |
| 61 | "(set-defaults, prompt: \"Disable Time Machine backups entirely\"). A separate prompt stops Time Machine asking to use new disks for backup." | "(set-defaults, switch: `macos.disable_time_machine`, on by default). **set-defaults stops all Time Machine backups unless you switch this off first**: on a Mac that uses Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before set-defaults. set-defaults also stops Time Machine asking to use new disks for backup (set-defaults, switch: `macos.time_machine_new_disks`)." |
| 134 | "reveal delay and slide animation stay at macOS defaults unless you opt in to custom values when prompted" | "reveal delay and slide animation stay at macOS defaults unless you declare `autohide-delay` and `autohide-time-modifier` in `config.local.toml`" |
| 170 | "(set-defaults, prompt, default No)" | "(set-defaults, opt-in: `macos.hidpi` or `--hidpi`)" |
| 293 | "- Quick Look text selection" | Delete. The key was removed in commit 893c53a. |
| 298 | "The script also has optional prompts for screenshot preferences, TextEdit plain text, and download quarantine or disk-image verification (both prompts default to No, which keeps the protection on). It runs [`setup/macos.sh`](../setup/macos.sh)." | "It also sets the screenshot preferences and TextEdit plain text, unless you switch off `macos.screenshots` or `macos.textedit` in `dotfiles-settings`. Download quarantine and disk-image verification stay on unless you opt out in `config.local.toml` (see the header of [`20-macos.toml`](../tilde/.config/mise/conf.d/20-macos.toml))." |

Other files:

| File and line | Stale | Replace with |
| --- | --- | --- |
| `docs/macos tips & tricks.md:63` | "`set-defaults` can optionally set the built-in tool to save PNGs" | "`set-defaults` sets the built-in tool (unless `macos.screenshots` is off in `dotfiles-settings`) to save PNGs" |
| `docs/macos tips & tricks.md:109` | "Remove the hot-corner loop in `setup/macos.sh` if you want to keep your own." | "Remove the eight `wvous-` lines from `tilde/.config/mise/conf.d/20-macos.toml` if you want to keep your own." |
| `docs/mole.md:41` | "`setup/macos.sh` already sets both." | "`tilde/.config/mise/conf.d/20-macos.toml` already declares both." |
| `docs/gui/raycast.md:9` | "`set-defaults` (`setup/macos.sh`) turns off" | "`set-defaults` (`20-macos.toml`) turns off" |
| `CLAUDE.md:40` | "Brewfile, per-step scripts, macos.sh (defaults), README.md (per-script docs)" | "Brewfile, per-step scripts, macos-extras.sh (what the macOS TOML can't express), README.md (per-script docs)" |
| `bin/CLAUDE.md:19` | "`set-defaults` (runs `setup/macos.sh`)" | "`set-defaults` (`mise bootstrap macos defaults apply`, then `setup/macos-extras.sh`)" |

`CLAUDE.md` is listed in `.prettierignore`. Edit it by hand and do not format it.

These docs name the nine `dotfiles-settings` ids before Task 6 registers them. The variables they stand for work from Task 1 on, and Task 6 lands in the same phase. Use the ids exactly as Task 6's table spells them.

- [ ] **Step 6: Verify**

Run the `grep` from Step 3.
Expected: no output.

Run: `pnpm check`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add bin/set-defaults .claude/rules/macos-defaults.md README.md setup/README.md 'docs/macos settings.md' 'docs/macos tips & tricks.md' docs/mole.md docs/gui/raycast.md CLAUDE.md bin/CLAUDE.md
git status --short
git commit -m "Apply macOS defaults through mise and drop setup/macos.sh"
```

`git rm` in Step 3 already staged the deletion of `setup/macos.sh`. Add `settings/registry.toml` to the `git add` line only when Step 3 edited it. Before committing, read the `git status --short` output: `agents/claude-settings.json` must show ` M` (unstaged), never `M ` in the first column.

### Task 4: The drift self-check

**Files:**
- Create: `setup/tests/macos-defaults.py`
- Modify: `bin/lib/check` (beside the `agents/catalog` Python tests, same `mise exec python --` form)

**Interfaces:**
- Consumes: the fragment (Task 2), `status --json` shape.
- Produces: `python3 setup/tests/macos-defaults.py`, exit 0 or 1. Plain asserts, prints `ok`, like `agents/catalog/test_build_catalog.py`.

What it asserts, and where:

| # | Assertion | Runs |
| --- | --- | --- |
| 1 | `tomllib` parses the fragment. | everywhere |
| 2 | Neither `com.apple.LaunchServices` nor `com.apple.frameworks.diskimages` is a table in the fragment (the security opt-ins stay out of git). | everywhere |
| 3 | Copy the fragment into `<tmp>/conf.d/`, run `mise bootstrap macos defaults status --json` with `MISE_CONFIG_DIR=<tmp>` and `cwd=<tmp>`. It exits 0 and stderr does not contain `WARN`. | where `mise` is on PATH |
| 4 | The number of entries equals the number of table keys plus the number of `defaults_entries` in the fragment (79 today, computed, not hard-coded). A dropped or shadowed entry fails here. | same |
| 5 | For each entry with `state == "differs"` and `path == null`: the live type from `defaults read-type` (`-currentHost` when `host` is `current`) equals the declared TOML type (`bool` boolean, `int` integer, `float` float, `str` string, `list` array, `dict` dictionary). A mismatch fails and names the key and both types. | not when `$CI` is set |
| 6 | Any remaining `differs` or `unset` is drift, not an error. Print one line to stderr, `check: N macOS preference(s) differ from 20-macos.toml (mise bootstrap macos defaults status)`, and pass. | not when `$CI` is set |

Why 5 and 6 skip on CI: the runner has none of these preferences applied, so there is nothing to compare. Why drift only warns: Finder and System Settings rewrite preferences on their own, and the commit gate runs `pnpm check`. The declared types come from `tomllib`, not from the JSON, because JSON cannot tell `48.0` from `48`.

- [ ] **Step 1: Write `setup/tests/macos-defaults.py`** with one function per row, `fragment_types(path) -> dict[tuple[str, str], type]` for the table keys, and a `main()` that runs them in order.

- [ ] **Step 2: Prove assertions 3 and 5 bite**

Temporarily change `tilesize = 38` to `tilesize = "38"` in the fragment.
Run: `python3 setup/tests/macos-defaults.py`
Expected on this Mac: exit 1 from assertion 5, naming `com.apple.dock tilesize`, `str` and `integer`. Then temporarily add `when = 2026-01-01` under `[bootstrap.macos.defaults."com.apple.dock"]`. Expected: exit 1 from assertion 3. Restore the file with `git checkout tilde/.config/mise/conf.d/20-macos.toml`.

- [ ] **Step 3: Run it clean**

Run: `python3 setup/tests/macos-defaults.py`
Expected: `ok`, exit 0, and before Task 7 the stderr line reporting 2 preferences.

Run: `CI=true python3 setup/tests/macos-defaults.py`
Expected: `ok`, exit 0, no stderr line.

- [ ] **Step 4: Wire it into `bin/lib/check`**

Inside the existing `if command -v mise` block add `mise exec python -- python3 setup/tests/macos-defaults.py > /dev/null`, and in the `else` branch `python3 setup/tests/macos-defaults.py > /dev/null`. Put this comment above the block's new lines:

```bash
# conf.d/20-macos.toml parses clean under mise and no declared type contradicts the live one (drift only warns)
```

- [ ] **Step 5: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add setup/tests/macos-defaults.py bin/lib/check
git commit -m "Check the macOS preferences fragment in pnpm check"
```

### Task 5: The `macos-default` adapter

**Files:**
- Create: `settings/src/dotfiles_settings/adapters/macos_default.py`
- Modify: `settings/src/dotfiles_settings/adapters/__init__.py` (`ADAPTERS`), `settings/src/dotfiles_settings/registry.py` (`KINDS`)
- Test: `settings/tests/test_macos_default.py`
- Modify: `bin/lib/check` (append the new test to A2's `settings_tests` array)

**Interfaces:**
- Consumes (from A2): `model.Setting`, `model.Value`, `model.Source`, `model.SettingsError`, `model.InvalidValue`; `cli.normalize(s, raw) -> str`, which returns `s.true_value` for a true bool and `""` for a false one; `mise.run_mise(args: list[str], stdin: str | None = None) -> str`; `mise.config_dir() -> Path`; `ADAPTERS: dict[str, Adapter]` holding instances; `registry.KINDS`; the optional adapter members `apply(self, settings: list[Setting]) -> list[str]` and the class attribute `write_note: str`. Tests are plain `python3` files with module-level asserts that print `ok`, start with `sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))`, and stub mise with `mise.run_mise = fake`.
- Produces:
  - `fragment_path() -> Path`: `mise.config_dir() / "conf.d" / "20-macos.toml"`.
  - `split_key(setting_key: str) -> tuple[str, str]`: `"com.apple.dock/show-recents"` gives `("com.apple.dock", "show-recents")`. Split on the first `/`.
  - `to_literal(s: Setting, value: str) -> str`: the TOML literal. `bool` gives `true` when `value == s.true_value`, `false` when `value == ""`, else `InvalidValue`. The empty string is what `cli.normalize` passes for false, as for every adapter. `int` gives `str(int(value))`, else `InvalidValue`. `string`, `enum` and `path` give `json.dumps(value)`.
  - `set_key(text: str, domain: str, key: str, literal: str) -> str` and `remove_key(text: str, domain: str, key: str) -> str`: pure text edits, below.
  - `head_text() -> str | None`: the fragment at git `HEAD`, or `None`.
  - `defaults_write(domain: str, key: str, flag: str, arg: str) -> None`: runs `defaults write <domain> <key> <flag> <arg>` and raises `SettingsError` on a non-zero exit. `flag` comes from `FLAGS = {"bool": "-bool", "int": "-int", "string": "-string", "enum": "-string", "path": "-string"}`. `arg` is the TOML literal for `bool` and `int` (`true`, `false`, `44`) and the raw value for the rest. Registry types are all scalar, so the flag is always determined.
  - `class MacosDefaultAdapter` with `read`, `write`, `reset`, `apply`, and `write_note = "Edited tilde/.config/mise/conf.d/20-macos.toml, a tracked file, and wrote that one preference. Commit the file to keep the change."`

Registry `key` for this kind is `<domain>/<preference key>` and addresses `[bootstrap.macos.defaults."<domain>"]`. `defaults_entries` items are not addressable and are not exposed.

**These settings are repo-tracked.** A write edits a tracked file, so it shows in `git diff`. The UI says so three ways: the registry section is named "macOS (tracked in git)", `write_note` is shown after every write and reset, and `Value.source` is `OVERRIDE` exactly while the declared value differs from the committed one.

`read(s)`:

| Situation | `value` | `source` | `seed` | `drift` |
| --- | --- | --- | --- | --- |
| A status entry matches `domain`, `key`, `host == "any"`, `path is None`, and the declared value equals the value at `HEAD` | declared value as a string | `SEED` | the `HEAD` value | `state != "set"` |
| Same, but the value differs from `HEAD`, or the key is absent at `HEAD` | declared value | `OVERRIDE` | the `HEAD` value or `None` | `state != "set"` |
| Same, but `head_text()` is `None` | declared value | `SEED` | `None` | `state != "set"` |
| No matching entry, including a `{}` status | `s.default` or `None` | `DEFAULT` when `s.default` is not `""`, else `UNSET` | `None` | `False` |

The declared value comes from the status entry's `value`. Strings render as: `True` gives `s.true_value`, `False` gives `""`, a number gives `str()`, a string is itself. A false bool reads as `""`, the same string `cli.normalize` produces, so the TUI's "unchanged, do nothing" comparison holds. The domain match is case-insensitive.

`write(s, value)` changes one preference and nothing else. It never runs `mise bootstrap macos defaults apply`: that would reset every preference the user changed by hand and write any `config.local.toml` opt-in. In order:

1. Build the literal, apply `set_key` to the file's text, write the file.
2. `self.read(s)`. When its `value` is not the one written, raise `SettingsError` saying another config file (`config.local.toml`) declares this key and outranks the fragment. Nothing is written to the preference.
3. `defaults_write(domain, key, FLAGS[s.type], arg)`.
4. `self.read(s)` again. When `drift` is true, raise `SettingsError("<domain> <key> did not take the value")`. mise compares value and type, so this is the read-back.
5. Restart the owning app when the domain is in `RESTART = {"com.apple.dock": "Dock", "com.apple.finder": "Finder"}` (`killall`, failure ignored).

`reset(s)`: when `head_text()` is `None`, raise `SettingsError("20-macos.toml is not in git HEAD, so there is no committed value to return to")`. When `HEAD` declares the key, call `write` with that value rendered as `read` renders it. When `HEAD` does not declare it, `remove_key`, write the file, write no preference, and print to stderr: `mise never deletes a preference. Run: defaults delete <domain> "<key>"`.

`apply(settings)`: run `mise.run_mise(["bootstrap", "macos", "defaults", "apply", "--yes"])` once. Return `["macOS preferences applied"]`. This is the one place the adapter applies the whole fragment, for `dotfiles-settings apply macos-default`. It runs no hook and restarts nothing; `set-defaults` is the full path.

`set_key` and `remove_key`. Why a text edit: `mise config set --file` writes the key but deletes every comment in the table it edits, and there is no `mise config unset`. The algorithm:

1. Parse `text` with `tomllib`. Let `old` be the current value at `bootstrap.macos.defaults[domain][key]`, if any.
2. If `old` exists and `type(old)` is not the type of the new literal, raise `InvalidValue` naming both types. This is the integer-is-not-a-boolean guard.
3. Find the header line: `[bootstrap.macos.defaults."<domain>"]`, or `[bootstrap.macos.defaults.<domain>]` when the domain is a bare key. The table's lines run to the next line that starts with `[`.
4. If the key exists: find the one line in the table matching `^(<key>|"<key>")\s*=\s*` and replace everything from the value up to an optional trailing ` # comment` that follows the old literal exactly. If the line does not have that shape (a multi-line value, an inline table), raise `SettingsError("edit 20-macos.toml by hand: <key> is not a one-line scalar")`.
5. If the key does not exist: insert `<key> = <literal>` after the table's last non-blank line. Quote the key when it is not a bare TOML key. If the table does not exist: append a blank line, the header and the key at the end of the file.
6. Postcondition, for both functions: parse the result. The parsed document must equal the original with only that one key set or removed. Otherwise raise `SettingsError` and write nothing.

- [ ] **Step 1: Write the failing test `settings/tests/test_macos_default.py`**

Fixture text used throughout:

```python
FRAGMENT = '''# header comment
[bootstrap.macos.defaults.NSGlobalDomain]
# key repeat why
KeyRepeat = 1
"com.apple.springing.enabled" = true

[bootstrap.macos.defaults."com.apple.dock"]
# size why
tilesize = 38 # trailing why
autohide = true
FXInfo = { General = true }

[[bootstrap.macos.defaults_entries]]
domain = "com.apple.finder"
key = "DesktopViewSettings"
path = ["GroupBy"]
value = "Kind"
'''
```

Assertions (each is one `assert`, grouped by function):

```python
# set_key keeps every comment and touches one line
out = set_key(FRAGMENT, "com.apple.dock", "tilesize", "44")
assert "tilesize = 44 # trailing why" in out and "# size why" in out and "# key repeat why" in out
assert out.replace("tilesize = 44", "tilesize = 38") == FRAGMENT

# quoted keys and bare domains
assert '"com.apple.springing.enabled" = false' in set_key(FRAGMENT, "NSGlobalDomain", "com.apple.springing.enabled", "false")

# a new key lands in its table, a new table lands at the end
out = set_key(FRAGMENT, "com.apple.dock", "show-recents", "false")
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.dock"]["show-recents"] is False
assert out.index("show-recents") < out.index("[[bootstrap.macos.defaults_entries]]")
out = set_key(FRAGMENT, "com.apple.screencapture", "name", '"Shot"')
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.screencapture"] == {"name": "Shot"}

# the type guard: 1 is not true
raises(InvalidValue, lambda: set_key(FRAGMENT, "com.apple.dock", "autohide", "1"))
# not a one-line scalar
raises(SettingsError, lambda: set_key(FRAGMENT, "com.apple.dock", "FXInfo", "true"))

# remove_key drops the line and nothing else
out = remove_key(FRAGMENT, "com.apple.dock", "autohide")
assert "autohide" not in out and "tilesize = 38 # trailing why" in out

# Review Focus 2: a hostile string survives
nasty = 'Sh"ot \\ #1'
s = setting(key="com.apple.screencapture/name", type="string")
out = set_key(FRAGMENT, "com.apple.screencapture", "name", to_literal(s, nasty))
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.screencapture"]["name"] == nasty

# to_literal: a bool arrives the way the CLI passes it, "" for false
b = setting(key="com.apple.dock/autohide", type="bool", true_value="true")
assert to_literal(b, cli.normalize(b, "on")) == "true"
for off in ("false", "off", "no", "0"):
    assert to_literal(b, cli.normalize(b, off)) == "false", off
raises(InvalidValue, lambda: to_literal(b, "yes"))
raises(InvalidValue, lambda: to_literal(b, "false"))
raises(InvalidValue, lambda: to_literal(setting(key="com.apple.dock/tilesize", type="int"), "big"))
```

Adapter tests. The file imports `cli` from the package for `cli.normalize`. Point `MISE_CONFIG_DIR` at a temp dir holding `conf.d/20-macos.toml` with `FRAGMENT`. Stub `mise.run_mise` with a fake that records its args and returns a status JSON built from a list of entries. Stub `macos_default.head_text`, `macos_default.defaults_write` (it appends its four arguments to `written`) and the `killall` call the same way. `status`, and each write test, clear `calls`, `written` and `killed` first.

```python
dock = setting(id="macos.dock.tilesize", key="com.apple.dock/tilesize", type="int")
entry = {"domain": "com.apple.dock", "host": "any", "path": None, "key": "tilesize", "value": 38, "current": "38", "state": "set"}

# read: committed and applied
status([entry]); head(FRAGMENT)
v = adapter.read(dock)
assert (v.value, v.source, v.seed, v.drift) == ("38", Source.SEED, "38", False)

# read: live value differs
status([{**entry, "current": "64", "state": "differs"}])
assert adapter.read(dock).drift is True

# read: uncommitted change
status([{**entry, "value": 44}])
v = adapter.read(dock)
assert (v.value, v.source, v.seed) == ("44", Source.OVERRIDE, "38")

# Review Focus 4: no git HEAD
head(None); status([entry])
v = adapter.read(dock)
assert (v.source, v.seed) == (Source.SEED, None)
raises(SettingsError, lambda: adapter.reset(dock))

# Review Focus 5: empty status
mise.run_mise = lambda args, stdin=None: "{}"
v = adapter.read(dock)
assert (v.value, v.source, v.drift) == (None, Source.UNSET, False)

# a path entry or a current-host entry never matches a table key
status([{**entry, "path": ["x"]}, {**entry, "host": "current"}])
assert adapter.read(dock).source is Source.UNSET

# write: edits the file, writes that one key, restarts the Dock, and never applies the fragment
status([{**entry, "value": 44, "current": "44"}]); head(FRAGMENT)
adapter.write(dock, "44")
assert "tilesize = 44 # trailing why" in fragment_path().read_text()
assert written == [("com.apple.dock", "tilesize", "-int", "44")] and killed == ["Dock"]
assert not any("apply" in c for c in calls)

# write: a bool goes off through the CLI's value, and an enum is a string
hide = setting(id="macos.dock.autohide", key="com.apple.dock/autohide", type="bool", true_value="true")
status([{**entry, "key": "autohide", "value": False, "current": "false"}])
adapter.write(hide, cli.normalize(hide, "off"))
assert "autohide = false" in fragment_path().read_text()
assert written == [("com.apple.dock", "autohide", "-bool", "false")]
assert adapter.read(hide).value == ""
effect = setting(id="macos.dock.mineffect", key="com.apple.dock/mineffect", type="enum", choices=("genie", "scale", "suck"))
status([{**entry, "key": "mineffect", "value": "scale", "current": "scale"}])
adapter.write(effect, "scale")
assert written == [("com.apple.dock", "mineffect", "-string", "scale")]

# write: the preference did not take the value
status([{**entry, "value": 50, "current": "38", "state": "differs"}])
raises(SettingsError, lambda: adapter.write(dock, "50"), contains="did not take")

# Review Focus 1: config.local.toml outranks the fragment, and no preference is written
status([{**entry, "value": 99}])
raises(SettingsError, lambda: adapter.write(dock, "50"), contains="config.local.toml")
assert written == []

# apply is the only whole-fragment path
status([entry])
assert adapter.apply([dock]) == ["macOS preferences applied"]
assert ["bootstrap", "macos", "defaults", "apply", "--yes"] in calls

# reset returns to the committed value
fragment_path().write_text(FRAGMENT.replace("tilesize = 38", "tilesize = 44"))
status([entry]); head(FRAGMENT)
adapter.reset(dock)
assert "tilesize = 38 # trailing why" in fragment_path().read_text()
assert written == [("com.apple.dock", "tilesize", "-int", "38")] and not any("apply" in c for c in calls)

assert ADAPTERS["macos-default"].__class__ is MacosDefaultAdapter and "macos-default" in registry.KINDS
print("ok")
```

`setting(**fields)` builds a `Setting` with the registry defaults for the fields not given. `raises(exc, fn, contains="")`, `status(entries)` and `head(text)` are small helpers in the test file.

- [ ] **Step 2: Run it to see it fail**

Run: `python3 settings/tests/test_macos_default.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.adapters.macos_default'`.

- [ ] **Step 3: Implement `macos_default.py`** from the Interfaces block, the `read` table and the `set_key` algorithm. `head_text()` runs `git -C <repo> show HEAD:<path>` where `<repo>` and `<path>` come from `git -C <dir of fragment_path().resolve()> rev-parse --show-toplevel` and the resolved path relative to it. It returns `None` on any non-zero exit. Register the adapter in `ADAPTERS` and add `"macos-default"` to `registry.KINDS`.

- [ ] **Step 4: Run the test**

Run: `python3 settings/tests/test_macos_default.py`
Expected: `ok`.

- [ ] **Step 5: Try it read-only against the real system**

Run: `python3 -c "import sys; sys.path.insert(0, 'settings/src'); from dotfiles_settings.adapters import macos_default as m; print(m.head_text() is not None, m.fragment_path())"`
Expected: `True` and the path under `~/.config/mise/conf.d/`.

- [ ] **Step 6: Wire the test into `bin/lib/check`, gate, commit**

Append `settings/tests/test_macos_default.py` to the `settings_tests` array A2 defines in `bin/lib/check`. A2's loop runs every file in the array and fails on a missing one, so no other line is needed.

Run: `pnpm check`
Expected: exit 0.

```bash
git add settings/src/dotfiles_settings/adapters/macos_default.py settings/src/dotfiles_settings/adapters/__init__.py settings/src/dotfiles_settings/registry.py settings/tests/test_macos_default.py bin/lib/check
git commit -m "Add the macos-default settings adapter"
```

### Task 6: Registry entries

**Files:**
- Modify: `settings/registry.toml`
- Modify: `settings/tests/test_macos_default.py` (one consistency block)

**Interfaces:**
- Consumes: the adapter (Task 5), the fragment (Task 2), A2's registry loader.

How the 26 were chosen, out of 68 table keys. A preference is exposed when all four hold: it has a control in System Settings or Finder's settings, or `docs/macos settings.md` marks it "(set-defaults)"; its value is a `bool`, `int`, `string` or `enum`, the types `Setting` has (so no float, array or dictionary); for an enum, every choice is named in the old script's comments or the settings pane; and it is not security-sensitive. That leaves out the hot corners (eight integers with opaque codes), the locale strings, the Activity Monitor and Terminal internals, everything in `defaults_entries`, and the opt-ins. The screenshot and Software Update preferences are not in the fragment any more (Decision 9 moved them to the extras script), so they are reached through their group switch, not one by one.

Entries are short, as A2's loader allows: `true_value`, `choices`, `default` and `widget` may be left out. Every entry writes the required fields `id`, `section = "macOS (tracked in git)"`, `label`, `help` (`""` where the table's cell is empty), `kind = "macos-default"`, `key`, `type` and `access = "rw"`. A `bool` adds `true_value = "true"`. An `enum` adds `choices`. No entry sets `default` or `widget`.

| id | label | type | key | help |
| --- | --- | --- | --- | --- |
| `macos.dock.autohide` | Hide the Dock automatically | bool | `com.apple.dock/autohide` | The Dock slides away until the pointer reaches its edge. |
| `macos.dock.tilesize` | Dock icon size | int | `com.apple.dock/tilesize` | In pixels. |
| `macos.dock.show_recents` | Show suggested and recent apps in the Dock | bool | `com.apple.dock/show-recents` | Adds a section of apps you are not keeping in the Dock. |
| `macos.dock.minimize_to_application` | Minimize windows into the app icon | bool | `com.apple.dock/minimize-to-application` | Off puts each minimized window at the right of the Dock. |
| `macos.dock.mineffect` | Minimize animation | enum `genie`, `scale`, `suck` | `com.apple.dock/mineffect` | `suck` is hidden: the settings pane offers only Genie and Scale. |
| `macos.dock.show_process_indicators` | Show a dot under open apps | bool | `com.apple.dock/show-process-indicators` | |
| `macos.dock.no_bouncing` | Stop Dock icons bouncing | bool | `com.apple.dock/no-bouncing` | Apps that want attention no longer bounce. |
| `macos.dock.showhidden` | Dim the icons of hidden apps | bool | `com.apple.dock/showhidden` | |
| `macos.dock.group_apps` | Group windows by app in Mission Control | bool | `com.apple.dock/expose-group-apps` | |
| `macos.finder.show_hidden_files` | Show hidden files | bool | `com.apple.finder/AppleShowAllFiles` | The same as pressing Command-Shift-Period in a Finder window. |
| `macos.finder.show_extensions` | Show all filename extensions | bool | `NSGlobalDomain/AppleShowAllExtensions` | |
| `macos.finder.show_pathbar` | Show the path bar | bool | `com.apple.finder/ShowPathbar` | |
| `macos.finder.show_status_bar` | Show the status bar | bool | `com.apple.finder/ShowStatusBar` | |
| `macos.finder.show_sidebar` | Show the sidebar | bool | `com.apple.finder/ShowSidebar` | |
| `macos.finder.view_style` | Default view | enum `Nlsv`, `icnv`, `clmv`, `glyv` | `com.apple.finder/FXPreferredViewStyle` | List, icon, column, gallery. |
| `macos.finder.folders_first` | Keep folders on top when sorting by name | bool | `com.apple.finder/_FXSortFoldersFirst` | |
| `macos.finder.extension_change_warning` | Warn before changing a file extension | bool | `com.apple.finder/FXEnableExtensionChangeWarning` | |
| `macos.keyboard.key_repeat` | Key repeat rate | int | `NSGlobalDomain/KeyRepeat` | Lower is faster. 1 is faster than the slider's fastest position. Needs a logout. |
| `macos.keyboard.initial_key_repeat` | Delay until repeat | int | `NSGlobalDomain/InitialKeyRepeat` | Lower is shorter. 10 is shorter than the slider's shortest position. Needs a logout. |
| `macos.keyboard.press_and_hold` | Hold a key for accented characters | bool | `NSGlobalDomain/ApplePressAndHoldEnabled` | Off makes a held key repeat. |
| `macos.keyboard.auto_capitalization` | Capitalize words automatically | bool | `NSGlobalDomain/NSAutomaticCapitalizationEnabled` | |
| `macos.keyboard.auto_correct` | Correct spelling automatically | bool | `NSGlobalDomain/NSAutomaticSpellingCorrectionEnabled` | |
| `macos.keyboard.smart_quotes` | Use smart quotes | bool | `NSGlobalDomain/NSAutomaticQuoteSubstitutionEnabled` | Off keeps straight quotes, which code needs. |
| `macos.keyboard.smart_dashes` | Use smart dashes | bool | `NSGlobalDomain/NSAutomaticDashSubstitutionEnabled` | |
| `macos.keyboard.period_substitution` | Add a period with a double space | bool | `NSGlobalDomain/NSAutomaticPeriodSubstitutionEnabled` | |
| `macos.general.scroll_bars` | Show scroll bars | enum `WhenScrolling`, `Automatic`, `Always` | `NSGlobalDomain/AppleShowScrollBars` | |

The nine `env` settings of Task 1 go in their own section, "macOS (this Mac)", because they are stored in the git-ignored override file, not in the tracked fragment. Every entry writes `kind = "env"`, `access = "rw"` and the fields below. A `bool` writes `true_value = "1"`, the value A2's CLI and TUI write for on; off arrives as `""`. `default` is the extras script's own fallback, as A2 defines it: `"1"` for the four group switches, the firewall and turning Time Machine off (the script reads `${VAR-1}`, so unset means on), `""` for HiDPI and the two names. `help` names what `set-defaults` does and that the change applies at its next run.

| id | label | type | default | key | help |
| --- | --- | --- | --- | --- | --- |
| `macos.screenshots` | Apply the screenshot preferences | bool | `"1"` | `DOTFILES_MACOS_SCREENSHOTS` | Save to the Desktop as PNG named Shot, no window shadow, pointer shown. Off leaves them as they are. Applied by the next set-defaults. |
| `macos.time_machine_new_disks` | Stop Time Machine offering new disks | bool | `"1"` | `DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS` | Time Machine stops asking to use each new drive for backups. Off leaves the prompt as it is. Applied by the next set-defaults. |
| `macos.textedit` | Make TextEdit default to plain text | bool | `"1"` | `DOTFILES_MACOS_TEXTEDIT` | New documents are plain text, opened and saved as UTF-8. Off leaves TextEdit as it is. Applied by the next set-defaults. |
| `macos.software_update` | Turn on automatic macOS updates | bool | `"1"` | `DOTFILES_MACOS_SOFTWARE_UPDATE` | Daily check, background download, security and system data installs. Turn off on a Mac whose updates are managed by MDM. Applied by the next set-defaults. |
| `macos.firewall` | Turn on the firewall and stealth mode | bool | `"1"` | `DOTFILES_MACOS_FIREWALL` | On by default. set-defaults asks for your password when the firewall or stealth mode is off. Turn this off on a Mac whose firewall is managed by MDM. Turning it off leaves the firewall as it is. |
| `macos.hidpi` | Offer HiDPI display modes | bool | `""` | `DOTFILES_MACOS_HIDPI` | Needs your password and a restart. Turning this off later leaves the modes on. |
| `macos.disable_time_machine` | Turn off Time Machine backups | bool | `"1"` | `DOTFILES_MACOS_DISABLE_TIME_MACHINE` | On by default: the next set-defaults stops all Time Machine backups on this Mac, and asks for your password when backups are on. If this Mac uses Time Machine, turn this off before running set-defaults. Turning it off later does not turn backups back on: use System Settings. |
| `macos.computer_name` | Computer name | string | `""` | `DOTFILES_MACOS_COMPUTER_NAME` | set-defaults renames the Mac when this differs from its current name, and asks for your password. Empty leaves the name alone. |
| `macos.local_hostname` | Local hostname | string | `""` | `DOTFILES_MACOS_LOCAL_HOSTNAME` | The Bonjour name (name.local), set together with the computer name. Empty derives it from the computer name: lower case, other characters as hyphens. |

What the UI shows for these nine: the value the next `set-defaults` will act on (override, else a `~/.zsh.local` export, else the default), never the Mac's live state. A2's `env` adapter reports `drift` as `False` for every env setting, and its write note ("Open a new shell to pick this up.") applies: `set-defaults` reads the variables from the shell it starts in.

- [ ] **Step 1: Add the failing consistency block to `settings/tests/test_macos_default.py`** (before `print("ok")`)

```python
# every macos-default registry entry is declared in the real fragment with a matching type
repo = Path(__file__).resolve().parents[2]
declared = tomllib.loads((repo / "tilde/.config/mise/conf.d/20-macos.toml").read_text())["bootstrap"]["macos"]["defaults"]
settings = registry.load()
macos = [s for s in settings if s.kind == "macos-default"]
assert len(macos) == 26
for s in macos:
    domain, key = split_key(s.key)
    value = declared[domain][key]
    assert type(value) is {"bool": bool, "int": int, "string": str, "enum": str}[s.type], s.id
    assert s.type != "enum" or value in s.choices, s.id
    assert s.section == "macOS (tracked in git)" and s.access == "rw", s.id
    assert s.type != "bool" or s.true_value == "true", s.id

# every variable the extras script reads is a setting in "macOS (this Mac)", and the reverse
extras = (repo / "setup/macos-extras.sh").read_text()
local = {s.key: s for s in settings if s.section == "macOS (this Mac)"}
assert set(local) == set(re.findall(r"DOTFILES_MACOS_[A-Z_]+", extras)), sorted(local)
on_by_default = {"DOTFILES_MACOS_SCREENSHOTS", "DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS", "DOTFILES_MACOS_TEXTEDIT",
                 "DOTFILES_MACOS_SOFTWARE_UPDATE", "DOTFILES_MACOS_FIREWALL", "DOTFILES_MACOS_DISABLE_TIME_MACHINE"}
for key, s in local.items():
    assert s.kind == "env" and s.access == "rw", key
    assert s.type == "string" or s.true_value == "1", key
    # on unless switched off: the script's ${VAR-1} and the registry default must agree
    assert (s.default == "1") == (key in on_by_default), key
    assert (f"${{{key}-1}}" in extras) == (key in on_by_default), key
assert "${DOTFILES_MACOS_HIDPI:-}" in extras
```

The counts are of this plan's own entries only. No test here counts the whole registry or its kinds. The file imports `re`.

Use A2's real loader call in place of `registry.load()` if its name differs.

- [ ] **Step 2: Run it to see it fail**

Run: `python3 settings/tests/test_macos_default.py`
Expected: `AssertionError` on `len(macos) == 26`.

- [ ] **Step 3: Add the 26 `[[setting]]` tables to `settings/registry.toml`** from the first table above, in that order, under a comment line that names the fragment and the selection rule.

Run: `python3 settings/tests/test_macos_default.py`
Expected: `AssertionError` naming the nine `DOTFILES_MACOS_*` keys, from the `set(local)` line.

- [ ] **Step 4: Add the nine `env` tables** from the second table, in that order, under a comment line that names `setup/macos-extras.sh` as their reader. Write `default` only where it is `"1"`. For example:

```toml
[[setting]]
id = "macos.software_update"
section = "macOS (this Mac)"
label = "Turn on automatic macOS updates"
help = "Daily check, background download, security and system data installs. Turn off on a Mac whose updates are managed by MDM. Applied by the next set-defaults."
kind = "env"
key = "DOTFILES_MACOS_SOFTWARE_UPDATE"
type = "bool"
true_value = "1"
default = "1"
access = "rw"
```

- [ ] **Step 5: Run the tests**

Run: `python3 settings/tests/test_macos_default.py`
Expected: `ok`.

Run: `uv run --project settings dotfiles-settings list --section "macOS (tracked in git)" --json | jq 'length, (map(select(.drift)) | length)'`
Expected: `26` and `0`.

Run: `uv run --project settings dotfiles-settings get macos.dock.tilesize --json | jq -c '[.value, .source, .drift]'`
Expected: `["38","seed",false]` (A2's JSON writes `source` as the lowercase enum value).

Run: `uv run --project settings dotfiles-settings list --section "macOS (this Mac)" --json | jq -c 'map([.setting_id, .value, .source])'`
Expected on a Mac with none of the nine set: the four group switches, `macos.firewall` and `macos.disable_time_machine` read `["…","1","default"]`, and `macos.hidpi`, `macos.computer_name` and `macos.local_hostname` read `["…",null,"unset"]`.

These commands only read. Do not run `set` on these nine here: it writes the live override file, which every new shell then exports. Task 7 Step 5 exercises one.

- [ ] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

```bash
git add settings/registry.toml settings/tests/test_macos_default.py
git commit -m "Expose the macOS preferences and switches in the settings registry"
```

### Task 7: Apply on this Mac and close the phase (needs the user's explicit go-ahead; the user runs it)

These commands change the machine. The user runs them in Ghostty after saying so explicitly. An agent runs none of them, and stops here until the user reports the results.

- [ ] **Step 1: See what will change**

Run: `mise bootstrap macos defaults apply --dry-run`
Expected: `77 value(s) already set` and two planned writes: `DesktopViewSettings["IconViewSettings"]["arrangeBy"] = grid` and `AppleSymbolicHotKeys["64"]`.

- [ ] **Step 2: Apply**

Run: `set-defaults`
Expected: mise lists the two writes and asks. After a yes, the extras script runs and Finder, Dock and the others restart. With none of the nine settings stored, no password prompt comes from the firewall or Time Machine: this Mac already has both on and backups off (measured 2026-11-09). A prompt here means a guard misread the state; note which command asked.

- [ ] **Step 3: Settle whatever macOS writes back**

Run: `mise bootstrap macos defaults status --missing`
Expected: no row. This command is informational and its exit code gates nothing.

If a row is `differs` again after the restart, macOS owns that value. This is likely for the desktop `arrangeBy` (Stacks are on, and the value was `name` after the old script had set `grid`) and possible for hotkey `64` (`enabled` had become an integer). For each such row: delete its `[[bootstrap.macos.defaults_entries]]` block from the fragment, leave a one-line comment saying macOS rewrites it and the date, and rerun the status command. Do not chase a value macOS keeps changing.

- [ ] **Step 4: Check the sandboxed apps were written**

Open TextEdit and choose File → New.
Expected: a plain-text document (Format offers "Make Rich Text").

- [ ] **Step 5: Change one setting through the UI and undo it**

Run: `uv run --project settings dotfiles-settings set macos.dock.tilesize 44 && git diff --stat`
Expected: the Dock redraws larger, Finder and the other apps do not restart, the note about the tracked file prints, and `git diff --stat` lists `tilde/.config/mise/conf.d/20-macos.toml` with 1 line changed.

Run: `uv run --project settings dotfiles-settings reset macos.dock.tilesize && git status --short tilde/.config/mise/conf.d/`
Expected: the Dock returns to 38 and the status command prints nothing.

- [ ] **Step 5a: Switch one group off and back through the UI**

This changes only the git-ignored override file, not a preference.

Run: `uv run --project settings dotfiles-settings set macos.textedit off && zsh -ic 'print -r -- "[${DOTFILES_MACOS_TEXTEDIT-unset}]"'`
Expected: `[]`. A new shell sees the switch as set and empty, which the extras script reads as off.

Run: `uv run --project settings dotfiles-settings reset macos.textedit && zsh -ic 'print -r -- "[${DOTFILES_MACOS_TEXTEDIT-unset}]"'`
Expected: `[unset]`, or `[1]` if `~/.zsh.local` exports it.

- [ ] **Step 6: The phase gate**

Run: `pnpm check && python3 setup/tests/macos-defaults.py; echo $?`
Expected: `0`. Drift prints a warning line and does not fail.

Run: `mise bootstrap status --missing`
This is informational. Read it, and do not require exit 0: an app can rewrite a preference at any time.

- [ ] **Step 7: Commit any settle edits**

```bash
git add tilde/.config/mise/conf.d/20-macos.toml
git commit -m "Stop declaring the preferences macOS rewrites"
```

Skip this step when Step 3 changed nothing.

---

## What Part B's `macos` step needs from this phase

The spec says that step reports drift only. It can rely on:

- `mise bootstrap macos defaults status --json`: `.macos_defaults.entries[]` with `domain`, `host`, `path`, `key`, `value`, `current`, `state` (`set`, `differs`, `unset`). `--missing` exits 1 on any drift, so treat its exit code as information, never as a gate. A config without the fragment prints `{}`.
- Nothing to back up and nothing to move. The old script wrote the same preferences in place.
- Expected drift on a machine set up the old way, so the report can explain it: `AppleLocale` may read `en_US@currency=USD` where the fragment declares the lower-case `usd`, hotkey `64` may hold integers, and the desktop `arrangeBy` may be `name`.
- Leftovers the new method never declares and mise never deletes. The step should list any of these that are present, with the command that removes each: `com.apple.dock autohide-delay`, `com.apple.dock autohide-time-modifier`, `com.apple.LaunchServices LSQuarantine`, and `com.apple.frameworks.diskimages` `skip-verify`, `skip-verify-locked`, `skip-verify-remote`. For example `defaults delete com.apple.dock autohide-delay`.
- The screenshot, Time Machine new-disk and Software Update preferences are not in `status`: the extras script writes them behind switches. The report cannot show drift for them.
- The dead knobs `DOTFILES_MACOS_YES` and `DOTFILES_MACOS_NO`, and the old prompt variables `COMPUTERNAME` and `LOCALHOSTNAME`. If `~/.zsh.local` exports any of them, the `env` step should say they no longer do anything, and point the last two at `macos.computer_name` and `macos.local_hostname`.
- The fix for drift is `set-defaults`. The migration script prints that and does not run it.
- `set-defaults` now turns Time Machine backups off unless `macos.disable_time_machine` is switched off, where the old script only did so after a "yes" (default No). A Mac set up the old way that kept its backups loses them on its next `set-defaults`. When `defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup` prints something other than `0` (or `tmutil destinationinfo` lists a destination) and `DOTFILES_MACOS_DISABLE_TIME_MACHINE` is unset, the step should say so and give `dotfiles-settings set macos.disable_time_machine off`. The same holds, less harmfully, for the firewall switch on a Mac whose firewall is off.

## Self-review notes

- Spec coverage for A3: the non-sudo `defaults write` lines move (Task 2), the sudo and non-`defaults` commands move to `setup/macos-extras.sh` run by a `post-defaults` hook (Tasks 1 and 2), `setup/macos.sh` and both knobs are deleted (Task 3), the adapter (Task 5) and registry entries (Task 6) exist, the Documentation table's four files are rewritten (Task 3), and the phase gate (`pnpm check` and the self-check) runs in Task 7.
- Decisions coverage: 1 (setup never applies; the docs say `set-defaults` is the only applier, and A6 writes `--skip macos-defaults`), 2 (five env settings, the firewall and turning Time Machine off on by default and HiDPI and the names off, each tested unset, empty and `1`, with the Time Machine warning in the help text, the `set-defaults` header, `README.md`, `setup/README.md` and `docs/macos settings.md`; Tasks 1, 3 and 6), 7 (no permission rule in this plan, Task 3 points to A7), 9 (four group switches, Tasks 1 and 6, each tested on, off and unset).
- Where this plan differs from the spec's wording: the spec's first draft counted 87 `defaults write` lines and 85 non-sudo ones. The file has 91 and 89, and the spec now says 91. Of the 89, 67 are declared (plus 6 that were `PlistBuddy`, for 79 entries), 6 become opt-ins and 16 go to the extras script, for the reasons in the classification. The spec's A3 paragraph now gives the same 79, 18 and 6.
- `setup.sh` never applies macOS preferences. A6 passes `--skip macos-defaults`; this plan's docs already say so, and they are true only once A6 lands that line. Until then nothing in the repo runs `mise bootstrap`.
- A UI write touches one preference (`defaults write`), never the whole fragment.
- Task 1's test covers every opt-in from its setting and from a flag, with the Mac differing and matching. The firewall tool is looked up on `PATH` first so a stub can stand in. With the firewall and Time Machine switches on by default, the guards decide whether a default run asks for sudo, so their limits matter more than when the switches were opt-in. What each guard does: it writes when the read does not show the "already done" state, and an unreadable state counts as "differs". So an unknown state leads to a sudo write by default; that write is the action the setting asks for, and the cost of a wrong read is a password prompt on every run, not a wrong setting. Measured on this Mac: the "on" wording (`State = 1`, `mode is on`), `AutoBackup = 0`, no Time Machine destination, block-all disabled and reported by `--getblockall`. Not verified on a real Mac:
  - That `sudo tmutil disable` sets `AutoBackup` to `0`. If it does not, every `set-defaults` on a Mac that had backups on asks for a password again. Settles it: on a Mac or CI runner with backups on, `defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup` before and after `sudo tmutil disable`.
  - What `AutoBackup` reads on a fresh Mac that never configured Time Machine. If the key is missing, the first default run calls `sudo tmutil disable` there (harmless, one prompt). Settles it: the same `defaults read` on the fresh-install CI runner.
  - The `socketfilterfw --getglobalstate` wording when the firewall is off or in another state (a block-all state shown here, if one exists). Any wording without `State = 1` leads to `--setglobalstate on`. Settles it: `--getglobalstate` on a Mac with the firewall off, and with "Block all incoming connections" on.
  - What `--setglobalstate on` does when the firewall is managed by an MDM profile. If the write fails, `set -e` stops the extras script. The help text tells such a Mac to switch `macos.firewall` off. Settles it: a run on an MDM-managed Mac.
- Not verified: that `mise bootstrap` passes the override file's `[env]` to the `post-defaults` hook. If it does not, a hand-run `mise bootstrap` sees only the shell's exports, which A1's cache already holds, so the result is the same in a zsh-started run. If it does, a stored override value beats a one-run `VAR=` prefix under the hook (not under `set-defaults`, which calls the extras script itself). Settles it: in a scratch `MISE_CONFIG_DIR` whose only content is an `[env]` override and a `post-defaults` hook that runs `env`, a `mise bootstrap` run by the owner (Global Constraints: an agent runs `mise bootstrap` only with `--dry-run`, which prints hooks without running them).
