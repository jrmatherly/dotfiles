# A2 Settings Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `settings/`, a uv package named `dotfiles-settings` that lists, reads, changes and resets this repo's env settings from a CLI, a terminal UI and a browser UI, storing changes in mise's override file.

**Architecture:** A registry file (`registry.toml`) names every setting. An adapter per `kind` reads and writes it. This phase ships one adapter, `env`, which reads `config.override.toml` with `tomllib` and writes through `mise set --override`. The CLI, the Textual app and the textual-serve wrapper all go through the same registry and adapters. The core (model, registry, mise helper, adapters, CLI) imports only the standard library. Textual is imported inside `tui.py` and `serve.py` only.

**Tech Stack:** Python 3.11+ (stdlib `tomllib`, `argparse`, `subprocess`), uv 0.13.7 with the hatchling build backend, Textual 8.2, textual-serve 1.1 (aiohttp), mise 2026.11.5, bash for the launcher.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A2. The settings package". Phase A1 has landed before this plan starts.

**Line numbers** are from commit `9af6244`. An earlier phase may have moved them, so find the quoted text with `grep -n` before editing.

## Global Constraints

- Minimum mise version: 2026.11.5. The package fails with a clear message below it.
- Python 3.11 or newer. Dependencies: `textual>=8.2,<9`, `textual-serve>=1.1,<2`. No others.
- The core (registry, model, mise helper, adapters, CLI) imports nothing outside the standard library, so its tests run with plain `python3`.
- The browser UI binds to `127.0.0.1` only, on a random free port, behind a per-run token in the URL.
- Tests that isolate mise set `MISE_CONFIG_DIR` and `HOME` to temp dirs. `run_mise` runs mise from `$HOME`, so a test that kept the real `HOME` would let mise read whatever config sits under it. Never set `MISE_GLOBAL_CONFIG_FILE`: it turns override files off.
- Names and signatures of `Setting`, `Value`, `Source`, `Adapter` and the CLI contract (subcommands, JSON fields, exit codes 0, 1, 2, 3) are the spec's, plus what the 2026-11-09 review settled: four optional registry fields, the `widget` field, `watch_paths`, and `write_note` as a string or a method. Five later plans add adapters against them. The Interfaces blocks below are the reference.
- A `ro` setting rejects `set` and `reset` in the CLI, before any adapter runs.
- Bash scripts start with `#!/bin/bash` and a tldr-style header, define their output helpers inline, and pass `pnpm check`. Each header line is one sentence on one line.
- House Python style (`agents/catalog/stack.py`): small functions, an error class the CLI reports without a traceback, test files that are plain scripts with module-level asserts and a final `print("ok")`.
- Commit subjects are short, imperative, sentence case, with no prefix. Every task ends with `pnpm check` passing.
- A commit names each path it adds. No `git add -A`, no `git add .`, no bare directory. The working tree holds an unrelated uncommitted change to `agents/claude-settings.json` that must not enter any commit of this plan.

## Review Focus

1. **A value containing shell or template metacharacters.** Measured on mise 2026.11.5: spaces, quotes, `=`, backslashes, backticks, `;`, `|`, `#`, a leading `-` and non-ASCII text round-trip unchanged. `{{`, `{%` and `{#` are parsed as a Tera template, and `{{ x }}` made every later `mise env` call exit 1. `$VAR` and `${VAR}` are expanded in `mise env` output. A person expects the stored value to be the typed value, so `set` refuses `{{`, `{%`, `{#`, `$`, and line breaks with exit 2. Test in Task 2.
2. **A registry key that is also exported in `~/.zsh.local`.** A1 sources its override cache after `~/.zsh.local`, so the override wins in every zsh. The UI must show source `override`, and show the `~/.zsh.local` value as the seed that reset would restore. Test in Task 2.
3. **mise missing or older than 2026.11.5.** Every subcommand exits 1 with one line naming the floor and what was found. No traceback. Test in Task 3.
4. **The override file hand-edited into invalid TOML.** mise itself exits 1 on every command in that state. `list` and `get` exit 1 with the file path and the parser's line. The TUI shows the error in a banner, disables the rows, and recovers when the file is fixed. Tests in Tasks 2, 3 and 4.
5. **Two UIs open at once.** A change made in one appears in the other within two seconds. A write that another writer clobbered is reported, not silently lost. Tests in Tasks 2 and 4.
6. **The browser page and third parties.** textual-serve 1.1.3's own page links a stylesheet on `fonts.googleapis.com`, so opening it would tell Google the user ran the settings UI. The page served here contains no URL outside `127.0.0.1:<port>`, and the shipped template copy cannot silently drift from upstream after a lock bump. Test in Task 5.
7. **Settings a UI must not offer to change.** The Hindsight model variables are `ro` (spec decision 3): they reach shells only, and Claude Code started from an app reads its own copy in `agents/claude-settings.json`, so an editable field would change half the system. Test in Task 1.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `settings/pyproject.toml` | Project metadata, dependencies, console script, hatchling build that packages `registry.toml` |
| `settings/uv.lock` | Committed lockfile |
| `settings/registry.toml` | Every setting, one `[[setting]]` table each |
| `settings/src/dotfiles_settings/model.py` | `Setting`, `Value`, `Source`, `Adapter`, `SettingsError`, `InvalidValue` |
| `settings/src/dotfiles_settings/registry.py` | Load and validate `registry.toml` |
| `settings/src/dotfiles_settings/mise.py` | Run mise, find its config dir, check the version floor |
| `settings/src/dotfiles_settings/adapters/__init__.py` | `ADAPTERS`, the dict keyed by kind |
| `settings/src/dotfiles_settings/adapters/env.py` | `EnvAdapter` |
| `settings/src/dotfiles_settings/cli.py` | Subcommands, value normalization, JSON, exit codes |
| `settings/src/dotfiles_settings/__main__.py` | `python -m dotfiles_settings` (textual-serve launches the app this way) |
| `settings/src/dotfiles_settings/tui.py` | `SettingsApp` |
| `settings/src/dotfiles_settings/serve.py` | `GuardedServer`, the textual-serve wrapper |
| `settings/src/dotfiles_settings/templates/app_index.html` | textual-serve's page template with the Google Fonts link replaced by an `@font-face` on textual-serve's own font file |
| `settings/src/dotfiles_settings/templates/LICENSE-textual-serve` | textual-serve's MIT license, which a copy of its file must carry |
| `settings/tests/test_*.py` | One script per module |
| `settings/README.md` | Package documentation |
| `bin/dotfiles-settings` | Launcher from the clone |

Decisions the spec left open, fixed here:

