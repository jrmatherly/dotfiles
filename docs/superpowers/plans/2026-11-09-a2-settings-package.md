# A2 Settings Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `settings/`, a uv package named `dotfiles-settings` that lists, reads, changes and resets this repo's env settings from a CLI, a terminal UI and a browser UI, storing changes in mise's override file.

**Architecture:** A registry file (`registry.toml`) names every setting. An adapter per `kind` reads and writes it. This phase ships one adapter, `env`, which reads `config.override.toml` with `tomllib` and writes through `mise set --override`. The CLI, the Textual app and the textual-serve wrapper all go through the same registry and adapters. The core (model, registry, mise helper, adapters, CLI) imports only the standard library. Textual is imported inside `tui.py` and `serve.py` only.

**Tech Stack:** Python 3.11+ (stdlib `tomllib`, `argparse`, `subprocess`), uv 0.13.7 with the hatchling build backend, Textual 8.2, textual-serve 1.1 (aiohttp), mise 2026.11.5, bash for the launcher.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A2. The settings package". Phase A1 has landed before this plan starts.

## Global Constraints

- Minimum mise version: 2026.11.5. The package fails with a clear message below it.
- Python 3.11 or newer. Dependencies: `textual>=8.2,<9`, `textual-serve>=1.1,<2`. No others.
- The core (registry, model, mise helper, adapters, CLI) imports nothing outside the standard library, so its tests run with plain `python3`.
- The browser UI binds to `127.0.0.1` only, on a random free port, behind a per-run token in the URL.
- Tests that isolate mise set `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`: it turns override files off.
- Names and signatures of `Setting`, `Value`, `Source`, `Adapter` and the CLI contract (subcommands, JSON fields, exit codes 0, 1, 2, 3) are the spec's. Five later plans add adapters against them.
- A `ro` setting rejects `set` and `reset` in the CLI, before any adapter runs.
- Bash scripts start with `#!/bin/bash` and a tldr-style header, define their output helpers inline, and pass `pnpm check`. Each header line is one sentence on one line.
- House Python style (`agents/catalog/stack.py`): small functions, an error class the CLI reports without a traceback, test files that are plain scripts with module-level asserts and a final `print("ok")`.
- Commit subjects are short, imperative, sentence case, with no prefix. Every task ends with `pnpm check` passing.

## Review Focus

1. **A value containing shell or template metacharacters.** Measured on mise 2026.11.5: spaces, quotes, `=`, backslashes, backticks, `;`, `|`, `#`, a leading `-` and non-ASCII text round-trip unchanged. `{{`, `{%` and `{#` are parsed as a Tera template, and `{{ x }}` made every later `mise env` call exit 1. `$VAR` and `${VAR}` are expanded in `mise env` output. A person expects the stored value to be the typed value, so `set` refuses `{{`, `{%`, `{#`, `$`, and line breaks with exit 2. Test in Task 2.
2. **A registry key that is also exported in `~/.zsh.local`.** A1 sources its override cache after `~/.zsh.local`, so the override wins in every zsh. The UI must show source `override`, and show the `~/.zsh.local` value as the seed that reset would restore. Test in Task 2.
3. **mise missing or older than 2026.11.5.** Every subcommand exits 1 with one line naming the floor and what was found. No traceback. Test in Task 3.
4. **The override file hand-edited into invalid TOML.** mise itself exits 1 on every command in that state. `list` and `get` exit 1 with the file path and the parser's line. The TUI shows the error in a banner, disables the rows, and recovers when the file is fixed. Tests in Tasks 2, 3 and 4.
5. **Two UIs open at once.** A change made in one appears in the other within two seconds. A write that another writer clobbered is reported, not silently lost. Tests in Tasks 2 and 4.

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
| `settings/tests/test_*.py` | One script per module |
| `settings/README.md` | Package documentation |
| `bin/dotfiles-settings` | Launcher from the clone |

Decisions the spec left open, fixed here:

