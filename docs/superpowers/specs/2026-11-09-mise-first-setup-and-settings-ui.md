# Mise-first setup and a settings UI

Date: 2026-11-09. Status: approved for planning. Plans built on this spec are listed in [Plans](#plans).

The eight plans were written against the first draft of this spec and tested its claims in scratch directories. Where they proved the draft wrong, this text was corrected. [Corrections from planning](#corrections-from-planning) lists each change. Where a plan and this spec still differ, the plan is the later and tested statement.

## Goal

Every setting this repo manages can be seen and changed in one interface, in the terminal and in a browser. Values are seeded from the environment and the tracked files. A change made in the interface wins over the seed.

To get there correctly, the repo's setup moves onto mise's declarative config (env, macOS defaults, packages, dotfiles, bootstrap), so the interface talks to one backend with JSON output. Machines set up the old way move across with a separate, temporary migration script.

## Two parts

- **Part A, the new method.** The mise-first setup and the settings package. It never reads the old layout and carries no compatibility code for it.
- **Part B, the migration script.** `migrate/legacy-to-mise`, a standalone script for machines set up before this work ("early adopters", this Mac included). It is the only place that knows the old layout. It is deleted on or after 2027-02-28.

Phases land one at a time on `main`. Each Part A phase has a matching Part B step that lands in the same phase, so this Mac is never left half-migrated.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| D1 | mise is the storage backend. No store of our own. | mise already implements seed, override, reset and provenance (see Verified facts). |
| D2 | A UI change to an env setting is written with `mise set --override`, into `config.override.toml`. Reset is `mise unset --override`. | The override file outranks every other config and the shell's own value. |
| D3 | Existing shell exports (`zsh/env.zsh`, `tilde/.zshenv`, `~/.zsh.local`) stay where they are and act as seeds. They are not moved into `[env]`. | Smallest change that meets "seed from env, UI wins". |
| D4 | Tool-owned live files (`~/.claude/settings.json`, `~/.hindsight/coding-agent.json`, a project's `.claude/settings.local.json`) get no second copy. The UI calls the existing CLIs (`claude-config`, `hindsight-memory`, `claude-stack`) where one can make the change. No CLI can set the Claude Code model or a jstack role, so for those two the UI edits the live file itself with an atomic write. | A copy drifts. The tools rewrite those files themselves. |
| D5 | The new method is Homebrew-free. Setup, `upup` and shell startup never call `brew`. mise installs, upgrades and prunes packages into `/opt/homebrew`. | Removes the dependency on the old tool. Conditions in [Packages](#a4-packages). |
| D6 | Tap formulae that mise can install as a tool from the same upstream project move to `[tools]`, each after an identity check. Seven move (`azd`, `azure-functions-core-tools`, `kubelogin` as `aqua:Azure/kubelogin`, `flux2`, `hunk`, `lazydocker`, `talosctl`). Six stay tap formulae (`sentry`, `kubestellar-deploy`, `kubestellar-ops`, `radar`, `sfnt2woff`, `claude-multipass`). | 13 Brewfile tap formulae have no Apple Silicon bottle, and building from a tap's Ruby file is mise's least mature path. |
| D7 | The settings package is an in-repo uv package at `settings/`, named `dotfiles-settings`. It is not published yet. | Its registry describes this repo's files. It installs from git with `uv tool install "git+<repo>#subdirectory=settings"`. |
| D8 | One Textual app serves the terminal UI and, through textual-serve, the browser UI. | One codebase, verified on this Mac. |
| D9 | A Claude Code panel is a later addition. It will call the package's JSON commands, and a registry setting turns it on or off. No panel code in these plans. | Requested as a future, toggleable addition. `mise mcp` cannot write config. |
| D10 | Telemetry opt-outs are shown read-only. | They are a paired list checked by `bin/lib/test-conventions`. |
| D11 | Tested on this Mac only. A manually triggered CI job on the macOS runner is the fresh-install test. | No spare Mac or VM. |
| D12 | Every phase updates the docs that describe what it changed, in the same commit. | No stale instructions. See [Documentation](#documentation). |

## Verified facts

Checked on this Mac on 2026-11-09 with mise 2026.11.5, Homebrew 7.0.13, uv 0.13.7, Python 3.14.10.

- `[env] KEY = { default = "x" }` keeps a value the shell already set. A plain `[env]` value replaces it.
- `mise set --override KEY=v` creates `config.override.toml` beside the global config. With the shell exporting `KEY=shell`, `mise env --json` then reports `v`. `mise unset --override KEY` restores the shell's value.
- `mise set` with no arguments lists each variable with its source file. `mise config ls --json` marks the override tier with `"override": true`.
- Setting `MISE_GLOBAL_CONFIG_FILE` turns override files off. Tests that isolate mise must use `MISE_CONFIG_DIR` only.
- `~/.config/mise` is a symlink to `tilde/.config/mise` in this repo. So `config.override.toml`, `config.local.toml` and `miserc.local.toml` are written inside the clone, and none is gitignored today.
- Interactive shells run `mise activate zsh` at the first prompt (`zsh/init.zsh`). Agent and other non-interactive shells get shims only, so `[env]` and overrides do not reach a plain script there.
- `mise env --json` took 23 ms (one run).
- `mise bootstrap packages import --manager brew` reproduced all 151 Brewfile formulae and 13 taps, plus 2 formulae installed outside the Brewfile (`jrmatherly/ai-kb/ai-kb-lite`, `jrmatherly/ai-kb/aikb`).
- With the 33 Brewfile casks declared as `brew-cask:` entries, a dry-run apply reported all 33 and 152 formulae as already installed. It planned one change: `repair rustup/1.29.3: linked-keg record`.
- Installing `brew:hello` through mise worked. `brew list` saw it and `brew doctor` did not mention it. After `brew uninstall hello`, an empty `Cellar/hello` holding `.mise-staging.lock` remained and `brew list --versions hello` still printed the name.
- 15 formulae have no Apple Silicon bottle: `azure/azd/azd`, `azure/functions/azure-functions-core-tools@4`, `azure/kubelogin/kubelogin`, `bramstein/webfonttools/sfnt2woff`, `fluxcd/tap/flux`, `getsentry/tools/sentry`, `jesseduffield/lazydocker/lazydocker`, `jrmatherly/ai-kb/ai-kb-lite`, `jrmatherly/ai-kb/aikb`, `jrmatherly/tap/claude-multipass`, `kubestellar/tap/kubestellar-deploy`, `kubestellar/tap/kubestellar-ops`, `modem-dev/tap/hunk`, `siderolabs/tap/talosctl`, `skyhook-io/tap/radar`.
- mise's registry resolves `azd`, `azure-functions-core-tools`, `flux2`, `hunk`, `kubelogin`, `lazydocker`, `sentry`, `talosctl`. Two need an identity check before use: `kubelogin` maps to `int128/kubelogin` (the Brewfile has Azure's), and `sentry` maps to `getsentry/sentry-cli` (the Brewfile has the newer `sentry` CLI).
- Casks: 2 use pkg installers (`dotnet-sdk`, `git-credential-manager`), 2 generate completions at install time (`codex`, `1password-cli`), 17 self-update, 1 is from a third-party tap (`jrmatherly/tap/claude-multipass-app`), `ghostty` ships a man page.
- Keg-only formulae in use: `binutils`, `openjdk`, `rustup`, `ssh-copy-id`, `trash-cli` (the Brewfile force-links `trash-cli` with `link: true`).
- `mise-plugins/mise-vscode-extensions`, the plugin repo mise's docs point at for VS Code extensions, returns 404. The Brewfile holds 183 `vscode` lines.
- `setup/macos.sh` has 87 `defaults write` lines, 2 of them with `sudo`, and about 15 non-`defaults` commands (`pmset`, `systemsetup` and similar).
- `setup/symlinks.sh` has 2 `sudo` links into `/usr/local/bin` and links three Firefox files as hard links.
- A Textual 8.2.8 app ran headless and, through textual-serve 1.1.3, answered HTTP 200 on `127.0.0.1`. The browser view is the terminal app drawn in a browser tab.
- A uv package in a repo subdirectory built a wheel and ran with `uvx --from "git+file://<repo>#subdirectory=settings"`.
- `dotfiles-settings` is unclaimed on PyPI.
- CI (`.github/workflows/check.yml`, `macos-26`) installs neither mise nor uv.
- Changelog dates: `[dotfiles]` and macOS defaults first appear in mise 2026.6.6, the override file in 2026.10.14.

From mise's docs, not run here:

- mise never uses `sudo` for macOS preferences and never deletes one.
- `[dotfiles]` symlink modes refuse to replace a real file. `--force` replaces it with no backup. A symlink pointing elsewhere is repointed without `--force`.
- `create_if_missing = true` writes a copy only when nothing is there. `merge = true` owns only the keys in its source, for JSON, JSONC, TOML, YAML and INI.
- mise does not upgrade a cask that Homebrew installed. Casks cannot be imported or version-pinned. Deleting a package entry uninstalls nothing until `prune`.
- `mise bootstrap plan` does not cover dotfiles, repos, macOS defaults or tools. `mise bootstrap status --missing` exits 1 on any drift.
- A bootstrap run is not a transaction. Hooks and the `bootstrap` task run every time.

## Constraints

- Minimum mise version: 2026.11.5. Setup and the settings package fail with a clear message below it.
- Python 3.11 or newer for the package (`tomllib`). Dependencies: `textual>=8.2,<9`, `textual-serve>=1.1,<2`. No others.
- The package's core (registry, adapters, CLI) imports nothing outside the standard library, so its tests run with plain `python3`.
- Shell startup must not run an interpreter or mise unless a cached file is stale.
- mise is run from `$HOME`, never from inside the clone. Inside it, mise loads the repo's `.nvmrc` as project config.
- `~/dotfiles` must be a symlink to the clone. A `[dotfiles]` source is not a template, so sources and hooks find the repo through that path. `setup.sh` creates it and stops when something else is there.
- A value written to the override file may not contain `{{`, `{%`, `{#`, `$` or a line break. mise treats the first three as a template and expands `$`, and a bad template breaks every later `mise env`.
- Nothing prunes packages automatically. `prune` removes every undeclared keg, mise's own included on a migrated Mac.
- Tap resolution calls the GitHub API, and the anonymous limit (60 an hour) is not enough for one run. Setup, `upup` and CI pass `MISE_GITHUB_TOKEN`, so `gh` must be signed in before packages install.
- The browser UI binds to `127.0.0.1` only, on a random free port, behind a per-run token in the URL.
- Machine-local files never enter git: `config.override.toml`, `config.*.override.toml`, `config.local.toml`, `config.*.local.toml`, `miserc.local.toml` under `tilde/.config/mise/`.
- Repo conventions hold: bash scripts start with `#!/bin/bash` and a tldr-style header, define their output helpers inline, and pass `pnpm check`. Commit subjects are short, imperative, sentence case.
- GitHub Actions are pinned to a commit SHA with the version in a comment, as in `check.yml`.

## Architecture

```text
settings/                      uv package "dotfiles-settings"
  pyproject.toml
  registry.toml                every setting, one [[setting]] table each
  src/dotfiles_settings/
    registry.py                load and validate registry.toml
    model.py                   Setting, Value, Source
    adapters/                  one module per kind
      env.py                   mise override file
      macos_default.py         [bootstrap.macos.*]
      package.py               [bootstrap.packages], [tools]
      dotfile.py               [dotfiles]
      tool.py                  existing CLIs
    cli.py                     list / get / set / reset / apply, all with --json
    tui.py                     Textual app
    serve.py                   textual-serve wrapper
  tests/
tilde/.config/mise/
  config.toml                  tools and settings (as today)
  conf.d/                      one fragment per concern, added by the phases
    20-macos.toml  30-packages.toml  40-dotfiles.toml  50-bootstrap.toml
migrate/legacy-to-mise         Part B
```

### Data shape

```toml
[[setting]]
id = "updates.trim_ca_roots"       # unique, dotted
section = "Updates"                # UI grouping
label = "Remove the compromised eMudhra roots"
help = "Lets upup remove two roots brew doctor warns about. ca-roots restore puts them back."
kind = "env"                       # env | macos-default | package | dotfile | tool
key = "DOTFILES_TRIM_CA_ROOTS"     # meaning depends on kind
type = "bool"                      # bool | string | int | enum | path
true_value = "1"                   # bool only: the string written for true
choices = []                       # enum only
default = ""                       # value when nothing sets it; "" means unset
access = "rw"                      # rw | ro
```

```python
class Source(Enum): OVERRIDE; SEED; DEFAULT; UNSET

@dataclass(frozen=True)
class Value:
    setting_id: str
    value: str | None      # effective value
    source: Source
    seed: str | None       # what applies without the override
    drift: bool            # the live system differs from the declared value

class Adapter(Protocol):
    def read(self, s: Setting) -> Value: ...
    def write(self, s: Setting, value: str) -> None: ...
    def reset(self, s: Setting) -> None: ...
```

Adapters are looked up in a dict keyed by `kind`. A `ro` setting rejects `write` and `reset` in the CLI, before any adapter runs.

### CLI contract

`dotfiles-settings list [--section S] --json`, `get <id> --json`, `set <id> <value>`, `reset <id>`, `apply <kind>`, `tui`, `serve [--no-open]`. JSON output is the `Value` fields plus the setting's `label`, `section`, `type`, `choices` and `access`. An adapter may also define `apply(settings) -> list[str]`, which `apply <kind>` calls, and a `write_note` string the UI shows before a write that changes a tracked file. A7 adds one optional registry field, `widget` (`""`, `"lines"`, `"seats"`), for the multi-line path list and the jstack role editor. Exit codes: 0 success, 1 failure, 2 unknown id or invalid value, 3 read-only setting. This contract is what the later Claude Code panel uses.

## Phases

Each Part A phase ends with `pnpm check` passing. From A3 on, each phase's self-check fails on a config that mise cannot parse, a dropped entry or a type mismatch, and only warns on value drift. `mise bootstrap status --missing` is not the gate: Finder and other apps rewrite preferences without anyone changing the config, so it can flip without cause.

### A1. Env settings on mise

Gitignore the machine-local mise files. Add `zsh/override-env.zsh`, sourced at the end of `tilde/.zshenv` and again as the last line of `tilde/.zshrc` (`zsh/env.zsh` and `~/.zsh.local` export after `.zshenv`, so one source is not enough for the override to win in an interactive shell): when `config.override.toml` exists and is newer than `~/.cache/dotfiles/override-env.zsh`, regenerate that cache from `mise env --dotenv`, filtered to the keys in the override file's `[env]` table and requoted (the dotenv output is unquoted and not safe to source as it is), then source it. When the override file is absent, do nothing. Require mise 2026.11.5 in setup, through `setup/mise-floor.sh`. Install mise and uv in CI. Add a self-check, `bin/lib/test-override-env`.

### A2. The settings package

`settings/` with the registry, the model, the `env` adapter, the CLI, the Textual app and the serve wrapper. The registry lists 36 env settings: 14 read-write (the `DOTFILES_*` knobs a script still reads, `OBSIDIAN_VAULT`, `VSCODE_FONT_PRESET`, `UPUP_SLOW`, the Hindsight model variables, `EDITOR`, `BAT_THEME`, the npm init values) and the 22 telemetry opt-outs as `ro`. `GHIDRA_INSTALL_DIR` is left out, because `bin/rea-mcp` overwrites it at every launch. `bin/vscode-settings` is changed so the environment's `VSCODE_FONT_PRESET` wins over its saved file. The seed is read from a fresh shell started with overrides off, since the current environment already holds the overridden value. textual-serve has no token and does not check the WebSocket origin, so `serve.py` adds both. The other four kinds have no adapter yet and no registry entries.

### A3. macOS defaults

`setup/macos.sh` has 91 `defaults write` lines. 76 of them and its 6 `PlistBuddy` edits move into `conf.d/20-macos.toml` (88 declared entries, in raw `[bootstrap.macos.defaults."<domain>"]` tables). 9 lines go to `setup/macos-extras.sh` with the non-`defaults` commands: 2 need `sudo`, 2 need `$HOME` in the value, 5 target sandboxed apps mise cannot read. 6 default-no prompts (security and per-machine choices) become opt-ins and are not declared. The extras script runs from a `post-defaults` hook. `bin/set-defaults` stays as the command that applies macOS preferences. Delete `setup/macos.sh` and its `DOTFILES_MACOS_YES` and `DOTFILES_MACOS_NO` knobs. `mise config set` strips the comments from a table it edits, so the adapter makes a minimal text edit and re-parses to confirm. Add the `macos-default` adapter and registry entries.

### A4. Packages

`conf.d/30-packages.toml` declares every formula and cask. Registry-backed tap formulae move to `[tools]` after an identity check each (D6). VS Code extensions are installed by a package-manager plugin kept in this repo at `mise-plugins/vscode/`, linked with `mise plugins link`. mise itself is installed with its own installer. `brewpick`, `setup/brew.sh` and `setup/Brewfile` are deleted. `upup` gets its mise upgrade steps in this phase, so upgrades never stop between phases. `upup`, `bin/lib/check`, `zsh/path.zsh`, `zsh/init.zsh`, `tilde/.zprofile` and the other `brew` callers stop calling `brew`. The `HOMEBREW_*` exports go. A manually triggered workflow, `.github/workflows/fresh-install.yml`, applies the package config on a clean runner. Add the `package` adapter (status, and apply missing).

Known gaps to close in this phase: `trash-cli` needs a PATH entry in place of `link: true` (`link = true` is a parse error in mise). `bin/ca-roots trim` runs Homebrew's own script, so `DOTFILES_TRIM_CA_ROOTS` does nothing on a Mac without Homebrew, and its help text says so. `bin/rea-mcp` and `setup/misc.sh` call `brew --prefix ghidra` and get a static path. `hunk` moves from 0.17.0 to the current release, and the git pager is checked against the tracked config. The 2 pkg casks and the 2 completion-generating casks each need an install test. `ghostty`'s man page is not linked. The `rustup` keg repair must be understood before the first real apply.

### A5. Dotfiles

`conf.d/40-dotfiles.toml` declares 38 entries: 37 single-path `symlink` entries and one `symlink-each`, for `~/.claude/rules`. There is no entry that walks `~`: with one, a read-only status ran over two minutes on this Mac, against 0.09 s with explicit entries. Sources are written `~/dotfiles/...`. The Codex config uses `copy` with `create_if_missing`. `[bootstrap.files]` cannot make a symlink, so the two `/usr/local/bin` links, Firefox's hard links, the git identity prompt (`~/.gitconfig.local`, with the `DOTFILES_GIT_*` knobs) and bat's cache are `setup/dotfiles-extras.sh`, which asks for sudo only when a link is missing. This Mac's Mole `.local` whitelist becomes an entry in the gitignored `config.local.toml`. Delete `setup/symlinks.sh`. Add the `dotfile` adapter (status, and apply).

### A6. Bootstrap entry point

`setup.sh` becomes a short script: install mise if missing, check its version, create the `~/dotfiles` and `~/.config/mise` links, then run `mise bootstrap` from `$HOME`. `mise bootstrap --adopt` cannot use a repo subdirectory as the config dir, so the wrapper stays. `setup/misc.sh` keeps its name and is the one `[tasks.bootstrap]` (a second definition in another fragment silently replaces the first). `setup/dotfiles-extras.sh` runs from a `post-dotfiles` hook, while sudo is still held. Touch ID for sudo is a `[bootstrap.files]` entry. `upup` gains a prune report that never prunes. `.claude/skills/validate-setup` and `.claude/rules/setup.md` are rewritten for the new order.

### A7. Agent tooling

The `tool` adapter and registry entries for: Hindsight on or off, its opt-in paths and survey switch (`hindsight-memory`), the per-project plugin stack (`claude-stack`), the jstack model roles (`tilde/.claude/rules/jstack-models.md`), and the Claude Code model line. A `ui.claude_panel` bool is registered for D9 and read by nothing yet.

### B. Migration script

`migrate/legacy-to-mise [--step <name>] [--dry-run]`. Steps: `env`, `macos`, `packages`, `dotfiles`, `setup`. Each is idempotent, prints what it will change, asks before changing, and backs up anything it replaces into `~/.dotfiles-migration-backup/<timestamp>/`.

- `env`: copy `export` lines for registered keys from `~/.zsh.local` into the override file on request, and leave the file itself alone.
- `macos`: report drift only. The preferences are already set.
- `packages`: formulae need no migration, since mise adopts them in place. List the casks Homebrew installed that do not self-update (16 of 33 here). mise skips a cask Homebrew installed, so moving one across needs `brew` still present. First try adoption on one font cask (hide Homebrew's record, let mise adopt the files in place); if that fails, the path is `brew uninstall --cask` then a mise apply, with a warning that a replaced app can lose its macOS privacy permissions. Removing Homebrew is a separate, last task, off by default and behind a typed phrase. Homebrew's own uninstaller deletes `Cellar` and `Caskroom`, which mise uses, so the task moves only the Homebrew program into the backup folder. That procedure is not one Homebrew documents, and it is not run on any Mac before the fresh-install workflow has passed.
- `dotfiles`: write this Mac's Mole `.local` entry into `config.local.toml`, find conflicts from `mise dot apply --dry-run`, back up real files in the way, then run `mise dot apply`. Never `--force`.
- `setup`: back up a hand-edited `/etc/pam.d/sudo_local` (the first bootstrap rewrites it), and re-register the `mise` MCP server when its command still points at Homebrew's path. Nothing is removed: the new method still uses the log folder and `~/dotfiles`.

The script's header states its removal date, and `bin/lib/test-conventions` fails after 2027-02-28 while the file still exists.

## Documentation

Each phase rewrites every file below that describes what it changed. A phase is not done while `grep` still finds the old instruction.

| Behaviour change | Phase | Files |
| --- | --- | --- |
| Settings are changed in the UI; `~/.zsh.local` exports are seeds that an override beats | A1, A2 | `README.md` (the `~/.zsh.local` section and each knob's instructions), `setup/README.md`, `bin/upup` header, `.claude/rules/zsh.md`, `CLAUDE.md` |
| Machine-local mise files live in the clone and are gitignored | A1 | `CLAUDE.md` (machine-local config), `.gitignore` comment |
| macOS preferences are TOML. mise never deletes a preference and never uses sudo for one | A3 | `.claude/rules/macos-defaults.md`, `docs/macos settings.md`, `setup/README.md`, `README.md` |
| No Homebrew. No version pins for casks. Removing an entry needs `prune`. Casks mise installs are its own | A4 | `README.md` (install, "Make it yours"), `setup/README.md`, `.claude/skills/add-tool/SKILL.md`, `.claude/rules/upup.md`, `.claude/rules/telemetry-sync.md`, `.claude/rules/vscode.md`, `bin/CLAUDE.md`, `CLAUDE.md`, `docs/privacy.md`, `docs/gui/*.md` and `docs/rea.md` and `docs/mole.md` where they say `brew install`, `fonts/README.md`, `colors/README.md`, `vscode/README.md` |
| Link conflicts stop the run; `--force` replaces with no backup; no prompt | A5 | `.claude/rules/symlinks.md`, `tilde/README.md`, `setup/README.md`, `firefox/README.md`, `README.md`, `CLAUDE.md` |
| mise is installed first; `setup.sh` is a wrapper around `mise bootstrap`; a run is not a transaction; `~/dotfiles` is required; `gh` must be signed in before packages install | A6 | `README.md`, `setup/README.md`, `.claude/rules/setup.md`, `.claude/skills/validate-setup/SKILL.md`, `.claude/agents/docs-auditor.md`, `.claude/skills/docs-audit/SKILL.md`, `CLAUDE.md`, `.serena/memories/core.md` |
| Agent settings are in the UI | A7 | `agents/README.md`, `.claude/rules/claude-config.md`, `tilde/.claude/rules/hindsight.md` |
| How to migrate an existing machine, and until when | B | `README.md`, `migrate/README.md` |

`setup/bootstrap-runtime.archify.json` and its SVG are regenerated in A6.

## Risks

- **Young upstream features.** The override file is three weeks old. Mitigation: the version floor, and a self-check that exercises seed, override and reset on every `pnpm check`.
- **Fresh install cannot be proven here.** Everything is already installed on this Mac, so mise's installer never runs. Mitigation: the fresh-install workflow (D11). Until it has passed, the README says so.
- **Privacy permissions.** Reinstalling an app through mise can drop them. Mitigation: Part B asks per cask.
- **A bootstrap run can stop half way.** Mitigation: every task and hook is safe to repeat, and the docs say to rerun.
- **Session cost of the browser UI.** Any local page could try the WebSocket. Mitigation: loopback bind, random port, URL token, and a test that a request without the token is refused. Whether textual-serve checks the Origin header is unverified; A2 checks it and adds the check if absent.

## Open decisions

Each has a default the plans already follow. Changing one means editing the named plan.

1. **Does `mise bootstrap` apply macOS preferences?** Today only `bin/set-defaults` does, on purpose. With A3's hook and A6's entry point, every setup run would. Default in the plans: it does. To keep today's behaviour, `setup.sh` passes `--skip macos-defaults` (A6).
2. **Security opt-ins for macOS** (firewall, HiDPI, Time Machine, computer name) are flags of `setup/macos-extras.sh`, so they are not in the UI. Making them env settings would put them there (A3).
3. **The Hindsight model settings are read-write but reach shells only.** An app-launched Claude Code reads its own copy in `agents/claude-settings.json`. The help text says so. Marking them read-only is the stricter choice (A2).
4. **The browser page loads one stylesheet from `fonts.googleapis.com`** (textual-serve's template). Removing it means shipping our own copy of the template (A2).
5. **Removing Homebrew at all** (B, Task 5). The new method never calls it either way.
6. **The Codex config** is seeded with `copy` and `create_if_missing`, which drops the old warning about tracked lines the live file lacks. `merge = "missing"` would add those lines for real (A5).
7. **`ask` permission rules** for `mise bootstrap` and `mise dot apply` were added to `.claude/settings.json` by A3 and A5, replacing the guard on the deleted scripts.

## Corrections from planning

- A1: one source of the override file in `.zshenv` loses to `zsh/env.zsh` and `~/.zsh.local` in an interactive shell. `mise env --dotenv` is not sourceable as printed.
- A2: `VSCODE_FONT_PRESET` was never read from the environment. `GHIDRA_INSTALL_DIR` cannot be overridden. textual-serve checks neither a token nor the origin. The JSON contract lacked `choices`.
- A3: the script has 91 `defaults write` lines, not 87, and not every non-sudo line can be declared. `setup.sh` never ran it.
- A4: 13 bottle-less tap formulae are in the Brewfile, not 15. The registry names for `kubelogin` and `sentry` are different tools. `upup` must upgrade through mise in the same phase that drops Homebrew. The GitHub rate limit and `ca-roots trim` were missing.
- A5: `[bootstrap.files]` cannot make a symlink. A `symlink-each` over `~` is too slow to use. `~/dotfiles` becomes required.
- A6: `--adopt` cannot take a subdirectory. mise must run from `$HOME`. Only one `[tasks.bootstrap]` can exist.
- A7: no CLI sets the Claude Code model.
- B: Homebrew's uninstaller would delete mise's packages. mise cannot reinstall a Homebrew cask by itself. There is no `10-env.toml` and no old logs path to remove.

## Out of scope

The Claude Code panel itself. Publishing to PyPI or a tap. Linux and Intel Macs. `mise dot` history sync between machines. Moving the repo's own `private/` or `logs/` handling.

## Plans

- `docs/superpowers/plans/2026-11-09-a1-env-settings-on-mise.md`
- `docs/superpowers/plans/2026-11-09-a2-settings-package.md`
- `docs/superpowers/plans/2026-11-09-a3-macos-defaults.md`
- `docs/superpowers/plans/2026-11-09-a4-packages.md`
- `docs/superpowers/plans/2026-11-09-a5-dotfiles.md`
- `docs/superpowers/plans/2026-11-09-a6-bootstrap-entry-point.md`
- `docs/superpowers/plans/2026-11-09-a7-agent-tooling.md`
- `docs/superpowers/plans/2026-11-09-b-migration-script.md`