- **Dependencies are main dependencies, not an extra.** `uv tool install "git+<repo>#subdirectory=settings"` then gives a working `tui` and `serve` with no extra flag. The stdlib-only rule is kept by importing Textual inside `tui.py` and `serve.py`, which `cli.py` imports only inside the `tui` and `serve` branches.
- **Build backend: hatchling.** `uv init --package` with uv 0.13.7 writes `uv_build`, which cannot map a file outside the module into the wheel. The spec puts `registry.toml` at `settings/registry.toml`, so the wheel needs hatchling's `force-include`. Verified: the built wheel contains `dotfiles_settings/registry.toml`, and an editable install finds `settings/registry.toml`.
- **`uv.lock` is committed.** The launcher and `bin/lib/check` run with `--locked`, so a dependency cannot move without a diff.
- **`default` means the consumer's own fallback.** No file applies a registry default for an env setting (spec D3), so `default` is non-empty only when the script that reads the variable falls back to that value itself. Otherwise it is `""` and an unset variable reads as `unset`.
- **A bool set to false is written as the empty string.** `sysup` tests `DOTFILES_TRIM_CA_ROOTS` with `-n` and `setup/misc.sh` tests `DOTFILES_SKIP_CODEGRAPH` with `= true`. An empty override reads as false for both and still beats a seed of `1`. A bool is shown as on when its value equals `true_value`.
- **`apply <kind>`** calls an optional adapter method `apply(self, settings: list[Setting]) -> list[str]` and prints the returned lines. `EnvAdapter` has none, and the CLI prints `env: nothing to apply`.
- **`write_note`** is optional on an adapter. It is either a string, or a method `write_note(self, s: Setting) -> str` for an adapter whose settings differ (A7's jstack roles edit a tracked file, its other settings do not). An empty string means no note. Callers never read the attribute themselves. They call `model.note_for(adapter, s)`, which handles a missing attribute, a string and a method. The note is shown with the write: once, right after a `set` or `reset` succeeds. The CLI prints it to stderr. The TUI shows it with `notify`. It is not shown before the write, there is no confirmation prompt, and a refused or failed write shows the error alone.
- **Four registry fields are optional.** `true_value`, `choices`, `default` and `widget` default to `""`, `[]`, `""` and `""`. The other eight are required. `Setting` is a keyword-only dataclass, so every `Setting(...)` call names its fields and the field order cannot matter. `widget` is one of `""`, `"lines"`, `"seats"`. This plan defines the field, validates it and emits it in JSON. A7 gives the two non-empty values their behaviour, and until then the TUI draws every setting by its `type`.
- **mise runs from `$HOME`.** `run_mise` passes `cwd=Path.home()`. Measured on mise 2026.11.5: from a folder holding an untrusted `mise.toml`, `mise set --override` exits 0 but `mise env --json` exits 1 with "not trusted". From `$HOME` both exit 0.
- **Live refresh covers every file an adapter names.** An adapter may define `watch_paths(self) -> list[Path]`. The TUI polls the mtimes of the union across its adapters.
- **The VS Code font preset has a file seed.** `bin/vscode-settings` falls back to the preset saved in `~/.config/dotfiles/vscode.env`, not to a shell export. For this one key, when the seed shell does not export it, `EnvAdapter` reads the seed from that file (`env.file_seed`). No registry field is added for it. Task 6 makes the script use an environment preset without saving it, so a reset in the UI hands the choice back to the saved file.
- **`set`, `reset` and `apply` ask in Claude Code, from A7 on.** In this phase they only write the gitignored override file. From A3 on, `set` on a `macos-default` setting edits a tracked file and changes live preferences, and A5's `apply dotfile` creates links. A permission rule cannot tell kinds apart, so all three subcommands get `ask` rules, in the form the repo uses for `sysup` and `set-defaults`. This plan adds none of them: spec decision 7 lands every `ask` rule in the last phase, so A7's Task 8 adds these eighteen, and until then the owner's go-ahead in chat is the guard. `list`, `get`, `tui` and `serve` do not ask.
- **The Hindsight model variables are read-only** (spec decision 3). `tilde/.zshenv` exports them for shells and `agents/claude-settings.json` sets the same three for Claude Code, so an override would reach shells only. They are shown so the user can see which model runs, with help text naming both files.
- **The browser page is served from a template copy in the package** (spec decision 4). `GuardedServer` passes `templates_path` to textual-serve, which accepts an absolute path (`base_path / templates_path` in `Server.__init__` keeps an absolute right side). The copy is upstream's `app_index.html` with its four-line Google Fonts `<link>` replaced by an `@font-face` that points at `RobotoMono-VariableFont_wght.ttf`, a file textual-serve already ships in its `static/fonts/` and serves at `/static/fonts/`, so the page keeps the font upstream intends and makes no third-party request. Static files still come from textual-serve's own folder. `test_serve.py` rebuilds the expected copy from the installed upstream template, so a textual-serve upgrade that changes the template fails the gate until the copy is redone.
- **Later phases add `env` settings to this registry.** A3 adds the macOS security opt-ins (firewall, HiDPI, Time Machine, computer name; spec decision 2) and the four preference-group switches (screenshots, the Time Machine new-disk prompt, TextEdit, Software Update; spec decision 9), and A7 adds `ui.claude_panel`. Nothing in this plan pins the number of `env` settings, a closed list of keys or sections, or the set of read-write settings. `seed_env` takes the keys of whatever `env` settings the registry holds, and the only count, of `Privacy` entries, does not include them.
- **Registry entries left out on purpose:** `DOTFILES_MACOS_YES` and `DOTFILES_MACOS_NO` (deleted by A3), `DOTFILES_GIT_NAME`, `DOTFILES_GIT_EMAIL`, `DOTFILES_GIT_SIGN_METHOD`, `DOTFILES_GIT_SIGNINGKEY` (read once, only while `~/.gitconfig.local` is missing; A5 keeps them and moves the prompt that reads them into `setup/dotfiles-extras.sh`), `DOTFILES_SUDO_KEPT`, `DOTFILES_SETUP_LOG`, `DOTFILES_DIR` (internal), and `GHIDRA_INSTALL_DIR` (`bin/rea-mcp` overwrites it from the Homebrew keg at every launch, so an override has no effect).

---

### Task 1: Package scaffold, model and registry

**Files:**

- Create: `settings/pyproject.toml`, `settings/uv.lock`, `settings/registry.toml`
- Create: `settings/src/dotfiles_settings/__init__.py` (empty), `model.py`, `registry.py`
- Test: `settings/tests/test_registry.py`
- Modify: `.gitignore`, `bin/lib/check`

**Interfaces:**

- Produces, in `model.py`:

```python
class SettingsError(Exception): ...          # CLI exit 1
class InvalidValue(SettingsError): ...       # CLI exit 2

class Source(Enum):
    OVERRIDE = "override"; SEED = "seed"; DEFAULT = "default"; UNSET = "unset"

@dataclass(frozen=True, kw_only=True)
class Setting:
    id: str; section: str; label: str; help: str; kind: str; key: str
    type: str; access: str                                  # the eight required fields
    true_value: str = ""; choices: tuple[str, ...] = (); default: str = ""; widget: str = ""

@dataclass(frozen=True)
class Value:
    setting_id: str; value: str | None; source: Source; seed: str | None; drift: bool

class Adapter(Protocol):
    def read(self, s: Setting) -> Value: ...
    def write(self, s: Setting, value: str) -> None: ...
    def reset(self, s: Setting) -> None: ...
    # optional, looked up with getattr:
    #   apply(self, settings: list[Setting]) -> list[str]
    #   watch_paths(self) -> list[Path]
    #   write_note: str, or write_note(self, s: Setting) -> str

def note_for(adapter: object, s: Setting) -> str   # "" when the adapter has no note for s
```

`write` receives a value the CLI has already normalized. A false bool arrives as `""` and a true bool as `s.true_value`, so every adapter accepts `""` as false.

- Produces, in `registry.py`:

```python
KINDS = ("env",)                      # later plans append their kind
TYPES = ("bool", "string", "int", "enum", "path")
WIDGETS = ("", "lines", "seats")      # A7 gives "lines" and "seats" their behaviour
REQUIRED = ("id", "section", "label", "help", "kind", "key", "type", "access")
def default_path() -> Path
def load(path: Path | None = None) -> list[Setting]
```

- [ ] **Step 1: Write `settings/pyproject.toml`**

```toml
[project]
name = "dotfiles-settings"
version = "0.1.0"
description = "See and change the settings this dotfiles repo manages"
requires-python = ">=3.11"
dependencies = ["textual>=8.2,<9", "textual-serve>=1.1,<2"]

[project.scripts]
dotfiles-settings = "dotfiles_settings.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/dotfiles_settings"]

[tool.hatch.build.targets.wheel.force-include]
"registry.toml" = "dotfiles_settings/registry.toml"
```

- [ ] **Step 2: Write `settings/registry.toml`**

A table has eight required fields: `id`, `section`, `label`, `help`, `kind`, `key`, `type`, `access`. Four are optional: `true_value` (default `""`), `choices` (`[]`), `default` (`""`) and `widget` (`""`). A `bool` needs a `true_value` and an `enum` needs `choices`. The entries below write the first three optional fields out. A later plan may leave them off.

```toml
[[setting]]
id = "updates.trim_ca_roots"
section = "Updates"
label = "Remove the compromised eMudhra roots"
help = "Lets sysup remove two roots brew doctor warns about. ca-roots restore puts them back."
kind = "env"
key = "DOTFILES_TRIM_CA_ROOTS"
type = "bool"
true_value = "1"
choices = []
default = ""
access = "rw"

[[setting]]
id = "updates.mac_password_op"
section = "Updates"
label = "1Password reference for the Mac login password"
help = "A secret reference such as op://Private/Mac login/password. sysup reads it with op when a macOS update is pending. The password itself is never stored here."
kind = "env"
key = "DOTFILES_MAC_PASSWORD_OP"
type = "string"
true_value = ""
choices = []
default = ""
access = "rw"

[[setting]]
id = "updates.slow_step_seconds"
section = "Updates"
label = "Show a step's time after this many seconds"
help = "sysup adds the elapsed time to a step's result line when the step took at least this long."
kind = "env"
key = "SYSUP_SLOW"
type = "int"
true_value = ""
choices = []
default = "10"
access = "rw"

[[setting]]
id = "setup.skip_codegraph"
section = "Setup"
label = "Leave CodeGraph alone during setup"
help = "Same as setup.sh --skip-codegraph."
kind = "env"
key = "DOTFILES_SKIP_CODEGRAPH"
type = "bool"
true_value = "true"
choices = []
default = ""
access = "rw"

[[setting]]
id = "shell.editor"
section = "Shell"
label = "Editor"
help = "EDITOR for local sessions. zsh/env.zsh sets VISUAL from its own EDITOR value before an override applies, so VISUAL does not follow this."
kind = "env"
key = "EDITOR"
type = "string"
true_value = ""
choices = []
default = ""
access = "rw"

[[setting]]
id = "shell.bat_theme"
section = "Shell"
label = "bat theme"
help = "Syntax highlighting theme for bat. bat --list-themes prints the names."
kind = "env"
key = "BAT_THEME"
type = "string"
true_value = ""
choices = []
default = ""
access = "rw"

[[setting]]
id = "apps.obsidian_vault"
section = "Apps"
label = "Obsidian vault folder"
help = "Used by obsidian-vault and install-color-themes."
kind = "env"
key = "OBSIDIAN_VAULT"
type = "path"
true_value = ""
choices = []
default = "~/Library/Mobile Documents/com~apple~CloudDocs/Notes"
access = "rw"

[[setting]]
id = "apps.vscode_font_preset"
section = "Apps"
label = "VS Code font preset"
help = "Beats the preset saved by vscode-settings --choose, without replacing it. Reset goes back to the saved preset. Run vscode-settings in a new shell afterwards to render settings.json."
kind = "env"
key = "VSCODE_FONT_PRESET"
type = "enum"
true_value = ""
choices = ["iosevka", "warp", "warp-terminal", "fira"]
default = "iosevka"
access = "rw"

[[setting]]
id = "hindsight.llm_model"
section = "Hindsight"
label = "Model for reflect and page refresh"
help = "Read-only here. tilde/.zshenv sets it for shells and agents/claude-settings.json sets it for Claude Code, so change both files together. A running daemon keeps the model it started with."
kind = "env"
key = "HINDSIGHT_API_LLM_MODEL"
type = "string"
true_value = ""
choices = []
default = ""
access = "ro"
```

Add the other two Hindsight models with the same shape as `hindsight.llm_model`, `access = "ro"` and its help text included:

| id | section | key | label |
| --- | --- | --- | --- |
| `hindsight.retain_llm_model` | Hindsight | `HINDSIGHT_API_RETAIN_LLM_MODEL` | Model for extraction |
| `hindsight.consolidation_llm_model` | Hindsight | `HINDSIGHT_API_CONSOLIDATION_LLM_MODEL` | Model for consolidation |

Add these with the same shape (`kind = "env"`, `true_value = ""`, `choices = []`, `default = ""`, `access = "rw"`, `type = "string"`):

| id | section | key | label | help |
| --- | --- | --- | --- | --- |
| `npm.init_author_name` | npm | `NPM_CONFIG_INIT_AUTHOR_NAME` | Author name for npm init | zsh/env.zsh seeds it from git's global user.name. |
| `npm.init_license` | npm | `NPM_CONFIG_INIT_LICENSE` | License for npm init | zsh/env.zsh seeds MIT. |
| `npm.init_version` | npm | `NPM_CONFIG_INIT_VERSION` | Version for npm init | zsh/env.zsh seeds 0.1.0. |

Add the telemetry opt-outs. Each is `section = "Privacy"`, `kind = "env"`, `type = "string"`, `true_value = ""`, `choices = []`, `default = ""`, `access = "ro"`, `id = "privacy." + key.lower()`, and `help = "Telemetry opt-out exported by zsh/env.zsh. Read-only: the list is paired with setup.sh (.claude/rules/telemetry-sync.md)."`

| key | label |
| --- | --- |
| `NEXT_TELEMETRY_DISABLED` | Next.js |
| `STRAPI_TELEMETRY_DISABLED` | Strapi |
| `GATSBY_TELEMETRY_DISABLED` | Gatsby |
| `ASTRO_TELEMETRY_DISABLED` | Astro |
| `STORYBOOK_DISABLE_TELEMETRY` | Storybook |
| `VERCEL_TELEMETRY_DISABLED` | Vercel CLI |
| `CDK_DISABLE_CLI_TELEMETRY` | AWS CDK |
| `GH_TELEMETRY` | GitHub CLI |
| `AZURE_DEV_COLLECT_TELEMETRY` | Azure Developer CLI |
| `AZURE_MCP_COLLECT_TELEMETRY` | Azure MCP server |
| `DO_NOT_TRACK` | Console Do Not Track |
| `CODEGRAPH_TELEMETRY` | CodeGraph |
| `RTK_TELEMETRY_DISABLED` | rtk |
| `FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT` | Azure Functions Core Tools |
| `DOTNET_CLI_TELEMETRY_OPTOUT` | .NET CLI |
| `POWERSHELL_TELEMETRY_OPTOUT` | PowerShell |
| `AZURE_CORE_COLLECT_TELEMETRY` | Azure CLI |
| `ASPIRE_CLI_TELEMETRY_OPTOUT` | Aspire CLI |
| `ASPIRE_DASHBOARD_TELEMETRY_OPTOUT` | Aspire dashboard |
| `JFROG_CLI_REPORT_USAGE` | JFrog CLI |
| `DISABLE_ERROR_REPORTING` | Claude Code error reports |
| `HOMEBREW_NO_ANALYTICS` | Homebrew |

That makes 36 entries, all `kind = "env"`: 11 read-write, the 3 read-only Hindsight models and the 22 read-only opt-outs in `Privacy`. A4 deletes `privacy.homebrew_no_analytics` together with the export, and lowers the `Privacy` count in `test_registry.py` by one in the same commit.

- [ ] **Step 3: Write the failing test `settings/tests/test_registry.py`**

The file starts with `sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))`, as every test file in this plan does. A helper `load_text(toml_text)` writes the text to a temp file named `registry.toml` and returns `registry.load(path)`. `bad(toml_text, needle)` asserts that `load_text` raises `SettingsError` containing `needle`. `table(**fields)` renders one valid string-typed table with id `a.b`, with the given fields replaced, and `table_without(*names)` leaves fields out.

No assertion pins the total number of settings, the number of `env` or read-write settings, or the exact set of kinds, keys or sections. A3, A4, A5 and A7 append entries and test their own in their own files. The one count below, of `Privacy` entries, is the one this plan owns. A plan that adds or removes a `Privacy` entry changes that number in the same commit: A4 removes `privacy.homebrew_no_analytics`. The `env` entries A3 adds (the security opt-ins and the four preference-group switches, spec decisions 2 and 9) and A7's `ui.claude_panel` are in other sections and change nothing in this file. The Hindsight check selects by key prefix and kind, not by section or id prefix, because A7 adds `kind = "tool"` entries with ids starting `hindsight.`.

```python
settings = registry.load()
ids = [s.id for s in settings]
assert len(ids) == len(set(ids))                         # unique ids, no total: later plans append
assert {s.kind for s in settings} <= set(registry.KINDS)
by_id = {s.id: s for s in settings}
assert by_id["updates.trim_ca_roots"].true_value == "1"
assert by_id["apps.vscode_font_preset"].choices == ("iosevka", "warp", "warp-terminal", "fira")
assert all(s.access == "ro" for s in settings if s.section == "Privacy")
assert sum(s.section == "Privacy" for s in settings) == 22

# every read-only opt-out is still exported by zsh/env.zsh
env_zsh = (Path(__file__).resolve().parents[2] / "zsh/env.zsh").read_text()
for s in settings:
    if s.section == "Privacy":
        assert re.search(rf"^export {s.key}=", env_zsh, re.M), s.key

# the Hindsight models are shown, never edited, and tilde/.zshenv still exports each (spec decision 3)
zshenv = (Path(__file__).resolve().parents[2] / "tilde/.zshenv").read_text()
models = [s for s in settings if s.kind == "env" and s.key.startswith("HINDSIGHT_API_")]
assert {s.key for s in models} == {"HINDSIGHT_API_LLM_MODEL", "HINDSIGHT_API_RETAIN_LLM_MODEL",
                                   "HINDSIGHT_API_CONSOLIDATION_LLM_MODEL"}
for s in models:
    assert s.access == "ro", s.id
    assert re.search(rf"^export {s.key}=", zshenv, re.M), s.key

bad(two_tables_with_id("a.b"), "duplicate id: a.b")
bad(table(kind="nope"), "a.b: unknown kind 'nope'")
bad(table(type="float"), "a.b: unknown type 'float'")
bad(table(type="enum", choices=[]), "a.b: enum needs choices")
bad(table(type="bool", true_value=""), "a.b: bool needs true_value")
bad(table(access="wo"), "a.b: access must be rw or ro")
bad(table(key="lower case"), "a.b: env key must match [A-Z_][A-Z0-9_]*")
bad(table(default="x", type="enum", choices=["y"]), "a.b: default 'x' is not one of the choices")
bad(table_without("label"), "a.b: missing field 'label'")
bad(table_without("access"), "a.b: missing field 'access'")
bad(table(extra=1), "a.b: unknown field 'extra'")
bad(table(widget="grid"), "a.b: unknown widget 'grid'")

# a short entry: the four optional fields take their defaults
short = load_text(table_without("true_value", "choices", "default"))[0]
assert (short.true_value, short.choices, short.default, short.widget) == ("", (), "", "")
assert load_text(table(widget="seats"))[0].widget == "seats"
# a bool may be on by default: A3's switches set default equal to true_value (spec decisions 2 and 9)
on = load_text(table(type="bool", true_value="1", default="1", section="macOS (this Mac)"))[0]
assert (on.default, on.true_value, on.section) == ("1", "1", "macOS (this Mac)")

# write_note may be absent, a string or a method
class Plain: write_note = "note"
class PerSetting:
    def write_note(self, s): return "tracked" if s.id == "a.b" else ""
assert [model.note_for(a, short) for a in (object(), Plain(), PerSetting())] == ["", "note", "tracked"]
assert model.note_for(PerSetting(), by_id["shell.editor"]) == ""
bad(table(id="Bad Id"), "id must be dotted lowercase: 'Bad Id'")
bad("not toml [", "registry.toml")           # the message names the file
bad("", "no settings")
print("ok")
```

- [ ] **Step 4: Run it to see it fail**

Run: `mise exec python -- python3 settings/tests/test_registry.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings'`

- [ ] **Step 5: Implement `model.py` and `registry.py`**

`default_path()` returns `$DOTFILES_SETTINGS_REGISTRY` when set, else `registry.toml` beside `registry.py` (installed wheel), else `Path(__file__).resolve().parents[2] / "registry.toml"` (source tree and editable install). `load` reports the first problem it finds as `SettingsError`, with the messages in Step 3. A table missing any name in `REQUIRED` is `missing field`. A missing optional field takes its default. `widget` must be in `WIDGETS`. `Setting` objects are built by keyword. `note_for` is `note = getattr(adapter, "write_note", "")`, then `note(s)` when it is callable, else `note`. An id must match `[a-z0-9_]+(\.[a-z0-9_]+)+`. The `KINDS` check is the only place a kind is validated, so a later plan adds its kind to `KINDS` and its adapter to `ADAPTERS` together.

- [ ] **Step 6: Run the test**

Run: `mise exec python -- python3 settings/tests/test_registry.py`
Expected: `ok`

- [ ] **Step 7: Lock, ignore, and wire into the gate**

Run: `uv lock --project settings`. Expected: `settings/uv.lock` is created.

Append to `.gitignore`:

```gitignore
# dotfiles-settings (settings/): uv's environment and build output. uv.lock is tracked.
settings/.venv/
settings/dist/
```

Prettier reads `.gitignore`, so `settings/.venv` needs no `.prettierignore` line. `__pycache__/` is already ignored.

In `bin/lib/check`, the catalog tests sit in an `if` that A1 changed to `if command -v mise > /dev/null && mise where python > /dev/null 2>&1; then`. CI has mise but no mise-installed Python, and `mise exec python` would download one there. Reuse that guard. Do not write a second one. Above the `if`, add the list:

```bash
# dotfiles-settings core tests (settings/): stdlib only, same Python as the catalog tests.
# A listed file that is missing fails the gate.
settings_tests=(settings/tests/test_registry.py)
```

Then add one line to each branch, after the catalog lines:

```bash
  for t in "${settings_tests[@]}"; do mise exec python -- python3 "$t" > /dev/null; done
```

```bash
  for t in "${settings_tests[@]}"; do python3 "$t" > /dev/null; done
```

There is no `[ -f ]` test. `python3` exits 2 on a missing file and `set -e` stops the gate, so a deleted or renamed test cannot be skipped silently. Each later task and plan appends its core test to `settings_tests` in the commit that creates the file.

- [ ] **Step 8: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings/pyproject.toml settings/uv.lock settings/registry.toml \
  settings/src/dotfiles_settings/__init__.py settings/src/dotfiles_settings/model.py \
  settings/src/dotfiles_settings/registry.py settings/tests/test_registry.py .gitignore bin/lib/check
git commit -m "Add the dotfiles-settings package with its registry"
```

---

### Task 2: mise helper and the env adapter

**Files:**

- Create: `settings/src/dotfiles_settings/mise.py`, `adapters/__init__.py`, `adapters/env.py`
- Test: `settings/tests/test_env.py`
- Modify: `bin/lib/check` (append the test to `settings_tests`)

**Interfaces:**

- Consumes: `Setting`, `Value`, `Source`, `SettingsError`, `InvalidValue` from Task 1.
- Produces, in `mise.py`:

```python
FLOOR = (2026, 11, 5)
def run_mise(args: list[str], stdin: str | None = None) -> str   # stdout; runs from $HOME; SettingsError on failure
def config_dir() -> Path          # $MISE_CONFIG_DIR, else ~/.config/mise
def check_version() -> None       # SettingsError below FLOOR or when mise is missing
```

- Produces, in `adapters/env.py`:

```python
def override_path() -> Path                     # config_dir() / "config.override.toml"
def read_override() -> dict[str, str]           # the file's [env] table, {} when the file is absent
def seed_env(keys: set[str]) -> dict[str, str]  # what a new interactive shell exports, overrides excluded
def vscode_env_path() -> Path                   # $VSCODE_SETTINGS_ENV, else ~/.config/dotfiles/vscode.env
def file_seed(key: str) -> str | None           # VSCODE_FONT_PRESET from vscode_env_path(); None for any other key
class EnvAdapter:
    write_note = "Open a new shell to pick this up."
    def read(self, s: Setting) -> Value
    def write(self, s: Setting, value: str) -> None
    def reset(self, s: Setting) -> None
    def watch_paths(self) -> list[Path]         # [override_path(), vscode_env_path()]
```

- Produces, in `adapters/__init__.py`: `ADAPTERS: dict[str, Adapter] = {"env": EnvAdapter()}`. It holds instances.

**How the seed is computed.** The process environment cannot give the seed. `mise activate` has already replaced the variable in an interactive shell, and A1's `zsh/override-env.zsh` replaces it at the end of `.zshenv` in every zsh. So `seed_env` asks a fresh shell:

```python
subprocess.run(["zsh", "-ic", "/usr/bin/env -0"], env=child, stdin=DEVNULL,
               stdout=PIPE, stderr=DEVNULL, timeout=20)
```

`child` is `os.environ` without every key in `keys`, plus `DOTFILES_NO_OVERRIDE_ENV=1`. Stripping the keys stops a value inherited from this process from passing as a seed. `zsh -ic` never reaches a prompt, so the deferred `mise activate` in `zsh/init.zsh` does not run and no override is applied. The guard variable makes A1's `zsh/override-env.zsh` return at once, both where `.zshenv` sources it and where `.zshrc` does. The result is the NUL-split output filtered to `keys`. A non-zero exit or a timeout raises `SettingsError`. `EnvAdapter` calls `seed_env` once per instance, on its first read, and keeps the result. It passes the key of every `env` setting in `registry.load()`, so one shell start serves every row. Measured: 110 ms on this Mac. With `-u EDITOR -u BAT_THEME -u HINDSIGHT_API_LLM_MODEL` in the parent, the child still reported all three from the shell files.

A consequence to state in the README: a variable exported by hand in one terminal is not a seed. The seed is what a new interactive shell gets.

**Read rules.**

| Condition | `source` | `value` | `seed` |
| --- | --- | --- | --- |
| key in `read_override()` | `OVERRIDE` | the override string | seed shell value, else `file_seed(key)`, else `default` if non-empty, else `None` |
| key in the seed shell | `SEED` | the seed value | same as value |
| `file_seed(key)` is not `None` | `SEED` | the file's value | same as value |
| `default != ""` | `DEFAULT` | `default` | same as value |
| otherwise | `UNSET` | `None` | `None` |

For `type = "path"`, a `default` is passed through `os.path.expanduser`. `drift` is always `False` for this adapter: an env setting has no live system state beyond the shell that reads it, and `write_note` covers a stale shell.

**Write rules.** `write` raises `InvalidValue` when the value contains `{{`, `{%`, `{#`, `$`, `\n` or `\r`, naming the offending sequence. Then it runs `mise.run_mise(["set", "--override", f"{s.key}={value}"])`. The value is one argv element, so no shell sees it. Then it re-reads the file and raises `SettingsError(f"{s.key} was changed by another writer, try again")` when the stored value differs. `reset` runs `mise.run_mise(["unset", "--override", s.key])` only when the key is in the file, so it never creates the file.

`read_override` raises `SettingsError(f"{path}: {error}")` on `tomllib.TOMLDecodeError`, and ignores `[env]` entries whose value is not a string.

**The file seed.** `file_seed("VSCODE_FONT_PRESET")` returns the text after `=` on the `VSCODE_FONT_PRESET=` line of `vscode_env_path()`, with one pair of surrounding quotes removed. It returns `None` when the file or the line is missing, and for every other key. It reads the file on each call, so a `vscode-settings --choose` run shows up on the next poll. The path honours `VSCODE_SETTINGS_ENV` because `bin/vscode-settings` does. Without this, a user who saved `warp` would see `iosevka, default` while VS Code renders `warp`.

`run_mise` runs `os.environ.get("DOTFILES_SETTINGS_MISE", "mise")` with `cwd=Path.home()`, so the folder the UI was started in never decides whether mise works. A non-zero exit becomes `SettingsError` carrying mise's stderr. `FileNotFoundError` becomes `SettingsError("dotfiles-settings needs mise 2026.11.5 or newer, and mise is not on PATH")`. `check_version` parses the first whitespace-separated token of `mise --version` (output on this Mac: `2026.11.5 macos-arm64 (2026-11-08)`) into a tuple of ints and raises `SettingsError(f"dotfiles-settings needs mise 2026.11.5 or newer, found {token}")` below `FLOOR`.

- [ ] **Step 1: Write the failing test `settings/tests/test_env.py`**

The test sets `MISE_CONFIG_DIR` and `HOME` to two temp dirs and `os.chdir`s to a third before importing the package. It writes `mise.toml` with `[env]` and `T_PROJECT = "x"` into that third dir and never trusts it, so every mise call in the test is made from a folder holding an untrusted config. It points `VSCODE_SETTINGS_ENV` at a path in the temp tree that does not exist yet. It builds `Setting` objects by hand with a helper `S(key, type="string", default="", true_value="")`, whose `id` is `key.lower()`. Part one stubs `env.seed_env` and uses real mise. It runs only when `shutil.which("mise")` finds mise, and prints `skipped: mise not found` otherwise. Part two needs no mise.

```python
# part one: real mise, stubbed seed shell
env.seed_env = lambda keys: {"T_LOCAL": "from-zsh-local", "T_SEEDED": "seed"}
a = env.EnvAdapter()
assert a.read(S("T_NONE")) == Value("t_none", None, Source.UNSET, None, False)
assert a.read(S("T_DEF", default="10")) == Value("t_def", "10", Source.DEFAULT, "10", False)
assert a.read(S("T_SEEDED")).source is Source.SEED

# run_mise runs from $HOME: the untrusted mise.toml in the cwd is never read.
# Measured without cwd=Path.home(): `mise env --json` exits 1 here with "not trusted".
assert "T_PROJECT" not in json.loads(mise.run_mise(["env", "--json"]))

for raw in ("hello world", "a=b=c", "it's \"q\" \\ back", "`id` ; rm -rf / | #c", "--help -x", "café ☕", ""):
    a.write(S("T_VAL"), raw)
    assert a.read(S("T_VAL")).value == raw, raw
    assert json.loads(mise.run_mise(["env", "--json"]))["T_VAL"] == raw, raw

for raw, needle in (("{{ x }}", "{{"), ("{% if %}", "{%"), ("{# c #}", "{#"), ("$HOME/x", "$"), ("a\nb", "line break")):
    raises(lambda: a.write(S("T_VAL"), raw), InvalidValue, needle)
assert a.read(S("T_VAL")).value == ""            # a refused write changed nothing

# a switch that is on by default (A3): unset reads as on, off is stored as "" and the key stays, reset restores the default
ON = S("T_ON", type="bool", default="1", true_value="1")
assert a.read(ON) == Value("t_on", "1", Source.DEFAULT, "1", False)
a.write(ON, "")
assert a.read(ON) == Value("t_on", "", Source.OVERRIDE, "1", False) and env.read_override()["T_ON"] == ""
a.reset(ON)
assert a.read(ON).source is Source.DEFAULT and "T_ON" not in env.read_override()

# a key ~/.zsh.local also exports: the override wins, the seed is what reset restores
a.write(S("T_LOCAL"), "ui")
assert a.read(S("T_LOCAL")) == Value("t_local", "ui", Source.OVERRIDE, "from-zsh-local", False)
a.reset(S("T_LOCAL"))
assert a.read(S("T_LOCAL")) == Value("t_local", "from-zsh-local", Source.SEED, "from-zsh-local", False)
a.reset(S("T_LOCAL"))                             # resetting twice is fine

# the VS Code preset: the saved file is the seed when no shell exports the key
P = S("VSCODE_FONT_PRESET", default="iosevka")
assert a.read(P) == Value("vscode_font_preset", "iosevka", Source.DEFAULT, "iosevka", False)
env.vscode_env_path().write_text("VSCODE_FONT_PRESET=warp\n")
assert a.read(P) == Value("vscode_font_preset", "warp", Source.SEED, "warp", False)
a.write(P, "fira")
assert a.read(P) == Value("vscode_font_preset", "fira", Source.OVERRIDE, "warp", False)
a.reset(P)
assert a.read(P).value == "warp"
assert env.file_seed("T_VAL") is None
assert a.watch_paths() == [env.override_path(), env.vscode_env_path()]

# a second writer between our write and our re-read is reported
real = mise.run_mise
mise.run_mise = then_clobber          # calls real(args, stdin), then real(["set", "--override", "T_RACE=other"])
raises(lambda: a.write(S("T_RACE"), "mine"), SettingsError, "changed by another writer")
mise.run_mise = real

# invalid TOML: the error names the file
env.override_path().write_text("[env]\nbroken = [\n")
raises(lambda: a.read(S("T_VAL")), SettingsError, "config.override.toml")
env.override_path().unlink()
assert env.read_override() == {} and not env.override_path().exists()
a.reset(S("T_VAL")); assert not env.override_path().exists()

# part two: version floor and a missing binary, through a fake mise script
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.11.4 macos-arm64 (2026-11-01)")
raises(mise.check_version, SettingsError, "needs mise 2026.11.5 or newer, found 2026.11.4")
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.12.0 macos-arm64")
mise.check_version()
os.environ["DOTFILES_SETTINGS_MISE"] = str(tmp / "absent")
raises(mise.check_version, SettingsError, "mise is not on PATH")

# seed_env against a real zsh with its own ZDOTDIR
(zdot / ".zshrc").write_text("export T_RC=rc\n")
os.environ.update(ZDOTDIR=str(zdot), T_RC="stale", T_ONLY_HERE="stale")
assert env.seed_env_real({"T_RC", "T_ONLY_HERE"}) == {"T_RC": "rc"}

# A1's cache honours the guard seed_env relies on
guard = Path(__file__).resolve().parents[2] / "zsh/override-env.zsh"
assert "DOTFILES_NO_OVERRIDE_ENV" in guard.read_text()
print("ok")
```

`seed_env_real` is the name the test binds to the original `env.seed_env` before stubbing it. `fake(text)` writes an executable script that prints `text`.

- [ ] **Step 2: Run it to see it fail**

Run: `mise exec python -- python3 settings/tests/test_env.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.adapters'`

- [ ] **Step 3: Confirm A1's guard is present**

Run: `grep -c DOTFILES_NO_OVERRIDE_ENV zsh/override-env.zsh`
Expected: 1 or more. A1 ships the guard with its own test. If it prints 0, stop and report: A1 has not landed as planned.

- [ ] **Step 4: Implement `mise.py`, `adapters/env.py`, `adapters/__init__.py`**

Adapters call mise as `mise.run_mise(...)` through the module (`from dotfiles_settings import mise`), so a test can replace the function by assignment.

- [ ] **Step 5: Run the tests**

Run: `mise exec python -- python3 settings/tests/test_env.py && bash bin/lib/test-override-env`
Expected: `ok`, and A1's self-check still passes.

- [ ] **Step 6: Verify and commit**

In `bin/lib/check`, append `settings/tests/test_env.py` to `settings_tests`.

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings/src/dotfiles_settings/mise.py settings/src/dotfiles_settings/adapters/__init__.py \
  settings/src/dotfiles_settings/adapters/env.py settings/tests/test_env.py bin/lib/check
git commit -m "Read and write env settings through mise's override file"
```

---

### Task 3: CLI and the launcher

**Files:**

- Create: `settings/src/dotfiles_settings/cli.py`, `__main__.py`, `bin/dotfiles-settings`
- Test: `settings/tests/test_cli.py`
- Modify: `bin/lib/check` (append the test to `settings_tests`). Not `.claude/settings.json` or `bin/lib/test-conventions`: the ask rules are A7's (Step 6)

**Interfaces:**

- Consumes: `registry.load`, `ADAPTERS`, `mise.check_version`, `model.note_for`, the model.
- Produces:

```python
def normalize(s: Setting, raw: str) -> str      # InvalidValue on a bad value
def to_json(s: Setting, v: Value) -> dict
def main(argv: list[str] | None = None) -> None # raises SystemExit with the contract's code
```

**Contract.**

| Command | Output | Exit |
| --- | --- | --- |
| `list [--section S] [--json]` | JSON array, or one `id<TAB>value<TAB>source` line per setting | 0 |
| `get <id> [--json]` | JSON object, or the value alone (empty line when unset) | 0, or 2 for an unknown id |
| `set <id> <value>` | nothing on stdout, the note on stderr | 0, 2 unknown id or invalid value, 3 read-only |
| `reset <id>` | nothing on stdout, the note on stderr | 0, 2 unknown id, 3 read-only |
| `apply <kind>` | the adapter's lines, or `<kind>: nothing to apply` | 0, 2 unknown kind |
| `tui` | runs `tui.run()` | 0 |
| `serve [--no-open]` | runs `serve.run(open_browser)` | 0 |

A JSON object has exactly these eleven keys: `setting_id`, `value`, `source`, `seed`, `drift`, `label`, `section`, `type`, `choices`, `widget`, `access`. `source` is the lowercase enum value. `value` and `seed` are strings or `null`. `choices` is an array of strings, empty unless the type is `enum`. `widget` is `""`, `"lines"` or `"seats"`.

The note is `model.note_for(adapter, s)`. It is printed to stderr once, after the adapter's `write` or `reset` returned, and only when it is not empty. A failed or refused command prints its error and no note.

`set` passes the adapter the value `normalize` returned. For a bool that is the setting's `true_value` for true and `""` for false, whatever word the user typed. An adapter never sees `on`, `off`, `true` or `false` from the CLI or the TUI. A test of a bool in a later plan goes through `cli.normalize`, not straight to an adapter's converter.

`main` calls `mise.check_version()` first for every subcommand. Any `InvalidValue` exits 2, any other `SettingsError` exits 1, each printing `dotfiles-settings: <message>` to stderr with no traceback. A `ro` setting exits 3 with `dotfiles-settings: <id> is read-only` before `normalize` or any adapter runs. argparse's own usage errors already exit 2. `--section` matches the section name case-insensitively, and an unknown section exits 2.

`normalize` rules:

| type | Accepts | Returns |
| --- | --- | --- |
| `bool` | `true on yes 1` / `false off no 0`, any case | `true_value` / `""` |
| `int` | optional `-`, then digits | `str(int(raw))` |
| `enum` | a member of `choices` | unchanged |
| `path` | anything that is absolute after `os.path.expanduser` | the expanded path |
| `string` | anything | unchanged |

- [ ] **Step 1: Write the failing test `settings/tests/test_cli.py`**

The test sets `MISE_CONFIG_DIR`, `HOME` and the cwd to temp dirs, points `DOTFILES_SETTINGS_REGISTRY` at a five-entry fixture registry (`t.flag` bool with `true_value = "1"`, `t.count` int with `default = "10"`, `t.pick` enum of `a`/`b`, `t.dir` path, `t.locked` string `ro`), and stubs `env.seed_env = lambda keys: {"T_LOCKED": "1"}`. `run(*argv)` calls `cli.main(list(argv))` with stdout and stderr captured and returns `(code, out, err)`. The mise-backed part is skipped when mise is not found, as in Task 2.

```python
code, out, _ = run("list", "--json")
rows = json.loads(out)
assert code == 0 and [r["setting_id"] for r in rows] == ["t.flag", "t.count", "t.pick", "t.dir", "t.locked"]
assert set(rows[0]) == {"setting_id", "value", "source", "seed", "drift", "label", "section", "type",
                        "choices", "widget", "access"}
assert rows[2]["choices"] == ["a", "b"] and rows[0]["choices"] == [] and rows[0]["widget"] == ""
assert rows[1]["value"] == "10" and rows[1]["source"] == "default"
assert rows[0]["value"] is None and rows[0]["source"] == "unset"

assert run("set", "t.flag", "on")[0] == 0
assert json.loads(run("get", "t.flag", "--json")[1]) == {
    "setting_id": "t.flag", "value": "1", "source": "override", "seed": None, "drift": False,
    "label": "Flag", "section": "One", "type": "bool", "choices": [], "widget": "", "access": "rw"}
assert run("set", "t.flag", "off")[0] == 0 and run("get", "t.flag")[1] == "\n"
code, _, err = run("reset", "t.flag")
assert code == 0 and "Open a new shell" in err
assert json.loads(run("get", "t.flag", "--json")[1])["source"] == "unset"

assert run("set", "t.count", "007")[0] == 0 and run("get", "t.count")[1] == "7\n"
assert run("set", "t.dir", "~/x")[0] == 0 and run("get", "t.dir")[1] == str(Path.home() / "x") + "\n"
assert len(json.loads(run("list", "--section", "one", "--json")[1])) == 2

for argv, code in ((("get", "nope"), 2), (("set", "nope", "1"), 2), (("reset", "nope"), 2),
                   (("set", "t.flag", "maybe"), 2), (("set", "t.count", "ten"), 2),
                   (("set", "t.pick", "c"), 2), (("set", "t.dir", "relative/x"), 2),
                   (("set", "t.pick", "{{ a }}"), 2), (("list", "--section", "nope"), 2),
                   (("apply", "nope"), 2), (("set", "t.locked", "0"), 3), (("reset", "t.locked"), 3)):
    got, _, err = run(*argv)
    assert got == code and err.startswith("dotfiles-settings: ") and "Traceback" not in err, (argv, got, err)
assert "T_LOCKED" not in env.read_override()
assert run("apply", "env") == (0, "env: nothing to apply\n", "")

# invalid TOML in the override file
env.override_path().write_text("[env]\nbroken = [\n")
code, _, err = run("list", "--json")
assert code == 1 and "config.override.toml" in err and "Traceback" not in err
env.override_path().unlink()

# mise older than the floor, then missing: every subcommand exits 1 with one line
for fake_mise, needle in ((fake("2026.11.4"), "found 2026.11.4"), (str(tmp / "absent"), "not on PATH")):
    os.environ["DOTFILES_SETTINGS_MISE"] = fake_mise
    for argv in (("list",), ("get", "t.flag"), ("set", "t.flag", "on"), ("tui",), ("serve", "--no-open")):
        code, out, err = run(*argv)
        assert (code, out) == (1, "") and needle in err and err.count("\n") == 1, (argv, err)
print("ok")
```

- [ ] **Step 2: Run it to see it fail**

Run: `mise exec python -- python3 settings/tests/test_cli.py`
Expected: `ImportError: cannot import name 'cli'`

- [ ] **Step 3: Implement `cli.py` and `__main__.py`**

Use `argparse` with subparsers. Import `dotfiles_settings.tui` and `dotfiles_settings.serve` inside their branches. An `ImportError` for `textual` there becomes `SettingsError("tui and serve need Textual. Run bin/dotfiles-settings, or install the package with uv.")`. `__main__.py` is `from dotfiles_settings.cli import main` and `main()`.

- [ ] **Step 4: Write `bin/dotfiles-settings`**

```bash
#!/bin/bash
#
# See and change the settings this dotfiles repo manages, in the terminal or a browser.
#
# - Open the terminal UI:
#
# `dotfiles-settings tui`
#
# - Open the same UI in a browser tab (local only, behind a per-run token):
#
# `dotfiles-settings serve`
#
# - List every setting with its value and where the value comes from:
#
# `dotfiles-settings list`
#
# - Change a setting, or go back to what the shell files set:
#
# `dotfiles-settings set {{updates.trim_ca_roots}} {{on}}`
# `dotfiles-settings reset {{updates.trim_ca_roots}}`
#
# - Read one setting as JSON:
#
# `dotfiles-settings get {{shell.editor}} --json`
#
# ---
# Package: settings/ (registry.toml lists the settings). Changes go to mise's
# config.override.toml and beat exports in zsh/env.zsh and ~/.zsh.local.
# Exit codes: 0 ok, 1 failure, 2 unknown id or invalid value, 3 read-only.
#
# License: MIT

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"

if ! command -v uv &> /dev/null; then
  echo "dotfiles-settings: needs uv (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

# uv run, not a uv tool install: it runs the clone's code and lockfile, so an
# edit to registry.toml needs no reinstall. Measured 100 ms against 57 ms.
exec uv run --quiet --locked --project "$DOTFILES_DIR/settings" dotfiles-settings "$@"
```

Then `chmod +x bin/dotfiles-settings`. `--project` does not change the working directory, which is why `run_mise` sets its own. The first run creates `settings/.venv` (gitignored in Task 1) and downloads the dependencies, so it needs the network and takes several seconds. Later runs take the times below.

Launcher choice, measured on this Mac with the same wrapper around each command (three runs each): `uv run --project` 101 to 113 ms, the venv's console script directly 57 ms, a plain `python3 -m` of a stdlib-only module 55 ms. `uv run` costs about 45 ms and is the one that cannot drift from the clone.

- [ ] **Step 5: Run the tests and the launcher**

Run: `mise exec python -- python3 settings/tests/test_cli.py`
Expected: `ok`

Run: `bin/dotfiles-settings list | head -3`
Expected: three tab-separated lines, the first starting `updates.trim_ca_roots`. This is the first run, so uv creates `settings/.venv` and downloads the dependencies before the lines appear.

Run: `cd "$(mktemp -d)" && printf '[env]\nX = "1"\n' > mise.toml && "$OLDPWD/bin/dotfiles-settings" list | head -1; cd "$OLDPWD"`
Expected: the same first line. The folder holds an untrusted `mise.toml` and the command still works.

Run: `help dotfiles-settings`
Expected: the header renders as a tldr page with no error.

- [ ] **Step 6: No ask rule in this phase**

Do not edit `.claude/settings.json` or `bin/lib/test-conventions` here. Spec decision 7 puts every `ask` rule the plans add in the last phase, so A7's Task 8 adds the eighteen rules for `dotfiles-settings set`, `reset` and `apply` (six spellings each, the form the repo uses for `sysup` and `set-defaults`) with their `test-conventions` loop. Until then the owner's go-ahead in chat guards a real `set`, `reset` or `apply` from an agent session. What A7 needs from this plan, measured here: against the tracked `rtk/config.toml` in a scratch HOME, `rtk rewrite` returns nothing for `dotfiles-settings set x`, `reset x` and `apply x`, so those rules need no `rtk/config.toml` entry. A call spelled `uv run --project settings dotfiles-settings set ...` is not covered by them.

- [ ] **Step 7: Verify and commit**

In `bin/lib/check`, append `settings/tests/test_cli.py` to `settings_tests`.

Run: `pnpm check`. Expected: exit 0. The shebang scan in `bin/lib/check` picks the launcher up for `bash -n` and shellcheck.

```bash
git add settings/src/dotfiles_settings/cli.py settings/src/dotfiles_settings/__main__.py \
  settings/tests/test_cli.py bin/dotfiles-settings bin/lib/check
git commit -m "Add the dotfiles-settings CLI and its launcher"
```

---

### Task 4: Terminal UI

**Files:**

- Create: `settings/src/dotfiles_settings/tui.py`
- Test: `settings/tests/test_tui.py`
- Modify: `bin/lib/check`

**Interfaces:**

- Consumes: `registry.load`, `ADAPTERS`, `cli.normalize`, `model.note_for`, each adapter's optional `watch_paths`.
- Produces:

```python
def widget_for(s: Setting, v: Value) -> Widget
class SettingsApp(App):
    def __init__(self, settings: list[Setting] | None = None, adapters: dict[str, Adapter] | None = None)
def run() -> None            # SettingsApp().run()
```

`None` for `settings` means `registry.load()`, and `None` for `adapters` means the real `ADAPTERS`. An empty list or dict means empty and is used as given. The constructor tests `is None`, never truthiness, so a test that passes `[]` or `{}` cannot be handed the real registry.

**Layout and behaviour.** Checked against Textual 8.2.8.

- A `ListView` with id `sections` on the left, one `ListItem` per section in registry order. Highlighting a section shows its rows in a `VerticalScroll` with id `rows`. A `Footer` shows the bindings.
- A row is the label, the widget, a `Static` marker and the help text. With `slug = s.id.replace(".", "-")`, the ids are `w-<slug>` for the widget, `m-<slug>` for the marker and `r-<slug>` for the reset `Button`.
- `widget_for`: `bool` gives `Switch(value=v.value == s.true_value)`, `enum` gives `Select([(c, c) for c in s.choices], allow_blank=True)` with the current value selected when it is a choice (an empty `Select` reads `Select.NULL` on 8.2.8), `int` gives `Input(type="integer")`, `string` and `path` give `Input`. `access == "ro"` sets `disabled=True` and the row gets no reset button.
- The marker text is `override` with the class `-override` when `v.source is Source.OVERRIDE`, and the lowercase source name otherwise. On an overridden row the marker is followed by `seed: <seed>` (or `seed: unset`) and the reset button.
- A change is committed on `Switch.Changed`, `Select.Changed` and `Input.Submitted` (Enter). The handler passes the widget's value through `cli.normalize` and calls the adapter's `write`. A `Switch` is passed as `"on"` or `"off"`, so the adapter receives `true_value` or `""`, the same as from the CLI. It does nothing when the normalized value equals the row's current value. That check is required: `Select.Changed` fires once on mount with the initial value, and a redraw that sets a widget's value fires its `Changed` event too (both measured on 8.2.8).
- Reset is the row's button and the binding `ctrl+r` on the focused row. A plain `r` would be typed into an `Input`.
- After a write or reset succeeds, the row is re-read and redrawn, and `model.note_for(adapter, s)`, when not empty, is shown with `self.notify(note)`. Nothing is shown before the write. A `SettingsError` is shown with `self.notify(str(error), severity="error")` and the row is redrawn from a fresh read, so a refused value does not stay on screen.
- `set_interval(2.0, ...)` re-reads every value when any watched file's mtime has changed (or a file appeared or vanished). The watched files are the union of `watch_paths()` over the app's adapters that define it. This is how a change from a second UI, a hand edit or another tool shows up.
- When a read raises `SettingsError`, a `Static` with id `error` shows the message, every row widget is disabled, and the next successful poll clears both.

- [ ] **Step 1: Write the failing test `settings/tests/test_tui.py`**

The test builds a `FakeAdapter` holding a dict of overrides and a dict of seeds, with the spec's three methods, a `write_note = "noted"`, a `watch_paths()` that returns one temp file, a `touch()` that rewrites that file, a `fail: str | None` that makes `read` raise `SettingsError(fail)`, a `refuse: str | None` that makes `write` raise `SettingsError(refuse)`, and a `writes` list. Settings: `t.flag` (bool, `true_value="1"`), `t.name` (string, seed `"seeded"`), `t.pick` (enum `a`/`b`), `t.locked` (string, `ro`), all in section `One`, and `u.other` in section `Two`.

```python
async def main():
    fake = FakeAdapter(seeds={"T_NAME": "seeded"})
    app = SettingsApp(SETTINGS, {"env": fake})
    async with app.run_test(size=(120, 40), notifications=True) as pilot:
        await pilot.pause()
        assert [str(i.query_one(Label).content) for i in app.query_one("#sections", ListView).children] == ["One", "Two"]
        assert isinstance(app.query_one("#w-t-flag"), Switch)
        assert isinstance(app.query_one("#w-t-pick"), Select)
        assert isinstance(app.query_one("#w-t-name"), Input) and app.query_one("#w-t-name", Input).value == "seeded"
        assert app.query_one("#w-t-locked").disabled and not app.query("#r-t-locked")
        assert fake.writes == []                               # mounting wrote nothing
        assert "seed" in str(app.query_one("#m-t-name", Static).content)

        app.query_one("#w-t-flag").focus(); await pilot.press("enter"); await pilot.pause()
        assert fake.writes == [("T_FLAG", "1")]
        assert app.query_one("#m-t-flag").has_class("-override")
        assert "override" in str(app.query_one("#m-t-flag", Static).content)
        assert any("noted" in str(n.message) for n in app._notifications)

        await pilot.press("ctrl+r"); await pilot.pause()        # reset the focused row
        assert "T_FLAG" not in fake.overrides and not app.query_one("#m-t-flag").has_class("-override")
        assert app.query_one("#w-t-flag", Switch).value is False

        app.query_one("#w-t-name", Input).focus()
        await pilot.press("end", "!", "enter"); await pilot.pause()
        assert fake.overrides["T_NAME"] == "seeded!"
        await pilot.click("#r-t-name"); await pilot.pause()
        assert app.query_one("#w-t-name", Input).value == "seeded"

        fake.refuse = "nope"                                    # write raises SettingsError("nope")
        app.query_one("#w-t-name", Input).focus()
        await pilot.press("end", "?", "enter"); await pilot.pause()
        assert app.query_one("#w-t-name", Input).value == "seeded"
        assert any(n.severity == "error" and "nope" in str(n.message) for n in app._notifications)
        fake.refuse = None

        fake.overrides["T_PICK"] = "b"; fake.touch()            # a second UI wrote
        await pilot.pause(2.5)
        assert app.query_one("#w-t-pick", Select).value == "b"

        fake.fail = "config.override.toml: bad"; fake.touch()   # hand-edited to invalid TOML
        await pilot.pause(2.5)
        assert "config.override.toml" in str(app.query_one("#error", Static).content)
        assert app.query_one("#w-t-flag").disabled
        fake.fail = None; fake.touch()
        await pilot.pause(2.5)
        assert not app.query("#error") and not app.query_one("#w-t-flag").disabled

    empty = SettingsApp([], {})                                 # empty means empty, not "load the real ones"
    async with empty.run_test(size=(120, 40)) as pilot:
        await pilot.pause()
        assert not empty.query("#sections ListItem")
asyncio.run(main())
print("ok")
```

`fake.touch()` rewrites the temp file `fake.watch_paths()` returns, so the poll sees a new mtime. The test does not patch `env.override_path`.

Attribute names checked on Textual 8.2.8 with a scratch app: `Static("hello").renderable` raises `AttributeError` and `.content` returns `hello` (a `Label` is a `Static`). `App._notifications` holds objects with `.message` and `.severity`, and `severity` is `"error"` after `notify(..., severity="error")`. `Enter` on a focused `Switch` toggles it. `ctrl+r` reaches an app binding while an `Input` has focus. An empty `query()` is falsy.

- [ ] **Step 2: Run it to see it fail**

Run: `uv run --quiet --locked --project settings python settings/tests/test_tui.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.tui'`

- [ ] **Step 3: Implement `tui.py`**

- [ ] **Step 4: Run the test, then look at the app**

Run: `uv run --quiet --locked --project settings python settings/tests/test_tui.py`
Expected: `ok`

Run: `bin/dotfiles-settings tui`, change `updates.slow_step_seconds` to 5, confirm the marker reads `override` with `seed: unset`, press `ctrl+r`, confirm it returns to 10 with `default`, quit. Then `bin/dotfiles-settings get updates.slow_step_seconds --json` shows `"source": "default"`.

- [ ] **Step 5: Wire into the gate**

In `bin/lib/check`, after the loop from Task 1, add a block guarded by `command -v uv` that runs `uv run --quiet --locked --project settings python settings/tests/test_tui.py > /dev/null`. Task 5 adds the line for `test_serve.py`. No `[ -f ]` guard: a listed file that is missing fails the gate. Without uv, print `check: uv not found, skipping the dotfiles-settings UI tests` to stderr, as the minijinja block does.

- [ ] **Step 6: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings/src/dotfiles_settings/tui.py settings/tests/test_tui.py bin/lib/check
git commit -m "Add the dotfiles-settings terminal UI"
```

---

### Task 5: Browser UI

**Files:**

- Create: `settings/src/dotfiles_settings/serve.py`, `settings/src/dotfiles_settings/templates/app_index.html`, `settings/src/dotfiles_settings/templates/LICENSE-textual-serve`
- Test: `settings/tests/test_serve.py`
- Modify: `bin/lib/check` (one line in the uv block from Task 4)

**Interfaces:**

- Consumes: `python -m dotfiles_settings tui` from Tasks 3 and 4.
- Produces:

```python
TEMPLATES = Path(__file__).parent / "templates"  # passed to textual-serve as templates_path
def free_port() -> int
def guard(port: int, token: str)                # an aiohttp middleware
class GuardedServer(textual_serve.server.Server):
    def __init__(self, command: str, port: int, token: str)
def run(open_browser: bool = True) -> None
```

**What textual-serve 1.1.3 does, read from the installed source (`textual_serve/server.py`, `app_service.py`, `templates/app_index.html`).**

- It has no token and no authentication of any kind.
- `handle_websocket` calls `websocket.prepare(request)` for any request. It never reads the `Origin` header. Any page open in the browser could connect to `/ws` and drive the app.
- Each WebSocket connection starts `command` as a new subprocess through `asyncio.create_subprocess_shell`, so `command` is a shell string.
- `Server.__init__(command, host="localhost", port=8000, title=None, public_url=None, statics_path="./static", templates_path="./templates")`. `public_url` is built from `port` in the constructor, so port 0 cannot be used. The wrapper must choose the port first. Both paths are joined onto the package folder with `/`, so an absolute path replaces it. `_make_app` loads templates with `jinja2.FileSystemLoader(self.templates_path)`, and `handle_index` renders `app_index.html` from there. Passing `templates_path` alone leaves `statics_path`, and so `/static`, on textual-serve's own folder.
- Routes: `/`, `/ws`, `/download/{key}`, `/static`. The page's script opens `new WebSocket(url + "?width=..&height=..")`, so it sends no token of its own. The browser does send cookies on that same-origin handshake.
- `_make_app()` is an async method returning the `aiohttp.web.Application`, and `serve()` runs it with `web.run_app(host=self.host, port=self.port)`.
- `templates/app_index.html` (160 lines) links a stylesheet at `https://fonts.googleapis.com/css?family=Roboto%20Mono` (lines 6 to 9) and names `"Roboto Mono"` in its CSS. `static/js/textual.js` asks xterm for `'Roboto Mono', Monaco, 'Courier New', monospace`. The package also ships `static/fonts/RobotoMono-VariableFont_wght.ttf` and an italic variant, which no file references. The only other absolute URLs in the template and static files are the SVG namespace `http://www.w3.org/2000/svg` and two comments in `xterm.css`, none of which the browser fetches. So the Google link is the page's only third-party request, and spec decision 4 removes it.

**The template copy.** Run `uv run --quiet --locked --project settings python -c 'import textual_serve, pathlib; print(pathlib.Path(textual_serve.__file__).parent)'` to find the locked textual-serve. Copy its `templates/app_index.html` to `settings/src/dotfiles_settings/templates/app_index.html`, and its `LICENSE` from the matching `textual_serve-<version>.dist-info/licenses/` folder to `templates/LICENSE-textual-serve`. In the copy, replace exactly these four lines:

```html
    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css?family=Roboto%20Mono"
    />
```

with:

```html
    <style>
      @font-face {
        font-family: "Roboto Mono";
        src: url("{{ config.static.url }}fonts/RobotoMono-VariableFont_wght.ttf");
        font-style: normal;
      }
    </style>
```

Change nothing else, so the test below can rebuild the copy from upstream. `{{ config.static.url }}` is the variable the template already uses for `xterm.css` and `textual.js`. hatchling's `packages = ["src/dotfiles_settings"]` includes non-Python files, so the wheel carries the folder (checked in a scratch build: the wheel lists `dotfiles_settings/templates/app_index.html`). `bin/lib/check` runs Prettier on no `*.html` glob, so the copy keeps upstream's formatting.

When textual-serve is upgraded in `uv.lock`, `test_serve.py` compares the copy with the new upstream template. If upstream changed the template, the test fails: copy the new file, make the same replacement, and check that the new template adds no other third-party URL (the test's URL scan covers that too). The comment above `TEMPLATES` in `serve.py` says this in one line.

**The wrapper.** `GuardedServer.__init__` calls `super().__init__(command, host="127.0.0.1", port=port, title="dotfiles settings", templates_path=TEMPLATES)`. Its `_make_app` awaits the parent's and appends `guard(port, token)` to `app.middlewares`. The middleware applies to every route, in this order:

1. `Host` header is not exactly `127.0.0.1:<port>`: 403. This stops DNS rebinding.
2. An `Origin` header is present and is not `http://127.0.0.1:<port>`: 403.
3. The path is `/ws` and there is no `Origin` header: 403.
4. The query has `token` equal to the run's token (`secrets.compare_digest`): answer 302 to `/` and set the cookie `dotfiles_settings_<port>` to the token with `httponly=True`, `samesite="Strict"`, `path="/"`. The redirect takes the token out of the address bar.
5. The cookie `dotfiles_settings_<port>` does not equal the token: 403.
6. Otherwise call the handler.

The cookie name carries the port because cookies are shared across ports of one host. Two `serve` runs would otherwise overwrite each other's cookie.

`run`: `port = free_port()` (bind a socket to `("127.0.0.1", 0)`, read the port, close it), `token = secrets.token_urlsafe(32)`, print `http://127.0.0.1:<port>/?token=<token>`, call `webbrowser.open(url)` unless `open_browser` is false, then `GuardedServer(shlex.join([sys.executable, "-m", "dotfiles_settings", "tui"]), port, token).serve()`. Ctrl+C stops it.

This design was run as a prototype against textual-serve 1.1.3 and aiohttp 3.14.5. Results: no token 403, wrong token 403, right token 302 with the cookie, static file without the cookie 403, cookie with `Host: localhost:<port>` 403, cookie with a foreign `Origin` 403, WebSocket with the cookie and no `Origin` 403, WebSocket with the cookie and the right `Origin` opened and received data.

- [ ] **Step 1: Write the failing test `settings/tests/test_serve.py`**

```python
from aiohttp.test_utils import TestClient, TestServer
import textual_serve

GOOGLE_LINK = '''    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css?family=Roboto%20Mono"
    />
'''
LOCAL_FONT = '''    <style>
      @font-face {
        font-family: "Roboto Mono";
        src: url("{{ config.static.url }}fonts/RobotoMono-VariableFont_wght.ttf");
        font-style: normal;
      }
    </style>
'''

# the shipped copy is upstream's template with only the font link replaced.
# A textual-serve upgrade that changes the template fails here: redo the copy (Task 5).
upstream = (Path(textual_serve.__file__).parent / "templates/app_index.html").read_text()
assert upstream.count(GOOGLE_LINK) == 1, "textual-serve's template changed its font link"
assert (serve.TEMPLATES / "app_index.html").read_text() == upstream.replace(GOOGLE_LINK, LOCAL_FONT), \
    "templates/app_index.html no longer matches textual-serve's template"

def third_party(body, port):
    own = (f"http://127.0.0.1:{port}/", f"ws://127.0.0.1:{port}/")
    urls = re.findall(r"""(?:[a-z]+:)?//[^\s"'<>)]+""", body)
    return [u for u in urls if not u.startswith(own) and u != "http://www.w3.org/2000/svg"]

async def main():
    port = serve.free_port()
    server = serve.GuardedServer("true", port, "tok")
    assert server.host == "127.0.0.1"
    assert server.templates_path == serve.TEMPLATES
    app = await server._make_app()
    origin = f"http://127.0.0.1:{port}"
    async with TestClient(TestServer(app, host="127.0.0.1", port=port)) as c:
        assert (await c.get("/")).status == 403                         # no token
        assert (await c.get("/?token=nope")).status == 403
        assert (await c.get("/static/js/textual.js")).status == 403
        assert (await c.get("/ws", headers={"Origin": origin})).status == 403
        r = await c.get("/?token=tok", allow_redirects=False)
        cookie = r.cookies[f"dotfiles_settings_{port}"]
        assert r.status == 302 and r.headers["Location"] == "/"
        assert cookie.value == "tok" and cookie["httponly"] and cookie["samesite"] == "Strict"
        page = await c.get("/")                                         # the client now holds the cookie
        body = await page.text()
        assert page.status == 200 and "fonts.googleapis.com" not in body
        assert third_party(body, port) == [], third_party(body, port)   # spec decision 4
        assert (await c.get("/static/js/textual.js")).status == 200
        assert (await c.get("/static/fonts/RobotoMono-VariableFont_wght.ttf")).status == 200
        assert (await c.get("/", headers={"Host": f"localhost:{port}"})).status == 403
        assert (await c.get("/", headers={"Host": f"evil.example:{port}"})).status == 403
        assert (await c.get("/", headers={"Origin": "http://evil.example"})).status == 403
        assert (await c.get("/ws")).status == 403                       # cookie, but no Origin
        assert (await c.get("/ws", headers={"Origin": "http://evil.example"})).status == 403
        ws = await c.ws_connect("/ws?width=80&height=24", headers={"Origin": origin})
        await ws.close()
    a, b = serve.free_port(), serve.free_port()
    assert 1024 < a < 65536 and 1024 < b < 65536
asyncio.run(main())
print("ok")
```

The URL scan was run against textual-serve 1.1.3 in a scratch venv, rendering `/` through a plain `Server` on `127.0.0.1`: with upstream's template it returns `['https://fonts.googleapis.com/css?family=Roboto%20Mono']`, and with the copy described above it returns `[]`, while `/static/fonts/RobotoMono-VariableFont_wght.ttf` answers 200.

- [ ] **Step 2: Run it to see it fail**

Run: `uv run --quiet --locked --project settings python settings/tests/test_serve.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.serve'`

- [ ] **Step 3: Write the template copy, then implement `serve.py`**

Make the copy and the license file as "The template copy" above says. Then write `serve.py`.

- [ ] **Step 4: Run the test, then the real thing**

Run: `uv run --quiet --locked --project settings python settings/tests/test_serve.py`
Expected: `ok`

Run: `bin/dotfiles-settings serve`. Expected: a browser tab opens showing the same UI as Task 4, and the address bar shows `http://127.0.0.1:<port>/` with no token. In the browser's network panel, every request goes to `127.0.0.1:<port>` and the terminal text is drawn in Roboto Mono. Change a setting in the tab, then run `bin/dotfiles-settings tui` in a second terminal and confirm it shows the change. Change it back there and confirm the tab follows within two seconds. In a third terminal run `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/`. Expected: `403`. Stop the server with Ctrl+C.

- [ ] **Step 5: Verify and commit**

In `bin/lib/check`, in the uv block from Task 4, add the same `uv run` line for `settings/tests/test_serve.py`.

Run: `pnpm check`. Expected: exit 0, and it now runs `test_serve.py`.

```bash
git add settings/src/dotfiles_settings/serve.py settings/src/dotfiles_settings/templates/app_index.html \
  settings/src/dotfiles_settings/templates/LICENSE-textual-serve settings/tests/test_serve.py bin/lib/check
git commit -m "Serve the settings UI to a browser behind a token and an Origin check"
```

---

### Task 6: Make `vscode-settings` honour `VSCODE_FONT_PRESET`

`bin/vscode-settings` reads the preset from `~/.config/dotfiles/vscode.env` (line 73) and saves whatever it rendered back to that file (line 141). An environment value reaches it today only by accident, when the file exists without the line. So the registry entry would change nothing. After this task the order is: `--preset` or `--choose`, then `VSCODE_FONT_PRESET` from the environment, then the saved file, then `iosevka`.

A preset that came from the environment is used but never saved. If it were saved, a reset in the UI would remove the override while `vscode.env` still held its value, and VS Code would keep the preset the user had just reset. With this rule the saved file only ever holds a choice made with `--preset` or `--choose`, and it is the seed the UI shows (`env.file_seed`, Task 2).

**Files:**

- Modify: `bin/vscode-settings` (the `saved=` block near line 71, the `preset=` line near line 97, the save near line 141, and the header)
- Modify: `vscode/README.md:24`
- Test: `vscode/test-vscode-settings.sh`

**Interfaces:**

- Consumes: nothing from earlier tasks.
- Produces: the behaviour `apps.vscode_font_preset` documents, and the saved file `env.file_seed` reads.

- [ ] **Step 1: Add the failing checks to `vscode/test-vscode-settings.sh`**

Follow the file's existing `check "<name>" "<command>"` form and its fixture variables. Add these cases after "reuses the saved choice", where the saved file holds `warp`:

1. A run with `VSCODE_FONT_PRESET=fira` in the environment renders `fira`, and the saved file still holds `VSCODE_FONT_PRESET=warp`.
2. The next run with no variable renders `warp` again. This is the reset path.
3. A run with `VSCODE_FONT_PRESET=fira` and `--preset iosevka` renders `iosevka` and saves `VSCODE_FONT_PRESET=iosevka`. Run `--preset warp` afterwards so the checks that follow see the state they expect.
4. A run with `VSCODE_FONT_PRESET=nope` exits non-zero and leaves `settings.json` and the saved file unchanged.

The test must not inherit a preset from the shell that runs it: add `unset VSCODE_FONT_PRESET` beside the file's `export VSCODE_SETTINGS_DIR=...` line.

- [ ] **Step 2: Run it to see it fail**

Run: `bash vscode/test-vscode-settings.sh`
Expected: the first new check fails.

- [ ] **Step 3: Change `bin/vscode-settings`**

Capture the environment's value in a variable before the saved file is sourced. In the `preset=${preset:-${saved:-iosevka}}` line, put it between the flag and `saved`. Write `vscode.env` at the end only when the preset did not come from the environment, that is when `--preset` or `--choose` set it or the environment's value was empty. Add one header line under the `--preset` example: ``# - Render the preset named by the environment, without saving it (dotfiles-settings sets `VSCODE_FONT_PRESET`):`` with the command `` `VSCODE_FONT_PRESET={{fira}} vscode-settings` ``.

- [ ] **Step 4: Update `vscode/README.md:24`**

Current: "`vscode/presets.toml` defines the font presets; `vscode-settings --choose` (also offered during setup) picks one, saves it in `~/.config/dotfiles/vscode.env`, and renders:"

Add one sentence after the table that follows it: "`VSCODE_FONT_PRESET` in the environment, which `dotfiles-settings set apps.vscode_font_preset` sets for new shells, beats the saved preset for that render and is not saved. `--preset` and `--choose` beat both."

- [ ] **Step 5: Verify and commit**

Run: `bash vscode/test-vscode-settings.sh && help vscode-settings > /dev/null && pnpm check`
Expected: exit 0.

```bash
git add bin/vscode-settings vscode/test-vscode-settings.sh vscode/README.md
git commit -m "Let VSCODE_FONT_PRESET in the environment pick the VS Code font preset"
```

---

### Task 7: Documentation

**Files:**

- Create: `settings/README.md`
- Modify: `docs/README.md`, `README.md`, `bin/sysup` (header lines 6 and 7, the comment near line 274, the notice text near line 393), `bin/ca-roots` (the message near line 107), `bin/lib/test-ca-roots` (the assertion near line 108 that quotes that message), `.claude/rules/telemetry-sync.md`, `CLAUDE.md` (the Architecture block)

**Interfaces:**

- Consumes: the finished package.
- Produces: no code.

- [ ] **Step 1: Write `settings/README.md`**

Prettier checks it (`printWidth: 70`, `proseWrap: never`). Sections, in this order, each stating only what the code does:

1. What it is, and the three ways in: `dotfiles-settings tui`, `serve`, and the JSON commands.
2. Where a value comes from: the four sources. Read-only rows: the telemetry opt-outs, and the three Hindsight models, which `tilde/.zshenv` and `agents/claude-settings.json` set together. The seed is what a new interactive zsh exports (`zsh/env.zsh`, `tilde/.zshenv`, `~/.zsh.local`). A variable exported by hand in one terminal is not a seed. A change is written to `config.override.toml` in mise's config dir, which is inside the clone and gitignored, and it beats the seed. Reset removes the override. A change reaches a shell opened afterwards.
3. The CLI contract table and the exit codes from Task 3, and the eleven JSON keys. Nothing here about Claude Code asking: A7's Task 8 adds that sentence with the rules that make it true.
4. Values that are refused: `{{`, `{%`, `{#`, `$` and line breaks, with the one-line reason for each (mise treats the first three as a template and expands the fourth).
5. Booleans: on means the value equals the setting's `true_value`, and off is written as an empty value. An adapter receives `true_value` or `""`, never the word typed.
6. The browser UI: loopback only, a random port, a per-run token that becomes a cookie, a `Host` and `Origin` check. The page makes no request outside `127.0.0.1`: `templates/app_index.html` is textual-serve's page with its `fonts.googleapis.com` link replaced by textual-serve's own Roboto Mono file. After upgrading textual-serve in `uv.lock`, `test_serve.py` fails if upstream changed its template. Then copy the new template, make the same one replacement, and rerun the test.
7. Adding a setting: one `[[setting]]` table, the eight required fields, the four optional ones with their defaults (`true_value`, `choices`, `default`, `widget`), and the validation errors. Adding a kind: a module in `adapters/`, an entry in `ADAPTERS` and in `registry.KINDS`, with the optional `apply`, `watch_paths` and `write_note` (a string, or a method taking the setting). The VS Code font preset is the one setting whose seed comes from a file, `~/.config/dotfiles/vscode.env`.
8. Tests: the two run commands, that `pnpm check` runs them, and the layout. One script per module in `settings/tests/`. A core test is listed in `settings_tests` in `bin/lib/check`, a Textual test in the uv block. Each plan asserts its own registry entries in its own file.
9. Installing without the clone: `uv tool install "git+<repo>#subdirectory=settings"`.
10. Requirements: mise 2026.11.5, Python 3.11, uv. The first run of `bin/dotfiles-settings` creates `settings/.venv` and downloads the dependencies.

- [ ] **Step 2: Add the alias index entry**

In `docs/README.md`, in the table that holds the `claude-stack` and `vscode-settings` rows, add:

```markdown
| `dotfiles-settings tui` `dotfiles-settings serve` `dotfiles-settings list` `dotfiles-settings set {{id}} {{value}}` `dotfiles-settings reset {{id}}` | See and change the settings this repo manages, in the terminal or a browser tab; a change is stored in mise's override file and beats the export in `zsh/env.zsh` or `~/.zsh.local` (see [settings](../settings/README.md)) |
```

- [ ] **Step 3: Rewrite the knob instructions that say "add this to `~/.zsh.local`"**

- `README.md`, the `DOTFILES_MAC_PASSWORD_OP` step: the instruction becomes `dotfiles-settings set updates.mac_password_op 'op://Private/Mac login/password'`, with one sentence that an export in `~/.zsh.local` still works and is the seed an override beats.
- `README.md`, the eMudhra section: `dotfiles-settings set updates.trim_ca_roots on`. The undo sentence ends, as A1 left it, "and delete the line from `~/.zsh.local` (run `mise unset --override DOTFILES_TRIM_CA_ROOTS` too if you set it that way)." Replace that ending with "and run `dotfiles-settings reset updates.trim_ca_roots` (delete the line from `~/.zsh.local` too if you exported it there)."
- `README.md`, the `~/.zsh.local` section: A1 added a second paragraph that starts "An `export` here is a starting value. `mise set --override KEY=value`". Replace that whole paragraph. Do not add a second one beside it. New text: "An `export` here is a starting value. A setting changed with [`dotfiles-settings`](settings/README.md) beats an export of the same variable in every new shell, and `dotfiles-settings reset <id>` hands the variable back to the export. The changes are stored in `tilde/.config/mise/config.override.toml` inside the clone (`~/.config/mise` is a link to that folder), which git ignores." Afterwards `grep -c 'mise set --override' README.md` prints 0.
- `bin/sysup` header lines 6 and 7. As A1 leaves them, line 6 reads "Set `DOTFILES_MAC_PASSWORD_OP` in `~/.zsh.local` (or with `mise set --override`) to a 1Password secret reference" and line 7 reads "Set `DOTFILES_TRIM_CA_ROOTS=1` in `~/.zsh.local` (or with `mise set --override`) to let it remove". On line 6, keep the first sentence and replace the second with "Run `dotfiles-settings set updates.mac_password_op 'op://vault/item/password'` (a 1Password secret reference) to supply it with a fingerprint instead." On line 7, replace the quoted start with "Run `dotfiles-settings set updates.trim_ca_roots on` to let it remove" and leave the rest of the line as it is. Each header line stays on one line: tlrc rejects a wrapped line.
- `bin/sysup` near line 274, the comment that says "Optional: set DOTFILES_MAC_PASSWORD_OP in ~/.zsh.local to a 1Password secret reference". Change "set DOTFILES_MAC_PASSWORD_OP in ~/.zsh.local to" to "set DOTFILES_MAC_PASSWORD_OP (dotfiles-settings set updates.mac_password_op) to". Re-wrap the comment at the width of its neighbours.
- `bin/sysup` near line 393, the `brew doctor` notice. A1 does not touch it. Current: `(set DOTFILES_TRIM_CA_ROOTS=1 in ~/.zsh.local to let sysup remove them)`. New: `(run dotfiles-settings set updates.trim_ca_roots on to let sysup remove them)`. A4 later deletes this notice with the `brew doctor` step, so A4 has nothing of this edit to carry over.
- `bin/ca-roots` near line 107. Current: `Remove DOTFILES_TRIM_CA_ROOTS from ~/.zsh.local, or the next sysup removes them again.` New: `Run dotfiles-settings reset updates.trim_ca_roots (or remove the export from ~/.zsh.local), or the next sysup removes them again.`
- `bin/lib/test-ca-roots` near line 108, the check named "restore names the opt-in to remove". It compares the last output line with the old sentence, word for word. Put the new sentence there in the same commit.
- `.claude/rules/telemetry-sync.md`: add one sentence at the end. "Each opt-out exported by `zsh/env.zsh` is also a read-only entry in `settings/registry.toml`, and `settings/tests/test_registry.py` fails the gate when an entry's variable is no longer exported there, so add, rename or remove the registry entry in the same change." Add `'settings/registry.toml'` to the file's `paths:` list. `bin/lib/test-conventions` caps the size of instruction files, so keep it to that one sentence.
- `CLAUDE.md`, the Architecture block: add the line `settings/          uv package dotfiles-settings: registry.toml + adapters, CLI, Textual UI (bin/dotfiles-settings)`.

- [ ] **Step 4: Check nothing still gives the old instruction**

Run: `grep -rn "in \`~/.zsh.local\` to\|add this to \[\`~/.zsh.local\`\]\|Add it to \[\`~/.zsh.local\`\]" README.md bin/sysup bin/ca-roots docs/README.md`
Expected: no output.

Run: `bash bin/lib/test-sysup && bash bin/lib/test-ca-roots && help sysup > /dev/null && help dotfiles-settings > /dev/null`
Expected: exit 0. `bin/lib/test-ca-roots` passes only with the assertion from Step 3 updated. `bin/lib/test-sysup` asserts none of the changed text (checked with `grep -n zsh.local bin/lib/test-sysup`: no match).

- [ ] **Step 5: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings/README.md docs/README.md README.md bin/sysup bin/ca-roots bin/lib/test-ca-roots \
  .claude/rules/telemetry-sync.md CLAUDE.md
git commit -m "Document dotfiles-settings and point the knob instructions at it"
```