- **Dependencies are main dependencies, not an extra.** `uv tool install "git+<repo>#subdirectory=settings"` then gives a working `tui` and `serve` with no extra flag. The stdlib-only rule is kept by importing Textual inside `tui.py` and `serve.py`, which `cli.py` imports only inside the `tui` and `serve` branches.
- **Build backend: hatchling.** `uv init --package` with uv 0.13.7 writes `uv_build`, which cannot map a file outside the module into the wheel. The spec puts `registry.toml` at `settings/registry.toml`, so the wheel needs hatchling's `force-include`. Verified: the built wheel contains `dotfiles_settings/registry.toml`, and an editable install finds `settings/registry.toml`.
- **`uv.lock` is committed.** The launcher and `bin/lib/check` run with `--locked`, so a dependency cannot move without a diff.
- **`default` means the consumer's own fallback.** No file applies a registry default for an env setting (spec D3), so `default` is non-empty only when the script that reads the variable falls back to that value itself. Otherwise it is `""` and an unset variable reads as `unset`.
- **A bool set to false is written as the empty string.** `upup` tests `DOTFILES_TRIM_CA_ROOTS` with `-n` and `setup/misc.sh` tests `DOTFILES_SKIP_CODEGRAPH` with `= true`. An empty override reads as false for both and still beats a seed of `1`. A bool is shown as on when its value equals `true_value`.
- **`apply <kind>`** calls an optional adapter method `apply(self, settings: list[Setting]) -> list[str]` and prints the returned lines. `EnvAdapter` has none, and the CLI prints `env: nothing to apply`.
- **`write_note`** is an optional adapter class attribute. The CLI prints it to stderr and the TUI shows it after a successful write or reset.
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

@dataclass(frozen=True)
class Setting:
    id: str; section: str; label: str; help: str; kind: str; key: str
    type: str; true_value: str; choices: tuple[str, ...]; default: str; access: str

@dataclass(frozen=True)
class Value:
    setting_id: str; value: str | None; source: Source; seed: str | None; drift: bool

class Adapter(Protocol):
    def read(self, s: Setting) -> Value: ...
    def write(self, s: Setting, value: str) -> None: ...
    def reset(self, s: Setting) -> None: ...
```

- Produces, in `registry.py`:

```python
KINDS = ("env",)                      # later plans append their kind
TYPES = ("bool", "string", "int", "enum", "path")
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

Every table carries all eleven fields. `true_value` is `""` unless `type = "bool"`. `choices` is `[]` unless `type = "enum"`.

```toml
[[setting]]
id = "updates.trim_ca_roots"
section = "Updates"
label = "Remove the compromised eMudhra roots"
help = "Lets upup remove two roots brew doctor warns about. ca-roots restore puts them back."
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
help = "A secret reference such as op://Private/Mac login/password. upup reads it with op when a macOS update is pending. The password itself is never stored here."
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
help = "upup adds the elapsed time to a step's result line when the step took at least this long."
kind = "env"
key = "UPUP_SLOW"
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
help = "Beats the preset saved by vscode-settings --choose. Run vscode-settings afterwards to render settings.json."
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
help = "Reaches shells only. Claude Code started from an app reads its own copy in agents/claude-settings.json, and a running daemon keeps the model it started with."
kind = "env"
key = "HINDSIGHT_API_LLM_MODEL"
type = "string"
true_value = ""
choices = []
default = ""
access = "rw"
```

Add these with the same shape (`kind = "env"`, `true_value = ""`, `choices = []`, `default = ""`, `access = "rw"`, `type = "string"`):

| id | section | key | label | help |
| --- | --- | --- | --- | --- |
| `hindsight.retain_llm_model` | Hindsight | `HINDSIGHT_API_RETAIN_LLM_MODEL` | Model for extraction | Same help as `hindsight.llm_model` |
| `hindsight.consolidation_llm_model` | Hindsight | `HINDSIGHT_API_CONSOLIDATION_LLM_MODEL` | Model for consolidation | Same help as `hindsight.llm_model` |
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
| `HOMEBREW_NO_ANALYTICS` | Homebrew (A4 removes this entry with the export) |

- [ ] **Step 3: Write the failing test `settings/tests/test_registry.py`**

The file starts with `sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))`, as every test file in this plan does. A helper `bad(toml_text, needle)` writes the text to a temp file named `registry.toml` and asserts `registry.load(path)` raises `SettingsError` containing `needle`.

```python
settings = registry.load()
ids = [s.id for s in settings]
assert len(ids) == len(set(ids)) == 36
assert {s.kind for s in settings} == {"env"}
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

bad(two_tables_with_id("a.b"), "duplicate id: a.b")
bad(table(kind="nope"), "a.b: unknown kind 'nope'")
bad(table(type="float"), "a.b: unknown type 'float'")
bad(table(type="enum", choices=[]), "a.b: enum needs choices")
bad(table(type="bool", true_value=""), "a.b: bool needs true_value")
bad(table(access="wo"), "a.b: access must be rw or ro")
bad(table(key="lower case"), "a.b: env key must match [A-Z_][A-Z0-9_]*")
bad(table(default="x", type="enum", choices=["y"]), "a.b: default 'x' is not one of the choices")
bad(table_without("label"), "a.b: missing field 'label'")
bad(table(extra=1), "a.b: unknown field 'extra'")
bad(table(id="Bad Id"), "id must be dotted lowercase: 'Bad Id'")
bad("not toml [", "registry.toml")           # the message names the file
bad("", "no settings")
print("ok")
```

- [ ] **Step 4: Run it to see it fail**

Run: `mise exec python -- python3 settings/tests/test_registry.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings'`

- [ ] **Step 5: Implement `model.py` and `registry.py`**

`default_path()` returns `$DOTFILES_SETTINGS_REGISTRY` when set, else `registry.toml` beside `registry.py` (installed wheel), else `Path(__file__).resolve().parents[2] / "registry.toml"` (source tree and editable install). `load` reports the first problem it finds as `SettingsError`, with the messages in Step 3. An id must match `[a-z0-9_]+(\.[a-z0-9_]+)+`. The `KINDS` check is the only place a kind is validated, so a later plan adds its kind to `KINDS` and its adapter to `ADAPTERS` together.

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

In `bin/lib/check`, after the two `agents/catalog` test lines, add a loop over `settings/tests/test_registry.py settings/tests/test_env.py settings/tests/test_cli.py` that runs each file that exists, through `mise exec python -- python3` when mise is present and plain `python3` otherwise, output to `/dev/null`. Later tasks create the other two files. Keep the comment style of the lines above it.

- [ ] **Step 8: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings .gitignore bin/lib/check
git commit -m "Add the dotfiles-settings package with its registry"
```

---

### Task 2: mise helper and the env adapter

**Files:**

- Create: `settings/src/dotfiles_settings/mise.py`, `adapters/__init__.py`, `adapters/env.py`
- Test: `settings/tests/test_env.py`

**Interfaces:**

- Consumes: `Setting`, `Value`, `Source`, `SettingsError`, `InvalidValue` from Task 1.
- Produces, in `mise.py`:

```python
FLOOR = (2026, 11, 5)
def run_mise(args: list[str], stdin: str | None = None) -> str   # stdout; SettingsError on failure
def config_dir() -> Path          # $MISE_CONFIG_DIR, else ~/.config/mise
def check_version() -> None       # SettingsError below FLOOR or when mise is missing
```

- Produces, in `adapters/env.py`:

```python
def override_path() -> Path                     # config_dir() / "config.override.toml"
def read_override() -> dict[str, str]           # the file's [env] table, {} when the file is absent
def seed_env(keys: set[str]) -> dict[str, str]  # what a new interactive shell exports, overrides excluded
class EnvAdapter:
    write_note = "Open a new shell to pick this up."
    def read(self, s: Setting) -> Value
    def write(self, s: Setting, value: str) -> None
    def reset(self, s: Setting) -> None
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
| key in `read_override()` | `OVERRIDE` | the override string | seed shell value, else `default` if non-empty, else `None` |
| key in the seed shell | `SEED` | the seed value | same as value |
| `default != ""` | `DEFAULT` | `default` | same as value |
| otherwise | `UNSET` | `None` | `None` |

For `type = "path"`, a `default` is passed through `os.path.expanduser`. `drift` is always `False` for this adapter: an env setting has no live system state beyond the shell that reads it, and `write_note` covers a stale shell.

**Write rules.** `write` raises `InvalidValue` when the value contains `{{`, `{%`, `{#`, `$`, `\n` or `\r`, naming the offending sequence. Then it runs `mise.run_mise(["set", "--override", f"{s.key}={value}"])`. The value is one argv element, so no shell sees it. Then it re-reads the file and raises `SettingsError(f"{s.key} was changed by another writer, try again")` when the stored value differs. `reset` runs `mise.run_mise(["unset", "--override", s.key])` only when the key is in the file, so it never creates the file.

`read_override` raises `SettingsError(f"{path}: {error}")` on `tomllib.TOMLDecodeError`, and ignores `[env]` entries whose value is not a string.

`run_mise` runs `os.environ.get("DOTFILES_SETTINGS_MISE", "mise")`. `FileNotFoundError` becomes `SettingsError("dotfiles-settings needs mise 2026.11.5 or newer, and mise is not on PATH")`. `check_version` parses the first whitespace-separated token of `mise --version` (output on this Mac: `2026.11.5 macos-arm64 (2026-11-08)`) into a tuple of ints and raises `SettingsError(f"dotfiles-settings needs mise 2026.11.5 or newer, found {token}")` below `FLOOR`.

- [ ] **Step 1: Write the failing test `settings/tests/test_env.py`**

The test sets `MISE_CONFIG_DIR` to a temp dir and `os.chdir`s to another temp dir before importing the package. It builds `Setting` objects by hand with a helper `S(key, type="string", default="", true_value="")`, whose `id` is `key.lower()`. Part one stubs `env.seed_env` and uses real mise. It runs only when `shutil.which("mise")` finds mise, and prints `skipped: mise not found` otherwise. Part two needs no mise.

```python
# part one: real mise, stubbed seed shell
env.seed_env = lambda keys: {"T_LOCAL": "from-zsh-local", "T_SEEDED": "seed"}
a = env.EnvAdapter()
assert a.read(S("T_NONE")) == Value("t_none", None, Source.UNSET, None, False)
assert a.read(S("T_DEF", default="10")) == Value("t_def", "10", Source.DEFAULT, "10", False)
assert a.read(S("T_SEEDED")).source is Source.SEED

for raw in ("hello world", "a=b=c", "it's \"q\" \\ back", "`id` ; rm -rf / | #c", "--help -x", "café ☕", ""):
    a.write(S("T_VAL"), raw)
    assert a.read(S("T_VAL")).value == raw, raw
    assert json.loads(mise.run_mise(["env", "--json"]))["T_VAL"] == raw, raw

for raw, needle in (("{{ x }}", "{{"), ("{% if %}", "{%"), ("{# c #}", "{#"), ("$HOME/x", "$"), ("a\nb", "line break")):
    raises(lambda: a.write(S("T_VAL"), raw), InvalidValue, needle)
assert a.read(S("T_VAL")).value == ""            # a refused write changed nothing

# a key ~/.zsh.local also exports: the override wins, the seed is what reset restores
a.write(S("T_LOCAL"), "ui")
assert a.read(S("T_LOCAL")) == Value("t_local", "ui", Source.OVERRIDE, "from-zsh-local", False)
a.reset(S("T_LOCAL"))
assert a.read(S("T_LOCAL")) == Value("t_local", "from-zsh-local", Source.SEED, "from-zsh-local", False)
a.reset(S("T_LOCAL"))                             # resetting twice is fine

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

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings
git commit -m "Read and write env settings through mise's override file"
```

---

### Task 3: CLI and the launcher

**Files:**

- Create: `settings/src/dotfiles_settings/cli.py`, `__main__.py`, `bin/dotfiles-settings`
- Test: `settings/tests/test_cli.py`

**Interfaces:**

- Consumes: `registry.load`, `ADAPTERS`, `mise.check_version`, the model.
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
| `set <id> <value>` | nothing on stdout, `write_note` on stderr | 0, 2 unknown id or invalid value, 3 read-only |
| `reset <id>` | nothing on stdout, `write_note` on stderr | 0, 2 unknown id, 3 read-only |
| `apply <kind>` | the adapter's lines, or `<kind>: nothing to apply` | 0, 2 unknown kind |
| `tui` | runs `tui.run()` | 0 |
| `serve [--no-open]` | runs `serve.run(open_browser)` | 0 |

A JSON object has exactly these keys: `setting_id`, `value`, `source`, `seed`, `drift`, `label`, `section`, `type`, `access`. `source` is the lowercase enum value. `value` and `seed` are strings or `null`.

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

The test sets `MISE_CONFIG_DIR` and the cwd to temp dirs, points `DOTFILES_SETTINGS_REGISTRY` at a five-entry fixture registry (`t.flag` bool with `true_value = "1"`, `t.count` int with `default = "10"`, `t.pick` enum of `a`/`b`, `t.dir` path, `t.locked` string `ro`), and stubs `env.seed_env = lambda keys: {"T_LOCKED": "1"}`. `run(*argv)` calls `cli.main(list(argv))` with stdout and stderr captured and returns `(code, out, err)`. The mise-backed part is skipped when mise is not found, as in Task 2.

```python
code, out, _ = run("list", "--json")
rows = json.loads(out)
assert code == 0 and [r["setting_id"] for r in rows] == ["t.flag", "t.count", "t.pick", "t.dir", "t.locked"]
assert set(rows[0]) == {"setting_id", "value", "source", "seed", "drift", "label", "section", "type", "access"}
assert rows[1]["value"] == "10" and rows[1]["source"] == "default"
assert rows[0]["value"] is None and rows[0]["source"] == "unset"

assert run("set", "t.flag", "on")[0] == 0
assert json.loads(run("get", "t.flag", "--json")[1]) == {
    "setting_id": "t.flag", "value": "1", "source": "override", "seed": None, "drift": False,
    "label": "Flag", "section": "One", "type": "bool", "access": "rw"}
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

Then `chmod +x bin/dotfiles-settings`. `--project` does not change the working directory. The first run creates `settings/.venv` and downloads the dependencies.

Launcher choice, measured on this Mac with the same wrapper around each command (three runs each): `uv run --project` 101 to 113 ms, the venv's console script directly 57 ms, a plain `python3 -m` of a stdlib-only module 55 ms. `uv run` costs about 45 ms and is the one that cannot drift from the clone.

- [ ] **Step 5: Run the tests and the launcher**

Run: `mise exec python -- python3 settings/tests/test_cli.py`
Expected: `ok`

Run: `bin/dotfiles-settings list | head -3`
Expected: three tab-separated lines, the first starting `updates.trim_ca_roots`.

Run: `help dotfiles-settings`
Expected: the header renders as a tldr page with no error.

- [ ] **Step 6: Verify and commit**

Run: `pnpm check`. Expected: exit 0. The shebang scan in `bin/lib/check` picks the launcher up for `bash -n` and shellcheck.

```bash
git add settings bin/dotfiles-settings
git commit -m "Add the dotfiles-settings CLI and its launcher"
```

---

### Task 4: Terminal UI

**Files:**

- Create: `settings/src/dotfiles_settings/tui.py`
- Test: `settings/tests/test_tui.py`
- Modify: `bin/lib/check`

**Interfaces:**

- Consumes: `registry.load`, `ADAPTERS`, `cli.normalize`, `env.override_path`.
- Produces:

```python
def widget_for(s: Setting, v: Value) -> Widget
class SettingsApp(App):
    def __init__(self, settings: list[Setting] | None = None, adapters: dict[str, Adapter] | None = None)
def run() -> None            # SettingsApp().run()
```

**Layout and behaviour.** Checked against Textual 8.2.8.

- A `ListView` with id `sections` on the left, one `ListItem` per section in registry order. Highlighting a section shows its rows in a `VerticalScroll` with id `rows`. A `Footer` shows the bindings.
- A row is the label, the widget, a `Static` marker and the help text. With `slug = s.id.replace(".", "-")`, the ids are `w-<slug>` for the widget, `m-<slug>` for the marker and `r-<slug>` for the reset `Button`.
- `widget_for`: `bool` gives `Switch(value=v.value == s.true_value)`, `enum` gives `Select([(c, c) for c in s.choices], allow_blank=True)` with the current value selected when it is a choice, `int` gives `Input(type="integer")`, `string` and `path` give `Input`. `access == "ro"` sets `disabled=True` and the row gets no reset button.
- The marker text is `override` with the class `-override` when `v.source is Source.OVERRIDE`, and the lowercase source name otherwise. On an overridden row the marker is followed by `seed: <seed>` (or `seed: unset`) and the reset button.
- A change is committed on `Switch.Changed`, `Select.Changed` and `Input.Submitted` (Enter). The handler passes the widget's value through `cli.normalize` and calls the adapter's `write`. It does nothing when the normalized value equals the row's current value. That check is required: `Select.Changed` fires once on mount with the initial value.
- Reset is the row's button and the binding `ctrl+r` on the focused row. A plain `r` would be typed into an `Input`.
- After a write or reset the row is re-read and redrawn, and the adapter's `write_note`, when it has one, is shown with `self.notify(note)`. A `SettingsError` is shown with `self.notify(str(error), severity="error")` and the row is redrawn from a fresh read, so a refused value does not stay on screen.
- `set_interval(2.0, ...)` re-reads every value when the mtime of `env.override_path()` has changed (or the file appeared or vanished). This is how a change from a second UI or a hand edit shows up.
- When a read raises `SettingsError`, a `Static` with id `error` shows the message, every row widget is disabled, and the next successful poll clears both.

- [ ] **Step 1: Write the failing test `settings/tests/test_tui.py`**

The test builds a `FakeAdapter` holding a dict of overrides and a dict of seeds, with the spec's three methods, a `write_note = "noted"`, a `fail: str | None` that makes `read` raise `SettingsError(fail)`, and a `writes` list. Settings: `t.flag` (bool, `true_value="1"`), `t.name` (string, seed `"seeded"`), `t.pick` (enum `a`/`b`), `t.locked` (string, `ro`), all in section `One`, and `u.other` in section `Two`.

```python
async def main():
    fake = FakeAdapter(seeds={"T_NAME": "seeded"})
    app = SettingsApp(SETTINGS, {"env": fake})
    async with app.run_test(size=(120, 40), notifications=True) as pilot:
        await pilot.pause()
        assert [str(i.query_one(Label).renderable) for i in app.query_one("#sections", ListView).children] == ["One", "Two"]
        assert isinstance(app.query_one("#w-t-flag"), Switch)
        assert isinstance(app.query_one("#w-t-pick"), Select)
        assert isinstance(app.query_one("#w-t-name"), Input) and app.query_one("#w-t-name", Input).value == "seeded"
        assert app.query_one("#w-t-locked").disabled and not app.query("#r-t-locked")
        assert fake.writes == []                               # mounting wrote nothing
        assert "seed" in str(app.query_one("#m-t-name", Static).renderable)

        app.query_one("#w-t-flag").focus(); await pilot.press("enter"); await pilot.pause()
        assert fake.writes == [("T_FLAG", "1")]
        assert app.query_one("#m-t-flag").has_class("-override")
        assert "override" in str(app.query_one("#m-t-flag", Static).renderable)
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
        assert "config.override.toml" in str(app.query_one("#error", Static).renderable)
        assert app.query_one("#w-t-flag").disabled
        fake.fail = None; fake.touch()
        await pilot.pause(2.5)
        assert not app.query("#error") and not app.query_one("#w-t-flag").disabled
asyncio.run(main())
print("ok")
```

`fake.touch()` rewrites a temp file that the test has made `env.override_path` return, so the poll sees a new mtime.

- [ ] **Step 2: Run it to see it fail**

Run: `uv run --quiet --locked --project settings python settings/tests/test_tui.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.tui'`

- [ ] **Step 3: Implement `tui.py`**

- [ ] **Step 4: Run the test, then look at the app**

Run: `uv run --quiet --locked --project settings python settings/tests/test_tui.py`
Expected: `ok`

Run: `bin/dotfiles-settings tui`, change `updates.slow_step_seconds` to 5, confirm the marker reads `override` with `seed: unset`, press `ctrl+r`, confirm it returns to 10 with `default`, quit. Then `bin/dotfiles-settings get updates.slow_step_seconds --json` shows `"source": "default"`.

- [ ] **Step 5: Wire into the gate**

In `bin/lib/check`, after the loop from Task 1, add a block guarded by `command -v uv` that runs `uv run --quiet --locked --project settings python settings/tests/test_tui.py > /dev/null`, and the same for `test_serve.py` once Task 5 creates it (guard each with `[ -f ]`). Without uv, print `check: uv not found, skipping the dotfiles-settings UI tests` to stderr, as the minijinja block does.

- [ ] **Step 6: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings bin/lib/check
git commit -m "Add the dotfiles-settings terminal UI"
```

---

### Task 5: Browser UI

**Files:**

- Create: `settings/src/dotfiles_settings/serve.py`
- Test: `settings/tests/test_serve.py`

**Interfaces:**

- Consumes: `python -m dotfiles_settings tui` from Tasks 3 and 4.
- Produces:

```python
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
- `Server.__init__(command, host="localhost", port=8000, title=None, public_url=None, statics_path=..., templates_path=...)`. `public_url` is built from `port` in the constructor, so port 0 cannot be used. The wrapper must choose the port first.
- Routes: `/`, `/ws`, `/download/{key}`, `/static`. The page's script opens `new WebSocket(url + "?width=..&height=..")`, so it sends no token of its own. The browser does send cookies on that same-origin handshake.
- `_make_app()` is an async method returning the `aiohttp.web.Application`, and `serve()` runs it with `web.run_app(host=self.host, port=self.port)`.
- The index template links a stylesheet from `fonts.googleapis.com`. The page works without it (the font falls back). This plan leaves the template alone and the README says so.

**The wrapper.** `GuardedServer.__init__` calls `super().__init__(command, host="127.0.0.1", port=port, title="dotfiles settings")`. Its `_make_app` awaits the parent's and appends `guard(port, token)` to `app.middlewares`. The middleware applies to every route, in this order:

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

async def main():
    port = serve.free_port()
    server = serve.GuardedServer("true", port, "tok")
    assert server.host == "127.0.0.1"
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
        assert (await c.get("/")).status == 200                         # the client now holds the cookie
        assert (await c.get("/static/js/textual.js")).status == 200
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

- [ ] **Step 2: Run it to see it fail**

Run: `uv run --quiet --locked --project settings python settings/tests/test_serve.py`
Expected: `ModuleNotFoundError: No module named 'dotfiles_settings.serve'`

- [ ] **Step 3: Implement `serve.py`**

- [ ] **Step 4: Run the test, then the real thing**

Run: `uv run --quiet --locked --project settings python settings/tests/test_serve.py`
Expected: `ok`

Run: `bin/dotfiles-settings serve`. Expected: a browser tab opens showing the same UI as Task 4, and the address bar shows `http://127.0.0.1:<port>/` with no token. Change a setting in the tab, then run `bin/dotfiles-settings tui` in a second terminal and confirm it shows the change. Change it back there and confirm the tab follows within two seconds. In a third terminal run `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/`. Expected: `403`. Stop the server with Ctrl+C.

- [ ] **Step 5: Verify and commit**

Run: `pnpm check`. Expected: exit 0, and it now runs `test_serve.py`.

```bash
git add settings
git commit -m "Serve the settings UI to a browser behind a token and an Origin check"
```

---

### Task 6: Make `vscode-settings` honour `VSCODE_FONT_PRESET`

`bin/vscode-settings` reads the preset only from `~/.config/dotfiles/vscode.env` (line 73). An environment value is ignored today, so the registry entry would change nothing. After this task the order is: `--preset` flag, then `VSCODE_FONT_PRESET` from the environment, then the saved file, then `iosevka`.

**Files:**

- Modify: `bin/vscode-settings` (the `saved=` block near line 71, and the header)
- Test: `vscode/test-vscode-settings.sh`

**Interfaces:**

- Consumes: nothing from earlier tasks.
- Produces: the behaviour `apps.vscode_font_preset` documents.

- [ ] **Step 1: Add the failing checks to `vscode/test-vscode-settings.sh`**

Follow the file's existing `check "<name>" "<command>"` form and its fixture variables. Add three cases after "saves the choice": with the saved file holding `warp`, a run with `VSCODE_FONT_PRESET=fira` in the environment renders `fira` and saves `VSCODE_FONT_PRESET=fira`. A run with `VSCODE_FONT_PRESET=fira` and `--preset iosevka` renders `iosevka`. A run with `VSCODE_FONT_PRESET=nope` exits non-zero and leaves `settings.json` unchanged.

- [ ] **Step 2: Run it to see it fail**

Run: `bash vscode/test-vscode-settings.sh`
Expected: the first new check fails.

- [ ] **Step 3: Change `bin/vscode-settings`**

Capture the environment's value before the saved file is sourced, and let it replace `saved` when non-empty. Add one header line under the `--preset` example: ``# - Render the preset named by the environment (dotfiles-settings sets `VSCODE_FONT_PRESET`):`` with the command `` `VSCODE_FONT_PRESET={{fira}} vscode-settings` ``.

- [ ] **Step 4: Verify and commit**

Run: `bash vscode/test-vscode-settings.sh && help vscode-settings > /dev/null && pnpm check`
Expected: exit 0.

```bash
git add bin/vscode-settings vscode/test-vscode-settings.sh
git commit -m "Let VSCODE_FONT_PRESET in the environment pick the VS Code font preset"
```

---

### Task 7: Documentation

**Files:**

- Create: `settings/README.md`
- Modify: `docs/README.md`, `README.md`, `bin/upup` (header lines 6 and 7, the notice text near line 393), `bin/ca-roots` (the message near line 107), `CLAUDE.md` (the Architecture block)

**Interfaces:**

- Consumes: the finished package.
- Produces: no code.

- [ ] **Step 1: Write `settings/README.md`**

Prettier checks it (`printWidth: 70`, `proseWrap: never`). Sections, in this order, each stating only what the code does:

1. What it is, and the three ways in: `dotfiles-settings tui`, `serve`, and the JSON commands.
2. Where a value comes from: the four sources. The seed is what a new interactive zsh exports (`zsh/env.zsh`, `tilde/.zshenv`, `~/.zsh.local`). A variable exported by hand in one terminal is not a seed. A change is written to `config.override.toml` in mise's config dir, which is inside the clone and gitignored, and it beats the seed. Reset removes the override. A change reaches a shell opened afterwards.
3. The CLI contract table and the exit codes from Task 3, and the nine JSON keys.
4. Values that are refused: `{{`, `{%`, `{#`, `$` and line breaks, with the one-line reason for each (mise treats the first three as a template and expands the fourth).
5. Booleans: on means the value equals the setting's `true_value`, and off is written as an empty value.
6. The browser UI: loopback only, a random port, a per-run token that becomes a cookie, a `Host` and `Origin` check. State that textual-serve's page requests a font stylesheet from `fonts.googleapis.com`.
7. Adding a setting: one `[[setting]]` table, the eleven fields, and the validation errors. Adding a kind: a module in `adapters/`, an entry in `ADAPTERS` and in `registry.KINDS`, with the optional `apply` and `write_note`.
8. Tests: the two run commands, and that `pnpm check` runs them.
9. Installing without the clone: `uv tool install "git+<repo>#subdirectory=settings"`.
10. Requirements: mise 2026.11.5, Python 3.11, uv.

- [ ] **Step 2: Add the alias index entry**

In `docs/README.md`, in the table that holds the `claude-stack` and `vscode-settings` rows, add:

```markdown
| `dotfiles-settings tui` `dotfiles-settings serve` `dotfiles-settings list` `dotfiles-settings set {{id}} {{value}}` `dotfiles-settings reset {{id}}` | See and change the settings this repo manages, in the terminal or a browser tab; a change is stored in mise's override file and beats the export in `zsh/env.zsh` or `~/.zsh.local` (see [settings](../settings/README.md)) |
```

- [ ] **Step 3: Rewrite the knob instructions that say "add this to `~/.zsh.local`"**

- `README.md`, the `DOTFILES_MAC_PASSWORD_OP` step: the instruction becomes `dotfiles-settings set updates.mac_password_op 'op://Private/Mac login/password'`, with one sentence that an export in `~/.zsh.local` still works and is the seed an override beats.
- `README.md`, the eMudhra section: `dotfiles-settings set updates.trim_ca_roots on`, and to undo, `dotfiles-settings reset updates.trim_ca_roots` in place of deleting the line.
- `README.md`, the `~/.zsh.local` section: add one sentence that a setting changed in `dotfiles-settings` beats an export of the same variable in this file.
- `bin/upup` header lines 6 and 7 and the `brew doctor` notice near line 393: name `dotfiles-settings set updates.mac_password_op` and `dotfiles-settings set updates.trim_ca_roots on`. Keep each header line one sentence on one line.
- `bin/ca-roots` near line 107: `Run dotfiles-settings reset updates.trim_ca_roots (or remove the export from ~/.zsh.local), or the next upup removes them again.`
- `CLAUDE.md`, the Architecture block: add the line `settings/          uv package dotfiles-settings: registry.toml + adapters, CLI, Textual UI (bin/dotfiles-settings)`.

- [ ] **Step 4: Check nothing still gives the old instruction**

Run: `grep -rn "in \`~/.zsh.local\` to\|add this to \[\`~/.zsh.local\`\]\|Add it to \[\`~/.zsh.local\`\]" README.md bin/upup bin/ca-roots docs/README.md`
Expected: no output.

Run: `bash bin/lib/test-upup && bash bin/lib/test-ca-roots && help upup > /dev/null && help dotfiles-settings > /dev/null`
Expected: exit 0. If a self-check asserts the old message text, update that assertion in the same commit.

- [ ] **Step 5: Verify and commit**

Run: `pnpm check`. Expected: exit 0.

```bash
git add settings/README.md docs/README.md README.md bin/upup bin/ca-roots bin/lib CLAUDE.md
git commit -m "Document dotfiles-settings and point the knob instructions at it"
```
