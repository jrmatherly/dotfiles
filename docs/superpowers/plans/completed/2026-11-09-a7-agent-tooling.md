# A7 Agent Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The coding-agent settings (Hindsight memory, the Claude Code default model, the jstack model roles, the per-project plugin stack) show up and change in `dotfiles-settings`, and a `ui.claude_panel` switch is registered for the later panel.

**Architecture:** One adapter, `ToolAdapter`, registered for `kind = "tool"`. A setting's `key` is `<tool>:<name>`. A table maps each `<tool>` to a reader, a writer and a reset. Writers call the existing CLIs (`hindsight-memory`, `claude-stack`) or make one atomic edit to the tool's own file (`~/.claude/settings.json`, `jstack-models.md`). No setting gets a second copy (D4).

**Tech Stack:** Python 3.11+ standard library (`json`, `subprocess`, `urllib.request`, `tempfile`), Textual 8.2 for two widgets and one screen, the repo's bash CLIs, script-assert tests.

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A7. Agent tooling". Read it first. D4 and D9 govern this plan.

## Outcome

Built on 2026-11-11, commits `ee390da` to `c1c06b9`. `pnpm check` passed on each commit. What differs from the text below:

- `bin/dotfiles-settings` runs `cd "$HOME"` before uv, so `Path.cwd()` was always the home folder and `stack.status` reported its stack for every project. The launcher now exports `DOTFILES_SETTINGS_CWD`, and `tool.launch_dir()` reads it for the status row, the watched manifest and the `p` screen (`fa10834`).
- `SeatsEditor` parses seats itself. `tool.parse_seats` rejects a model-only seat such as `opus`, which must open unchanged.
- An unset jstack role shows a blank model select. Picking a model writes `<model> medium`.
- `.claude/rules/claude-config.md` gained an **rtk and ask rules** bullet, split from Permissions to stay under the 1000-byte line cap.
- Not run: any live write from the UI, the TUI in a real terminal, and `/validate-setup before` under the new `Bash(mise bootstrap*)` ask rule (Task 8 Step 3 names it as unverified).

## Global Constraints

- The package's core (registry, adapters, CLI) imports nothing outside the standard library. `tool.py` follows that.
- Use the spec's names exactly: `Setting`, `Value`, `Source` (`OVERRIDE`, `SEED`, `DEFAULT`, `UNSET`), `Adapter` (`read`, `write`, `reset`).
- Exit codes: 0 success, 1 failure, 2 unknown id or invalid value, 3 read-only setting. A `ro` setting is rejected in the CLI before the adapter runs.
- Tool-owned live files get no second copy (D4). The adapter never runs `claude-config save` or `claude-config restore`.
- No panel code (D9). `ui.claude_panel` is registered and read by nothing.
- Tests never touch `~/.claude`, `~/.hindsight` or the repo's tracked files. They use `HINDSIGHT_CONFIG`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CONFIG_SAVE_DIR` and temp dirs.
- Tests that isolate mise set `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`.
- `dotfiles-settings list` must stay fast. No reader may run `hindsight-memory status` (1.5 s measured) or `claude-stack scan` (2.9 s measured).
- Bash scripts keep their tldr-style header and pass `pnpm check`. Commit subjects are short, imperative, sentence case, with no prefix.
- Every doc that describes a changed behaviour changes in the same commit (D12).
- Line numbers in this plan are from commit `9af6244`. An earlier phase may have moved them, so find each quoted text with `grep -n` before editing it.
- No step in this plan changes this Mac. The steps that touch the live machine are reads (`get`, `status`, opening the TUI and changing nothing). Every write in a test goes to a scratch file. A real `set` or `reset` from the UI is the user's to run.
- The phase is done when `pnpm check` passes, Task 7's stale-instruction greps pass and Task 8's ask rules are in place (twenty-nine, or twenty-four when `migrate/` is gone). `mise bootstrap status --missing` is informational and no step needs it to exit 0.
- Commits name their paths. No `git add -A`, no `git add .`, no bare directory. The working tree holds an unrelated uncommitted change to `agents/claude-settings.json` that must never enter a commit of this plan.
- This plan's tests live in `settings/tests/test_tool.py`, `settings/tests/test_tui_agents.py` and `agents/catalog/test_stack.py`. It does not edit `settings/tests/test_registry.py`, and no test here counts the registry's settings or pins its kinds. A count is scoped to this plan's own rows (the 17 `jstack:` keys).
- A false bool reaches an adapter as `""` and a true one as the setting's `true_value` (`"true"` for the tool bools, `"1"` for `ui.claude_panel`). The tool writers treat `""` as false. A test of a bool goes through `cli.normalize`.

## Review Focus

1. Another process rewrites `~/.claude/settings.json` between the adapter's read and its write (Claude Code, NotchBar, the LLM Router all write it). Expected: no key is lost. Pinned by `test_edit_file_retries_when_the_file_changes` in Task 1.
2. Hindsight is not installed, or was uninstalled (no `coding-agent.json`). Expected: the rows show as unset, a write exits 1 with the script's own message, and no config is created. Pinned by `test_hindsight_without_config` in Task 2.
3. `jstack-models.md` holds lines the UI does not know: a hand-added comment, a model-only value such as `opus`, a full model id, a missing role, no final newline. Expected: a read shows the text as it is, and a write changes one line and leaves every other byte alone. Pinned by `test_jstack_round_trip_is_byte_identical` in Task 4.
4. `~/.claude/settings.json` is not valid JSON, or is missing. Expected: the read shows unset, a write fails with exit 1, and the file is unchanged. Pinned by `test_claude_model_refuses_invalid_json` in Task 3.
5. The UI is started outside a project, or where `claude-stack` cannot run (no catalog, no mise). Expected: `stack.status` shows unset and every other row still lists. Pinned by `test_stack_status_failure_is_unset` in Task 5.
6. An agent starts `mise bootstrap` in any form (`--yes`, `--only macos-defaults`, a subcommand), `mise dot apply` / `mise dotfiles apply` / `unapply`, `mise install`, `mise self-update`, `mise plugins link`, `dotfiles-settings set`, `reset` or `apply`, or `migrate/legacy-to-mise` by any path. Expected: Claude Code asks first, also when rtk's hook is active, and also for `mise bootstrap status` and `mise bootstrap packages status`, which an allow rule covered during the build (an ask rule wins over an allow rule). rtk 1.2.0 rewrites `mise install x` to `rtk mise install x` (measured), so that rule holds only with `"mise install"` in rtk's `exclude_commands`. Pinned by the `rules .claude/settings.json ask present` lines and the rtk probe in `bin/lib/test-conventions` (Task 8).

---

## Interfaces from A2 that this plan uses

Confirmed with the A2 plan's author on 2026-11-09. Check them against the landed code before Task 1 and adapt names if they moved.

- `model.py`: `Setting` is a frozen dataclass with `id, section, label, help, kind, key, type, true_value, choices, default, widget, access`. All `str` except `choices: tuple[str, ...]`. `true_value`, `choices`, `default` and `widget` are optional in `registry.toml` and default to `""`, `[]`, `""` and `""`. A2 defines `widget`, lets it be `""`, `"lines"` or `"seats"`, rejects any other value, and emits it in JSON. This plan gives the two non-empty values their behaviour. `Value` and `Source` are the spec's. `SettingsError` means exit 1. `InvalidValue(SettingsError)` means exit 2.
- `adapters/__init__.py`: `ADAPTERS: dict[str, Adapter]` holds class instances. `registry.KINDS` lists the allowed kinds. `registry.py` rejects an unknown field in a `[[setting]]` table.
- `cli.normalize(s, raw) -> str` validates bool, int, enum and path before the adapter runs. For a bool it returns the setting's `true_value` or `""`. An adapter raises `InvalidValue` only for its own rules.
- `list --json` and `get --json` emit the `Value` fields plus `label`, `section`, `type`, `choices`, `widget`, `access`.
- Optional adapter members. `write_note(self, s: Setting) -> str` returns the note the CLI and the TUI show after a write or reset of that setting, or `""` for none. `watch_paths(self) -> list[Path]` returns the files the adapter's settings read. The TUI polls the mtimes of the union across adapters.
- `mise.run_mise(...)` runs from `$HOME`. This plan does not call it. `tool.run` is a separate runner with its own `cwd` rule (Task 5).
- `tui.py`: `SettingsApp(settings=None, adapters=None)`. `None` loads the real registry and adapters. An empty list or dict means empty and is never replaced. `widget_for(s: Setting, v: Value) -> Widget` picks the widget. A widget's id is `"w-" + s.id.replace(".", "-")`.
- Tests are script-assert files, `settings/tests/test_<module>.py`. Each starts with `sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))` and prints `ok`. Core tests run with `python3 settings/tests/test_x.py`. Textual tests run with `uv run --project settings python settings/tests/test_x.py`.
- The repo root is `os.environ["DOTFILES"]`. A2 has no helper for it.

## Decisions

**No new `type`. The two list-shaped settings use A2's optional `widget` field.** The Hindsight path list is a `string` whose value is one path per line, the form `hindsight-memory paths list` prints. A jstack role is a `string` whose value is the text after the colon in the rule file, such as `opus medium` or `fable medium, opus medium`. `widget = "lines"` and `widget = "seats"` tell the TUI how to draw those two. A2 defines the field, validates it and emits it. This plan adds only the two widgets that draw it. A `list` type was rejected because it would touch `cli.normalize`, the JSON contract and every adapter for one setting.

**Reads come from the tool's own file. Writes go through its CLI where one exists.** `hindsight-memory` has no cheap "get". Its `status` took 1.5 s here because it starts `uvx`. Reading the three keys from `coding-agent.json` is not a copy, so D4 holds. Writes use `hindsight-memory on|off`, `survey on|off` and `paths add|remove`, which were run against a scratch `HINDSIGHT_CONFIG` on 2026-11-09.

**The Claude Code model has no CLI writer, so the adapter edits `~/.claude/settings.json` itself.** `claude config --help` prints the top-level help on Claude Code 2.1.321, so there is no `claude config set`. `claude-config` has no setter either, and its `write_settings` writes through the file (`cat tmp > settings`), which is not atomic. The adapter makes one atomic edit (see `edit_file`). This is the one place the plan departs from D4's wording "the UI calls the existing CLIs". It keeps D4's intent, since nothing is copied.

**Model drift rule.** The UI changes the live file only, `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`. The tracked `agents/claude-settings.json` is the seed and is never written by the UI. Effective value is the live one. `drift` is true when the two differ. `reset` writes the tracked value into the live file. The existing flow then closes the gap in the other direction: `claude-config save` (run by hand or by `sysup`) copies live into the repo for review and commit. Measured on 2026-11-09: commit `9af6244` tracks `opus`, the live file says `fable`, and the working tree already holds an uncommitted `fable` from a save. The seed is read from the working tree, so the UI reports no drift here until the next UI change.

**jstack roles: the rule file is both seed and live.** `~/.claude/rules/jstack-models.md` is a symlink to the tracked `tilde/.claude/rules/jstack-models.md`. There is no override layer, so a present line has source `SEED` and `drift` is always false. The file's own header defines reset: "Delete a line to fall back to the skill default". So `reset` deletes the role's line and the row then shows `UNSET`. A UI edit leaves the tracked file modified, and `git diff` shows it.

**The plugin stack is per project, so the global UI shows it read-only for the launch directory.** Its storage is that project's gitignored `.claude/settings.local.json`. A global row with a toggle would claim a scope it does not have. The registry holds one `ro` row, `stack.status`. A separate screen lists `claude-stack scan` for the directory the UI was started from, with keep and off as actions that run `claude-stack apply --keep|--off`. `scan` is too slow for `list`, so `claude-stack` gains a `status` subcommand that only reads the manifest.

**Every `ask` rule the plans add lands here, last** (spec decision 7). A3 moved macOS preferences from `setup/macos.sh` to `mise bootstrap`, and A5 moved the links from `setup/symlinks.sh` to `mise dot apply`. The old scripts were guarded by the `Bash(./setup/*)` family of ask rules, and those guards went with the scripts. A4 makes `mise install`, `mise self-update` and `mise plugins link` change the machine, and Part B adds `migrate/legacy-to-mise`. The owner kept every guard but moved them all to the last phase so none prompts during the build. Until Task 8 lands, the owner's go-ahead in chat guards these commands. Task 8 adds twenty-nine rules: `Bash(mise bootstrap*)`, `Bash(mise dot *apply*)` and `Bash(mise dotfiles *apply*)` (the strings A3 and A5 used to carry), `Bash(mise install*)`, `Bash(mise self-update*)` and `Bash(mise plugins link*)` (A4's P15), the eighteen for `dotfiles-settings set`, `reset` and `apply` that A2's Task 3 used to add (the decision's list does not name them, but its rule is every `ask` rule the plans add), and Part B's five for `migrate/legacy-to-mise` (its P15). It adds no allow rules. The decision's allow list for the build's read-only and scratch commands is already in `.claude/settings.json` (commits `96ee341` and `1fcb304`), and Task 8 removes the two of its rules that `Bash(mise bootstrap*)` makes dead (Step 3).

**Part B's rules depend on `migrate/` existing.** Part B's Task 1 creates the script before A1, so it is in the checkout when Task 8 runs, and Part B's own plan no longer adds rules. Part B's Task 8 deletes `migrate/` on or after 2027-02-28 and removes these five rules and their check with it. If Task 8 here runs after that removal (or Part B never landed), it leaves the five rules and their block out. The block is guarded by `if [ -e migrate ]`, so it never fails a checkout without the script.

**`ui.claude_panel` is an `env` setting.** Key `DOTFILES_UI_CLAUDE_PANEL`, type `bool`, `true_value = "1"`, default `""`. It is stored in the mise override file by A2's `env` adapter. No `tool` code is involved.

## Settings

All `kind = "tool"` unless noted. Section is `Agents` for every row. "Config" means `${HINDSIGHT_CONFIG:-~/.hindsight/coding-agent.json}`. A tool bool reads as `"true"` or `""`, and its `true_value` is `"true"`.

| id | key | type | access | default | Read | Write | Seed, source, drift |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hindsight.enabled` | `hindsight:enabled` | bool | rw | `true` | Config key `disabled`. `"true"` unless it is JSON `true`. | `hindsight-memory on` for `"true"`, else `hindsight-memory off` | Seed is `default`. `SEED` when equal to it, else `OVERRIDE`. `UNSET` with value `None` when Config is missing. Drift false. |
| `hindsight.survey` | `hindsight:survey` | bool | rw | `""` | Config key `codebaseSurvey`. `"true"` only when JSON `true`. | `hindsight-memory survey on` or `survey off` | As above. |
| `hindsight.paths` | `hindsight:paths` | string, `widget = "lines"` | rw | `~/dev` | Config key `optInPaths`, joined with `\n`. | For each wanted line not stored: `hindsight-memory paths add <line>`. Then for each stored line not wanted: `hindsight-memory paths remove <line>`. | As above. |
| `hindsight.daemon` | `hindsight:daemon` | string | ro | `""` | `running` when `GET http://127.0.0.1:<port>/health` answers 200 within 1 s, else `down`. `<port>` is Config key `apiPort`, or 9077 when the key is absent or JSON `null` (this Mac's config holds `"apiPort": null`, read 2026-11-09). `uninstalled` when Config is missing and `<Config>.uninstalled` exists. `not installed` when neither exists. | none | Source `DEFAULT`, seed `None`, drift false. |
| `claude.model` | `claude:model` | string | rw | `""` | Key `model` of `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`. | `edit_file` sets `model` in that file. | Seed is key `model` of `${CLAUDE_CONFIG_SAVE_DIR:-$DOTFILES/agents}/claude-settings.json`. `SEED` when equal, `OVERRIDE` when different, `UNSET` when the live key is absent. Drift is `value != seed`. |
| `jstack.<slug>` (17 rows) | `jstack:<role>` | string, `widget = "seats"` | rw | `""` | The text after `<role>: ` in `${CLAUDE_CONFIG_DIR:-~/.claude}/rules/jstack-models.md`. | `edit_file` replaces or appends that one line. | Seed equals the value. `SEED` when the line exists, `UNSET` with value `None` when it does not. Drift false. Reset deletes the line. |
| `stack.status` | `stack:status` | string | ro | `""` | Stdout of `claude-stack status` run in the directory the UI was launched from, never `$HOME`. | none | Source `DEFAULT`. `UNSET` with value `None` when the command fails. |
| `ui.claude_panel` | `DOTFILES_UI_CLAUDE_PANEL` (`kind = "env"`) | bool, `true_value = "1"` | rw | `""` | A2's `env` adapter | `mise set --override` | A2's rules. |

Labels and help text, fixed copy:

- `hindsight.enabled`: "Hindsight memory". Help: "The kill switch for every Hindsight hook. Off stops recall and capture in all repos."
- `hindsight.survey`: "Hindsight codebase survey". Help: "Lets a claude -p agent sample each repo to seed memory. It reads untracked files too."
- `hindsight.paths`: "Hindsight opt-in paths". Help: "Memory is active only under these folders. One per line."
- `hindsight.daemon`: "Hindsight daemon". Help: "Whether the local coding-agent daemon answers. hindsight-memory status shows more."
- `claude.model`: "Claude Code default model". Help: "Changes ~/.claude/settings.json only. The tracked agents/claude-settings.json is the seed. claude-config save copies a change into the repo. A --model flag, ANTHROPIC_MODEL, or a model set in project or managed settings outranks it." The last sentence is from Claude Code's model configuration page (`https://code.claude.com/docs/en/model-config`, "Setting your model", read 2026-11-09): the priority order is `/model`, `--model`, `ANTHROPIC_MODEL`, then the `model` settings field, and a `model` in project or managed settings applies again at every launch.
- `jstack.<slug>`: label "jstack: `<role>`". Help: "Model and effort for this jstack role. Edits the tracked rule file, so commit the change. Reset deletes the line and jstack uses its default. New sessions pick it up."
- `stack.status`: "Project plugin stack". Help: "Per project. Shows the folder the UI was started from. Press p to see and change it."
- `ui.claude_panel`: "Claude Code settings panel". Help: "Turns the planned Claude Code panel on. Nothing reads this yet."

The 17 jstack rows, as `slug` = role: `feature_refactoring` = `feature, refactoring`. `bug_fix` = `bug-fix`. `perf_issue` = `perf-issue`. `hillclimb` = `hillclimb`. `judgment_and_prose` = `judgment and prose`. `hardest_tasks` = `hardest tasks`. `how_explorer` = `how explorer`. `how_explainer` = `how explainer`. `why_investigators` = `why investigators`. `why_synthesizer` = `why synthesizer`. `reflect_tooling` = `reflect tooling`. `reflect_judgment_divergent_synthesizer` = `reflect judgment, divergent, synthesizer`. `arena_runners` = `arena runners`. `arena_cross_judge_pool` = `arena cross-judge pool`. `swarm_workers` = `swarm workers`. `architect_runners` = `architect runners`. `interrogate_reviewers` = `interrogate reviewers`.

## File Structure

- Create `settings/src/dotfiles_settings/adapters/tool.py`. The adapter, its table, `edit_file`, the seat grammar, the stack helpers.
- Create `settings/tests/test_tool.py`. Readers and writers against scratch files.
- Create `settings/src/dotfiles_settings/tui_agents.py`. `LinesEditor`, `SeatsEditor`, `StackScreen`.
- Create `settings/tests/test_tui_agents.py`. Pilot tests.
- Modify `settings/src/dotfiles_settings/registry.py` (only `KINDS`), `adapters/__init__.py`, `tui.py`, `settings/registry.toml`.
- Modify `agents/catalog/stack.py`, `agents/catalog/test_stack.py`, `bin/claude-stack` (header), `docs/README.md`.
- Modify `agents/README.md`, `.claude/rules/claude-config.md`, `tilde/.claude/rules/hindsight.md`.
- Modify `bin/lib/check` only if A2 lists test files one by one there.
- Modify `.claude/settings.json` (`permissions.ask`, two rules out of `permissions.allow`), `bin/lib/test-conventions`, `rtk/config.toml`, `.claude/rules/claude-config.md` and `settings/README.md` (Task 8).

---

### Task 1: The `tool` kind and the atomic edit

**Files:**
- Modify: `settings/src/dotfiles_settings/registry.py`, `settings/src/dotfiles_settings/adapters/__init__.py`, `settings/registry.toml`
- Create: `settings/src/dotfiles_settings/adapters/tool.py`
- Test: `settings/tests/test_tool.py`

**Interfaces:**
- Consumes: `Setting` (with A2's `widget`), `Value`, `Source`, `SettingsError`, `InvalidValue`, `ADAPTERS`, `registry.KINDS`.
- Produces:
  - `"tool"` in `registry.KINDS`.
  - `tool.run(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]`. Runs with `capture_output=True, text=True`. `cwd=None` keeps the process's own directory. `argv[0]` is a script name resolved as `$DOTFILES/bin/<name>`. Raises `SettingsError("DOTFILES is not set")` when the variable is missing. Tests replace it by assignment.
  - `tool.edit_file(path: Path, change: Callable[[str], str]) -> None`.
  - `tool.TOOLS: dict[str, tuple[Reader, Writer | None, Resetter | None]]`, keyed by the part of `Setting.key` before the first `:`. `Reader = Callable[[str, Setting], Value]`, `Writer = Callable[[str, Setting, str], None]`, `Resetter = Callable[[str, Setting], None]`. The first argument is the part of the key after the `:`.
  - `class ToolAdapter` with `read`, `write`, `reset`. `reset` calls the tool's resetter when it has one, else `write(s, read(s).seed or "")`. Registered as `ADAPTERS["tool"]`.

- [ ] **Step 1: Write the failing tests**

```python
def test_registry_accepts_the_tool_kind():
    s = load_one('kind = "tool"\nkey = "jstack:bug-fix"\ntype = "string"\nwidget = "seats"')
    assert (s.kind, s.widget) == ("tool", "seats")

def test_edit_file_keeps_mode_and_symlink():
    real = tmp / "real.json"; real.write_text("a\n"); real.chmod(0o600)
    link = tmp / "link.json"; link.symlink_to(real)
    tool.edit_file(link, lambda t: t + "b\n")
    assert link.is_symlink() and real.read_text() == "a\nb\n"
    assert stat.S_IMODE(real.stat().st_mode) == 0o600
    assert [p.name for p in tmp.iterdir() if p.name not in ("real.json", "link.json")] == []

def test_edit_file_retries_when_the_file_changes():
    f = tmp / "race.txt"; f.write_text("one\n"); calls = []
    def change(text):
        calls.append(text)
        if len(calls) == 1:
            f.write_text("one\nother\n")      # another writer lands mid-edit
        return text + "mine\n"
    tool.edit_file(f, change)
    assert f.read_text() == "one\nother\nmine\n" and len(calls) == 2

def test_unknown_tool_key_is_a_settings_error():
    assert raises(lambda: tool.ToolAdapter().read(setting(key="nope:x")), "nope")
```

Helpers at the top of the test file, used by every later task:

- `tmp`: a temp dir removed at exit. `repo`: `Path(__file__).resolve().parents[2]`.
- `cli`: `from dotfiles_settings import cli`, for `cli.normalize`.
- `load_one(fragment)`: wraps the fragment in a full `[[setting]]` table and calls A2's registry loader on a temp file.
- `setting(**fields)`: a `Setting` with filler for the fields not given.
- `all_settings()`: the real `settings/registry.toml`, loaded. `by_id(id)`: one of them.
- `raises(fn, needle)`: true when `fn` raises `SettingsError` whose text contains `needle`. `raises_type(fn, cls)`: true when `fn` raises exactly that class or a subclass.
- `stub_run(stdout="", stderr="", returncode=0)`: assigns `tool.run` a fake that records each `argv` and returns a `CompletedProcess`. Returns the list of recorded calls. The file restores the real `tool.run` after each stubbed test.
- `health_server()`: a context manager that serves 200 on `/health` from an `http.server` thread on a free port and yields the port.

- [ ] **Step 2: Run the tests and see them fail**

Run: `python3 settings/tests/test_tool.py`
Expected: FAIL, `No module named 'dotfiles_settings.adapters.tool'`.

- [ ] **Step 3: Add `"tool"` to `registry.KINDS`**

Do not touch `Setting` or the loader. A2 already defines `widget` and validates it. If `Setting` has no `widget` field, stop: A2 has not landed as agreed.

- [ ] **Step 4: Implement `run`, `edit_file`, `TOOLS` (empty) and `ToolAdapter` in `tool.py`**

`edit_file` is the only algorithm the tests do not fix:

```python
def edit_file(path, change):
    real = path.resolve()                      # write the link's target, keep the link
    for attempt in (1, 2):
        before = real.read_text()
        after = change(before)
        if after == before:
            return
        fd, tmp = tempfile.mkstemp(dir=real.parent, prefix=real.name + ".")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(after); f.flush(); os.fsync(f.fileno())
            shutil.copymode(real, tmp)
            if real.read_text() == before:     # nobody wrote since we read
                os.replace(tmp, real)
                return
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    raise SettingsError(f"{path} changed while it was being edited. Try again")
```

- [ ] **Step 5: Register `ui.claude_panel` in `settings/registry.toml`**

Use the row in the Settings table, `kind = "env"`. Add this assertion to `test_tool.py`:

```python
def test_claude_panel_is_an_env_bool():
    s = by_id("ui.claude_panel")
    assert (s.kind, s.key, s.type, s.true_value, s.access) == ("env", "DOTFILES_UI_CLAUDE_PANEL", "bool", "1", "rw")
```

- [ ] **Step 6: Run the tests**

Run: `python3 settings/tests/test_tool.py`
Expected: `ok`.

- [ ] **Step 7: Commit**

```bash
git add settings/src/dotfiles_settings/registry.py settings/src/dotfiles_settings/adapters/__init__.py settings/src/dotfiles_settings/adapters/tool.py settings/registry.toml settings/tests/test_tool.py
git commit -m "Add the tool adapter skeleton"
```

### Task 2: Hindsight settings

**Files:**
- Modify: `settings/src/dotfiles_settings/adapters/tool.py`, `settings/registry.toml`
- Test: `settings/tests/test_tool.py`

**Interfaces:**
- Consumes: `tool.run`, `tool.TOOLS`, `ToolAdapter` from Task 1.
- Produces: `TOOLS["hindsight"]`. The four `hindsight.*` registry rows. `tool.hindsight_port(config: dict) -> int`: the config's `apiPort`, or 9077 when the key is absent or `None`.

- [ ] **Step 1: Write the failing tests**

The tests run the real `bin/hindsight-memory` against a scratch config. Set `os.environ["DOTFILES"]` to the repo root (`Path(__file__).resolve().parents[2]`) and `os.environ["HINDSIGHT_CONFIG"]` to a temp file. `A = tool.ToolAdapter()`.

```python
def test_hindsight_flags_round_trip():
    cfg.write_text('{"optInPaths": ["~/dev"]}')
    v = A.read(by_id("hindsight.enabled"))
    assert (v.value, v.source, v.seed, v.drift) == ("true", Source.SEED, "true", False)
    s = by_id("hindsight.enabled")
    assert (cli.normalize(s, "off"), cli.normalize(s, "on")) == ("", "true")
    A.write(s, cli.normalize(s, "off"))         # a false bool arrives as ""
    assert json.loads(cfg.read_text())["disabled"] is True
    assert A.read(by_id("hindsight.enabled")).source is Source.OVERRIDE
    A.reset(by_id("hindsight.enabled"))
    assert json.loads(cfg.read_text())["disabled"] is False
    s = by_id("hindsight.survey")
    A.write(s, cli.normalize(s, "yes"))
    assert json.loads(cfg.read_text())["codebaseSurvey"] is True
    A.write(s, cli.normalize(s, "no"))
    assert json.loads(cfg.read_text())["codebaseSurvey"] is False

def test_hindsight_paths_add_then_remove():
    cfg.write_text('{"optInPaths": ["~/dev", "/opt/old"]}')
    A.write(by_id("hindsight.paths"), "~/dev\n/opt/src\n\n")
    assert json.loads(cfg.read_text())["optInPaths"] == ["~/dev", "/opt/src"]
    assert A.read(by_id("hindsight.paths")).value == "~/dev\n/opt/src"

def test_hindsight_without_config():
    cfg.unlink()
    v = A.read(by_id("hindsight.enabled"))
    assert (v.value, v.source) == (None, Source.UNSET)
    assert raises(lambda: A.write(by_id("hindsight.enabled"), "true"), "hindsight-memory init")
    assert not cfg.exists()
    assert A.read(by_id("hindsight.daemon")).value == "not installed"
    Path(str(cfg) + ".uninstalled").write_text("{}")
    assert A.read(by_id("hindsight.daemon")).value == "uninstalled"

def test_hindsight_daemon_probe():
    cfg.write_text('{"apiPort": 1}')            # port 1 refuses at once, as test-hindsight-memory does
    assert A.read(by_id("hindsight.daemon")).value == "down"
    with health_server() as port:               # http.server thread answering 200 on /health
        cfg.write_text(json.dumps({"apiPort": port}))
        assert A.read(by_id("hindsight.daemon")).value == "running"

def test_hindsight_port_treats_null_as_the_default():
    assert tool.hindsight_port({"apiPort": None}) == 9077     # the live config holds null
    assert tool.hindsight_port({}) == 9077
    assert tool.hindsight_port({"apiPort": 1}) == 1

def test_registry_defaults_match_the_script():
    src = (repo / "bin/hindsight-memory").read_text()
    assert '"optInPaths": ["~/dev"]' in src and '"codebaseSurvey": false' in src and '"disabled"' not in src.split("defaults()")[1].split("EOF")[1]
    assert (by_id("hindsight.paths").default, by_id("hindsight.survey").default, by_id("hindsight.enabled").default) == ("~/dev", "", "true")
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `python3 settings/tests/test_tool.py`
Expected: FAIL on `by_id("hindsight.enabled")`, no such setting.

- [ ] **Step 3: Add the four registry rows from the Settings table**

- [ ] **Step 4: Implement `_read_hindsight(name, s) -> Value` and `_write_hindsight(name, s, value) -> None`**

One `json.loads` of the config serves all four names. A reader never raises: a missing or unparsable config gives `Value(value=None, source=UNSET, seed=s.default, drift=False)`. A writer raises `SettingsError(<the script's stderr, stripped>)` when a command exits non-zero. The path writer splits on newlines, strips each line, drops empty ones, and runs every `add` before any `remove`. It passes each path as one argv element. The bool writers run `on` for the setting's `true_value` and `off` for anything else, `""` included. The daemon probe takes its port from `hindsight_port`, which is `config.get("apiPort") or 9077`, the same rule as the script's `jq -r '.apiPort // 9077'`. It must not be `config.get("apiPort", 9077)`, which returns `None` for a stored null. The probe uses `urllib.request.urlopen(url, timeout=1)` and treats any exception as `down`. `test_hindsight_port_treats_null_as_the_default` does not probe port 9077, so it gives the same result whether or not a daemon runs.

- [ ] **Step 5: Run the tests**

Run: `python3 settings/tests/test_tool.py`
Expected: `ok`.

- [ ] **Step 6: Check against the live machine, read-only**

Run: `dotfiles-settings get hindsight.paths --json`
Expected: `"value": "~/dev"` and the seed source on this Mac (its config holds `["~/dev"]`, checked 2026-11-09).

Run: `dotfiles-settings get hindsight.daemon --json`
Expected: `"value": "running"` while the daemon is up (`/health` answered 200 on port 9077 on 2026-11-09).

- [ ] **Step 7: Commit**

```bash
git add settings/src/dotfiles_settings/adapters/tool.py settings/registry.toml settings/tests/test_tool.py
git commit -m "Show and change Hindsight memory in the settings UI"
```

### Task 3: The Claude Code default model

**Files:**
- Modify: `settings/src/dotfiles_settings/adapters/tool.py`, `settings/registry.toml`
- Test: `settings/tests/test_tool.py`

**Interfaces:**
- Consumes: `tool.edit_file`, `TOOLS`.
- Produces: `TOOLS["claude"]`. The `claude.model` row.

- [ ] **Step 1: Write the failing tests**

Set `CLAUDE_CONFIG_DIR` to `tmp/claude` and `CLAUDE_CONFIG_SAVE_DIR` to `tmp/save`. `live = tmp/claude/settings.json`, `tracked = tmp/save/claude-settings.json`.

```python
LIVE = '{\n  "env": {\n    "K": "v"\n  },\n  "model": "fable",\n  "theme": "dark"\n}\n'

def test_claude_model_seed_and_drift():
    live.write_text(LIVE); tracked.write_text('{"model": "opus"}')
    v = A.read(by_id("claude.model"))
    assert (v.value, v.seed, v.source, v.drift) == ("fable", "opus", Source.OVERRIDE, True)
    tracked.write_text('{"model": "fable"}')
    v = A.read(by_id("claude.model"))
    assert (v.source, v.drift) == (Source.SEED, False)

def test_claude_model_write_changes_only_the_live_model():
    live.write_text(LIVE); live.chmod(0o600); tracked.write_text('{"model": "opus"}')
    before = tracked.read_text()
    A.write(by_id("claude.model"), "sonnet")
    assert live.read_text() == LIVE.replace('"fable"', '"sonnet"')   # every other byte kept
    assert tracked.read_text() == before
    assert stat.S_IMODE(live.stat().st_mode) == 0o600
    A.reset(by_id("claude.model"))
    assert json.loads(live.read_text())["model"] == "opus"

def test_claude_model_reset_without_a_tracked_value_removes_the_key():
    live.write_text(LIVE); tracked.write_text("{}")
    A.reset(by_id("claude.model"))
    assert "model" not in json.loads(live.read_text())
    assert A.read(by_id("claude.model")).source is Source.UNSET

def test_claude_model_rejects_a_bad_name():
    live.write_text(LIVE)
    for bad in ("", "two words", "x;rm"):
        assert raises_type(lambda: A.write(by_id("claude.model"), bad), InvalidValue)
    A.write(by_id("claude.model"), "opus[1m]")
    A.write(by_id("claude.model"), "claude-fable-5-2")

def test_claude_model_refuses_invalid_json():
    live.write_text('{"env": {')
    assert A.read(by_id("claude.model")).value is None
    assert raises_type(lambda: A.write(by_id("claude.model"), "opus"), SettingsError)
    assert live.read_text() == '{"env": {'
    live.unlink()
    assert raises_type(lambda: A.write(by_id("claude.model"), "opus"), SettingsError)
    assert not live.exists()
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `python3 settings/tests/test_tool.py`
Expected: FAIL on `by_id("claude.model")`.

- [ ] **Step 3: Add the `claude.model` registry row**

- [ ] **Step 4: Implement `_read_claude`, `_write_claude`, `_reset_claude`**

The change function parses with `json.loads`, sets or deletes `model`, and serialises with `json.dumps(data, indent=2, ensure_ascii=False) + "\n"`. That form reproduced the live 13 KB file byte for byte on 2026-11-09. A model name must match `^[A-Za-z0-9][A-Za-z0-9._:\[\]-]*$`, else `InvalidValue`. A missing live file is a `SettingsError` naming the path, so the UI never creates a settings file. The seed path is `${CLAUDE_CONFIG_SAVE_DIR:-$DOTFILES/agents}/claude-settings.json`. An unreadable seed gives `seed=None`.

- [ ] **Step 5: Run the tests**

Run: `python3 settings/tests/test_tool.py`
Expected: `ok`.

- [ ] **Step 6: Check against the live machine, read-only**

Run: `dotfiles-settings get claude.model --json`
Expected: `"value"` equals `jq -r .model ~/.claude/settings.json`, and `"seed"` equals `jq -r .model agents/claude-settings.json`.

- [ ] **Step 7: Commit**

```bash
git add settings/src/dotfiles_settings/adapters/tool.py settings/registry.toml settings/tests/test_tool.py
git commit -m "Show the Claude Code model with its tracked seed and drift"
```

### Task 4: jstack model roles

**Files:**
- Modify: `settings/src/dotfiles_settings/adapters/tool.py`, `settings/registry.toml`
- Test: `settings/tests/test_tool.py`

**Interfaces:**
- Consumes: `tool.edit_file`, `TOOLS`.
- Produces:
  - `TOOLS["jstack"]` and the 17 `jstack.*` rows.
  - `tool.MODELS = ("opus", "sonnet", "haiku", "fable")`, `tool.EFFORTS = ("low", "medium", "high", "xhigh", "max")`.
  - `tool.LIST_ROLES = frozenset({"arena runners", "arena cross-judge pool", "architect runners", "interrogate reviewers"})`.
  - `tool.CODEX_ROLES = frozenset({"arena cross-judge pool", "reflect tooling"})`.
  - `tool.parse_seats(role: str, value: str) -> list[tuple[str, str]]`. Each seat is `(model, effort)`. `inherit` and `codex` give `("inherit", "")` and `("codex", "")`. Raises `InvalidValue`.
  - `ToolAdapter.write_note(self, s: Setting) -> str`. Returns `tool.JSTACK_NOTE` for a `jstack:` key and `""` for every other. `JSTACK_NOTE = "Edited tilde/.claude/rules/jstack-models.md, a tracked file. Commit it to keep the change."`

Grammar, from the `setup-jstack` skill: a value is seats joined by `, `. A seat is `inherit`, or `codex` (only in `CODEX_ROLES`), or `<model> <effort>` with the model in `MODELS` or matching `^claude-[a-z0-9.-]+$` and the effort in `EFFORTS`. More than one seat is allowed only in `LIST_ROLES`. The reader does not validate, so a hand-written value such as `opus` still shows.

- [ ] **Step 1: Write the failing tests**

`rule = tmp/claude/rules/jstack-models.md` is a symlink to `tmp/tracked.md`, as on a real machine.

```python
RULE = "# header\n# budget: small (medium)\nfeature, refactoring: opus medium\nbug-fix: opus\n# my note\nreflect judgment, divergent, synthesizer: fable medium\narena runners: fable medium, opus medium"   # no final newline

def test_jstack_read():
    tracked.write_text(RULE)
    assert A.read(by_id("jstack.feature_refactoring")).value == "opus medium"
    assert A.read(by_id("jstack.bug_fix")).value == "opus"          # model-only, shown as written
    assert A.read(by_id("jstack.reflect_judgment_divergent_synthesizer")).value == "fable medium"
    v = A.read(by_id("jstack.hillclimb"))
    assert (v.value, v.source, v.drift) == (None, Source.UNSET, False)
    assert A.read(by_id("jstack.arena_runners")).source is Source.SEED

def test_jstack_round_trip_is_byte_identical():
    tracked.write_text(RULE)
    A.write(by_id("jstack.bug_fix"), "sonnet high")
    assert tracked.read_text() == RULE.replace("bug-fix: opus\n", "bug-fix: sonnet high\n")
    tracked.write_text(RULE)
    A.write(by_id("jstack.arena_runners"), "fable medium, opus medium")   # same value
    assert tracked.read_text() == RULE
    assert rule.is_symlink()

def test_jstack_append_and_reset():
    tracked.write_text(RULE)
    A.write(by_id("jstack.hillclimb"), "inherit")
    assert tracked.read_text() == RULE + "\nhillclimb: inherit\n"
    A.reset(by_id("jstack.feature_refactoring"))
    assert "feature, refactoring" not in tracked.read_text() and "# my note\n" in tracked.read_text()

def test_parse_seats():
    assert tool.parse_seats("bug-fix", "opus high") == [("opus", "high")]
    assert tool.parse_seats("arena cross-judge pool", "fable medium, codex") == [("fable", "medium"), ("codex", "")]
    assert tool.parse_seats("swarm workers", "claude-opus-5-5 max") == [("claude-opus-5-5", "max")]
    for role, bad in (("bug-fix", "opus"), ("bug-fix", "opus huge"), ("bug-fix", "gpt medium"),
                      ("bug-fix", "opus medium, sonnet medium"), ("bug-fix", "codex"), ("arena runners", "")):
        assert raises_type(lambda: tool.parse_seats(role, bad), InvalidValue)

def test_jstack_missing_file_is_not_created():
    tracked.unlink()
    assert A.read(by_id("jstack.bug_fix")).value is None
    assert raises(lambda: A.write(by_id("jstack.bug_fix"), "opus high"), "setup-jstack")
    assert not tracked.exists()

def test_tracked_rule_roles_are_known_and_parse():
    lines = (repo / "tilde/.claude/rules/jstack-models.md").read_text().splitlines()
    held = dict(l.split(": ", 1) for l in lines if not l.startswith("#") and ": " in l)
    known = {s.key.split(":", 1)[1] for s in all_settings() if s.key.startswith("jstack:")}
    assert set(held) <= known, set(held) - known      # a subset: Reset deletes a line
    for role, value in held.items():
        tool.parse_seats(role, value)                 # every line the file holds is valid
    assert len(known) == 17

def test_write_note_only_for_jstack_roles():
    assert A.write_note(by_id("jstack.bug_fix")) == tool.JSTACK_NOTE
    assert "tracked file" in tool.JSTACK_NOTE
    for other in ("hindsight.enabled", "hindsight.paths", "claude.model"):
        assert A.write_note(by_id(other)) == ""
```

The role test reads the live tracked file, so it must hold after the UI's own Reset and after a `/jstack:setup-jstack` run. Reset deletes a role's line, and the file's header allows deleting one by hand. So the file's roles are a subset of the registry's, not equal to them. A role the registry does not know fails the test, and the fix is a new registry row. The count of 17 is of this plan's own registry rows.

- [ ] **Step 2: Run the tests and see them fail**

Run: `python3 settings/tests/test_tool.py`
Expected: FAIL on `by_id("jstack.feature_refactoring")`.

- [ ] **Step 3: Add the 17 registry rows**

Use the slug and role list under the Settings table. Each has `key = "jstack:<role>"`, `type = "string"`, `widget = "seats"`, `default = ""`.

- [ ] **Step 4: Implement `parse_seats`, `_read_jstack`, `_write_jstack`, `_reset_jstack` and `write_note`**

A role's line is the first line that does not start with `#` and whose text before the first `": "` equals the role. Work on `text.splitlines(keepends=True)` so every other line keeps its bytes and its line ending. A replaced line keeps its own line ending. An appended line goes at the end, after adding a `\n` to a last line that lacks one. The writer calls `parse_seats` first. A missing file raises `SettingsError("no jstack-models.md. Run /jstack:setup-jstack first")`. `write_note` is one line: the note when `s.key` starts with `jstack:`, else `""`. The rule file is a symlink into the repo, so a role write or reset leaves a tracked file modified, the same case A3's note covers.

- [ ] **Step 5: Run the tests**

Run: `python3 settings/tests/test_tool.py`
Expected: `ok`.

- [ ] **Step 6: Commit**

```bash
git add settings/src/dotfiles_settings/adapters/tool.py settings/registry.toml settings/tests/test_tool.py
git commit -m "Edit jstack model roles one line at a time"
```

### Task 5: The project plugin stack

**Files:**
- Modify: `agents/catalog/stack.py:409-426`, `agents/catalog/test_stack.py`, `bin/claude-stack:5-27` (header), `docs/README.md:161`
- Modify: `settings/src/dotfiles_settings/adapters/tool.py`, `settings/registry.toml`
- Test: `agents/catalog/test_stack.py`, `settings/tests/test_tool.py`

**Interfaces:**
- Consumes: `tool.run`, `TOOLS`.
- Produces:
  - `claude-stack status [path]`. Prints `none`, or `applied: <N> off, <YYYY-MM-DD>` from the manifest's `owned` and `generated`. Needs no catalog. Exit 0.
  - `TOOLS["stack"]` and the `stack.status` row.
  - `tool.StackRow(NamedTuple)`: `state: str`, `key: str`, `why: str`.
  - `tool.stack_scan(cwd: Path) -> list[StackRow]`. Raises `SettingsError` with the command's stderr on a non-zero exit.
  - `tool.stack_apply(cwd: Path, keep: list[str], off: list[str]) -> str`. Returns the command's stdout line. Raises `SettingsError` with its stderr.
  - `ToolAdapter.watch_paths(self) -> list[Path]`. The files the tool settings read: `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`, `${CLAUDE_CONFIG_SAVE_DIR:-$DOTFILES/agents}/claude-settings.json` (the model's seed, which decides drift), `${HINDSIGHT_CONFIG:-~/.hindsight/coding-agent.json}`, `${CLAUDE_CONFIG_DIR:-~/.claude}/rules/jstack-models.md`, and `Path.cwd() / ".claude/skill-stack.json"` (the stack manifest of the launch directory). A path that does not exist is still returned. The seed path is left out when `DOTFILES` and `CLAUDE_CONFIG_SAVE_DIR` are both unset.

- [ ] **Step 1: Write the failing `status` test in `agents/catalog/test_stack.py`**

Follow the file's existing helpers (`repo`, the fixture catalog, the apply call it already uses). Capture stdout with `contextlib.redirect_stdout`.

```python
r = repo(tmp / "status")
assert out(lambda: s.main(["status", str(r)])) == "none\n"
# after the same apply_stack call the neighbouring tests use, with one plugin turned off:
assert out(lambda: s.main(["status", str(r)])) == f"applied: 1 off, {date.today()}\n"
```

- [ ] **Step 2: Run it and see it fail**

Run: `mise exec python -- python3 agents/catalog/test_stack.py`
Expected: FAIL, argparse rejects `status` (`invalid choice`).

- [ ] **Step 3: Add `status` to `main` in `stack.py`**

Add `"status"` to `choices`. Handle it before `load_catalog()`, beside the `reset` branch: read `root / MANIFEST_FILE` with `read_json` and print the line above.

- [ ] **Step 4: Run the stack tests**

Run: `mise exec python -- python3 agents/catalog/test_stack.py`
Expected: `ok`.

- [ ] **Step 5: Document the subcommand**

In `bin/claude-stack`, add after the blank `#` that follows the `scan` entry (after line 8, so the new entry sits between two `#` lines like its neighbours):

```bash
# - Say whether a stack is applied here, without scanning:
#
# `claude-stack status`
#
```

In `docs/README.md:161`, add `` `claude-stack status` `` after `` `claude-stack scan` `` in the first cell.

Run: `help claude-stack`
Expected: the page renders and lists `claude-stack status`. `bin/lib/test-conventions` renders every `bin/` header through `help`, so this is the same check `pnpm check` makes. The header with this entry was rendered in a scratch copy on 2026-11-09 and passed.

- [ ] **Step 6: Write the failing adapter tests**

These stub `tool.run` by assignment. `live`, `cfg` and `rule` are the scratch paths from Tasks 2 to 4, and `tracked_settings` is `tmp/save/claude-settings.json`, all still named by `CLAUDE_CONFIG_DIR`, `CLAUDE_CONFIG_SAVE_DIR` and `HINDSIGHT_CONFIG`. `rule` is compared unresolved: `watch_paths` returns the link's path, and a stat of it follows the link to the tracked file.

```python
SCAN = ("keep a@m  path: x.py\noff b@m  no signal\n"
        "estimated saving: 1,000 tokens (catalog figures, which run high)\n"
        "history: 3 plugin tool calls in this repo's sessions\napplied: current\n")

def test_stack_status_reads_the_fast_command():
    calls = stub_run(stdout="applied: 21 off, 2026-11-03\n")
    v = A.read(by_id("stack.status"))
    assert (v.value, v.source) == ("applied: 21 off, 2026-11-03", Source.DEFAULT)
    assert calls == [["claude-stack", "status"]]

def test_stack_status_runs_in_the_launch_directory():
    seen = []
    tool.run = lambda argv, cwd=None: seen.append(cwd) or subprocess.CompletedProcess(argv, 0, "none\n", "")
    here = Path.cwd(); os.chdir(tmp)
    try:
        A.read(by_id("stack.status"))
    finally:
        os.chdir(here)
    assert seen == [tmp.resolve()] and tmp.resolve() != Path.home()

def test_watch_paths_name_the_files_the_settings_read():
    here = Path.cwd(); os.chdir(tmp)
    try:
        paths = A.watch_paths()
    finally:
        os.chdir(here)
    assert set(paths) == {live, tracked_settings, cfg, rule, tmp.resolve() / ".claude/skill-stack.json"}

def test_stack_status_failure_is_unset():
    stub_run(returncode=2, stderr="claude-stack: needs mise for its Python\n")
    v = A.read(by_id("stack.status"))
    assert (v.value, v.source) == (None, Source.UNSET)

def test_stack_scan_and_apply():
    stub_run(stdout=SCAN)
    assert tool.stack_scan(tmp) == [tool.StackRow("keep", "a@m", "path: x.py"), tool.StackRow("off", "b@m", "no signal")]
    calls = stub_run(stdout="applied to /x: 1 plugins off.\n")
    tool.stack_apply(tmp, keep=["b@m"], off=[])
    assert calls == [["claude-stack", "apply", "--keep", "b@m"]]
    stub_run(returncode=2, stderr="claude-stack: b@m is set to false in .claude/settings.local.json by you\n")
    assert raises(lambda: tool.stack_apply(tmp, keep=["b@m"], off=[]), "by you")
```

- [ ] **Step 7: Run them and see them fail**

Run: `python3 settings/tests/test_tool.py`
Expected: FAIL on `by_id("stack.status")`.

- [ ] **Step 8: Add the `stack.status` row and implement `_read_stack`, `stack_scan`, `stack_apply`, `watch_paths`**

`_read_stack` runs `["claude-stack", "status"]` with `cwd=Path.cwd()`. That is on purpose and differs from `mise.run_mise`, which runs from `$HOME` because mise refuses an untrusted folder. The stack is per project, and the project is the folder the UI was launched from. Do not change this `cwd` to `$HOME`: the row would then report the home folder's stack for every project. `test_stack_status_runs_in_the_launch_directory` pins it. `watch_paths` builds its list from the same path helpers the readers use, so the two cannot disagree. `stack_scan` keeps only lines matching `^(keep|off) (\S+)  (.*)$`. That is the format `claude-stack scan` printed on 2026-11-09 (two spaces before the reason).

- [ ] **Step 9: Run the tests**

Run: `python3 settings/tests/test_tool.py`
Expected: `ok`.

Run from the repo root: `claude-stack status`
Expected: `applied: 21 off, 2026-11-03` on this Mac (the manifest held 21 owned plugins on 2026-11-09). The count may have moved.

- [ ] **Step 10: Commit**

```bash
git add agents/catalog/stack.py agents/catalog/test_stack.py bin/claude-stack docs/README.md settings/src/dotfiles_settings/adapters/tool.py settings/registry.toml settings/tests/test_tool.py
git commit -m "Report the project plugin stack in the settings UI"
```

### Task 6: TUI widgets and the stack screen

**Files:**
- Create: `settings/src/dotfiles_settings/tui_agents.py`
- Modify: `settings/src/dotfiles_settings/tui.py` (`widget_for`, the save handlers, one binding)
- Test: `settings/tests/test_tui_agents.py`

**Interfaces:**
- Consumes: `widget_for`, `SettingsApp`, `Setting.widget`, `tool.MODELS`, `tool.EFFORTS`, `tool.LIST_ROLES`, `tool.CODEX_ROLES`, `tool.parse_seats`, `tool.stack_scan`, `tool.stack_apply`, `tool.StackRow`.
- Produces:
  - `LinesEditor(TextArea)`. Property `value -> str`: its lines, stripped, empty ones dropped, joined with `\n`. Posts `LinesEditor.Submitted(value: str)` on blur when `value` differs from the value it was built with.
  - `SeatsEditor(Widget)`, built as `SeatsEditor(role: str, value: str, id=...)`. One row per seat, each with a model `Select` (id `model-<n>`) and an effort `Select` (id `effort-<n>`). Property `value -> str` in the rule file's form. Posts `SeatsEditor.Changed(value: str)` after any change. For a role in `LIST_ROLES` it has buttons `#add-seat` and `#remove-seat`. It never removes the last seat.
  - `StackScreen(Screen)`, built as `StackScreen(cwd: Path)`. A `DataTable` (id `stack`) with columns state, plugin, why. Keys `k` (keep) and `o` (off) act on the highlighted row, then rescan. `escape` closes it.
  - `SettingsApp` binding `p`, "Project plugins", which pushes `StackScreen(Path.cwd())`. The launch directory again, never `$HOME` (see Task 5 Step 8).

Widget rules the tests do not fix:

- Model choices are `MODELS`, then `inherit`, then `codex` when the role is in `CODEX_ROLES`. A current model outside that list (a full model id) is added as an extra choice, so opening a row never changes it.
- A seat whose model is `inherit` or `codex` has its effort `Select` disabled, and `value` leaves the effort out.
- A model-only seat such as `opus` shows effort `medium` selected. Nothing is written until the user changes something.
- A new seat starts as `opus medium`.
- `StackScreen` runs `stack_scan` in a thread worker, since a scan took 2.9 s here. It shows "Scanning" until rows arrive. A `SettingsError` from a scan or an apply goes to `self.notify(str(e), severity="error")`.
- `widget_for` returns `LinesEditor` for `widget == "lines"` and `SeatsEditor` for `widget == "seats"`, before its type switch. `SettingsApp` saves on `LinesEditor.Submitted` and `SeatsEditor.Changed` through the same save path its `Input` handler uses.

- [ ] **Step 1: Write the failing pilot tests**

Each test builds a small host `App` that mounts one widget (`host(widget)`), or a `SettingsApp` with a fake adapter. `FakeAdapter(values)` returns each value with source `SEED` from `read` and appends `(setting.id, value)` to `.writes` in `write`. `paths_setting` and `bug_fix_setting` are the `hindsight.paths` and `jstack.bug_fix` rows from the real registry.

```python
async def test_seats_editor_single_role():
    async with host(SeatsEditor("bug-fix", "opus medium", id="e")).run_test() as pilot:
        e = pilot.app.query_one("#e", SeatsEditor)
        assert not pilot.app.query("#add-seat")
        e.query_one("#effort-0", Select).value = "high"
        await pilot.pause()
        assert e.value == "opus high"
        e.query_one("#model-0", Select).value = "inherit"
        await pilot.pause()
        assert e.value == "inherit" and e.query_one("#effort-0", Select).disabled

async def test_seats_editor_list_role():
    async with host(SeatsEditor("arena cross-judge pool", "fable medium, claude-opus-5-5 max", id="e")).run_test() as pilot:
        e = pilot.app.query_one("#e", SeatsEditor)
        assert e.value == "fable medium, claude-opus-5-5 max"        # an unknown id survives
        await pilot.click("#add-seat"); await pilot.pause()
        assert e.value == "fable medium, claude-opus-5-5 max, opus medium"
        e.query_one("#model-2", Select).value = "codex"
        await pilot.pause()
        assert e.value.endswith(", codex")
        for _ in range(4):
            await pilot.click("#remove-seat")
        await pilot.pause()
        assert e.value == "fable medium"

async def test_lines_editor_saves_on_blur():
    fake = FakeAdapter({"hindsight.paths": "~/dev"})
    app = SettingsApp(settings=[paths_setting], adapters={"tool": fake})
    async with app.run_test() as pilot:
        ed = app.query_one("#w-hindsight-paths", LinesEditor)
        ed.focus(); ed.text = "~/dev\n\n /opt/src \n"
        await pilot.press("tab"); await pilot.pause()
        assert fake.writes == [("hindsight.paths", "~/dev\n/opt/src")]

async def test_seats_editor_saves_through_the_app():
    fake = FakeAdapter({"jstack.bug_fix": "opus medium"})
    app = SettingsApp(settings=[bug_fix_setting], adapters={"tool": fake})
    async with app.run_test() as pilot:
        app.query_one("#w-jstack-bug_fix #effort-0", Select).value = "max"
        await pilot.pause()
        assert fake.writes == [("jstack.bug_fix", "opus max")]

async def test_stack_screen_keep_and_off():
    tool.stack_scan = lambda cwd: [tool.StackRow("off", "b@m", "no signal")]
    applied = []
    tool.stack_apply = lambda cwd, keep, off: applied.append((keep, off)) or "applied"
    ran = []
    tool.run = lambda argv, cwd=None: ran.append(argv)      # any real tool reader would land here
    app = SettingsApp(settings=[], adapters={})             # empty means empty, not the real registry
    async with app.run_test() as pilot:
        assert ran == [] and not app.query("#w-stack-status")   # no real adapter ran, no real row drawn
        await pilot.press("p"); await pilot.pause(0.2)
        table = app.screen.query_one("#stack", DataTable)
        assert table.row_count == 1
        await pilot.press("k"); await pilot.pause(0.2)
        assert applied == [(["b@m"], [])]
        await pilot.press("escape"); await pilot.pause()
        assert not isinstance(app.screen, StackScreen)
```

`test_stack_screen_keep_and_off` relies on A2's rule that an empty list or dict is never replaced by the real registry and adapters. With the real registry the `stack.status` row would exist and its reader would call `tool.run`, so the first assertion inside the pilot fails if that rule breaks.

The file ends with a runner that awaits each test and prints `ok`, as A2's `test_tui.py` does.

- [ ] **Step 2: Run them and see them fail**

Run: `uv run --project settings python settings/tests/test_tui_agents.py`
Expected: FAIL, `No module named 'dotfiles_settings.tui_agents'`.

- [ ] **Step 3: Implement `LinesEditor`, `SeatsEditor` and `StackScreen` in `tui_agents.py`**

- [ ] **Step 4: Wire `widget_for`, the two save handlers and the `p` binding in `tui.py`**

- [ ] **Step 5: Run the tests**

Run: `uv run --project settings python settings/tests/test_tui_agents.py`
Expected: `ok`.

Run: `uv run --project settings python settings/tests/test_tui.py`
Expected: `ok`. A2's tests still pass.

- [ ] **Step 6: Look at it**

Run from the repo root: `dotfiles-settings tui`
Expected: an Agents section with the Hindsight switches, a multi-line path box, the model field, 17 jstack rows with paired selects, and the stack status line. Press `p`. The plugin table fills after about three seconds. Press `escape`. Change nothing.

- [ ] **Step 7: Commit**

```bash
git add settings/src/dotfiles_settings/tui_agents.py settings/src/dotfiles_settings/tui.py settings/tests/test_tui_agents.py
git commit -m "Add the path list, seat and plugin stack views to the settings TUI"
```

### Task 7: Check wiring and documentation

**Files:**
- Modify: `bin/lib/check` (only if needed), `agents/README.md:40,42`, `.claude/rules/claude-config.md:15`, `tilde/.claude/rules/hindsight.md:7`

**Interfaces:**
- Consumes: everything above.
- Produces: docs that name the UI for each agent setting.

- [ ] **Step 1: Make `pnpm check` run the two new test files**

Run: `grep -n "settings/tests" bin/lib/check`
A2 lists files. Append `settings/tests/test_tool.py` to the `settings_tests` array (the core tests, which fail on a missing file), and add `settings/tests/test_tui_agents.py` as one more line in the `uv run` block beside `test_tui.py`.

- [ ] **Step 2: `tilde/.claude/rules/hindsight.md` line 7**

Stale sentence: "**Manage it with `hindsight-memory`, not `npx`.** `paths add|remove <dir>`, `on|off` (kill switch), `survey on|off`, `status`, `uninstall`."

Replace with: "**Manage it with `hindsight-memory`, not `npx`.** `paths add|remove <dir>`, `on|off` (kill switch), `survey on|off`, `status`, `uninstall`. `dotfiles-settings` shows the kill switch, the survey and the paths under Agents and changes them through these same commands."

Leave the rest of the bullet as it is. This rule loads in every session, so add nothing more.

- [ ] **Step 3: `.claude/rules/claude-config.md` line 15**

Stale sentence: "`jstack-models.md` is rewritten through its symlink by `/jstack:setup-jstack`."

Replace with: "`jstack-models.md` is rewritten through its symlink by `/jstack:setup-jstack`, and `dotfiles-settings` edits one role line at a time by replacing the link's target, never the link. The UI's `claude.model` writes `~/.claude/settings.json` only. `agents/claude-settings.json` is its seed and changes only through `claude-config save`."

- [ ] **Step 4: `agents/README.md` line 40**

Stale sentence: "After installing or removing plugins or skills, or changing settings, run `claude-config save` (`sysup` does too) and commit the diff."

Replace with: "After installing or removing plugins or skills, or changing settings, run `claude-config save` (`sysup` does too) and commit the diff. That includes a default model changed in `dotfiles-settings` (`claude.model`): the UI changes this Mac's `~/.claude/settings.json`, shows the value tracked here as the seed, and marks a difference as drift until `save` records it or Reset puts the tracked value back."

- [ ] **Step 5: `agents/README.md` line 42**

Stale sentence: "`claude-stack scan` reads tracked paths (files on disk outside git), dependency manifests and the repo's own session history (tool names only) against `[stack.signals]` in `curated.toml`, `apply` turns the plugins nothing needs off in the repo's gitignored `.claude/settings.local.json`, and `reset` undoes it."

Replace with the same sentence plus: "`status` says whether a stack is applied without scanning. `dotfiles-settings` shows that line for the folder it was started from, and its `p` screen lists the scan with keep and off."

- [ ] **Step 6: Add one bullet to `agents/README.md` after line 42**

"- Agent settings in the settings UI (`dotfiles-settings`, section Agents): Hindsight's kill switch, survey and opt-in paths, the Claude Code default model, and one row per jstack role from [`jstack-models.md`](../tilde/.claude/rules/jstack-models.md). A role edit changes that tracked file, so commit it. Reset on a role deletes its line and jstack falls back to its own default. `ui.claude_panel` is registered for a later Claude Code panel and read by nothing yet."

- [ ] **Step 7: Check that no stale instruction is left**

Run: `grep -n "rewritten through its symlink by" .claude/rules/claude-config.md`
Expected: one line, and it names `dotfiles-settings`.

Run: `grep -rn "dotfiles-settings" agents/README.md tilde/.claude/rules/hindsight.md .claude/rules/claude-config.md | wc -l`
Expected: 5 or more.

- [ ] **Step 8: Run the gate**

Run: `pnpm check`
Expected: exit 0. `bin/lib/test-conventions` caps instruction file sizes. If it fails on `hindsight.md` or `claude-config.md`, shorten the new sentence. Do not raise the cap.

- [ ] **Step 9: Commit**

```bash
git add agents/README.md .claude/rules/claude-config.md tilde/.claude/rules/hindsight.md
git diff --quiet bin/lib/check || git add bin/lib/check      # only when Step 1 changed it
git diff --cached --name-only | grep -x "agents/claude-settings.json" && echo "STOP: unstage it"
git commit -m "Document the agent settings in the settings UI"
```

### Task 8: Ask before the commands that change the machine

Spec decision 7: every `ask` rule the plans add lands here. The last task of the last phase, so the rules never prompt during the build. Before this task, the owner's go-ahead in chat is the only guard on these commands. Four groups, one commit:

| Group | Rules | From | Why |
| --- | --- | --- | --- |
| Bootstrap and links | `Bash(mise bootstrap*)`, `Bash(mise dot *apply*)`, `Bash(mise dotfiles *apply*)` | A3, A5 | The old `setup/*` ask rules guarded the scripts these replace. |
| mise itself | `Bash(mise install*)`, `Bash(mise self-update*)`, `Bash(mise plugins link*)` | A4 (its P15) | The repo's rule for `sysup` and `set-defaults` is that every way to start a command that changes the machine asks. In this repo the global config is the repo's own, so `mise install` installs the tracked tools. `Bash(mise bootstrap*)` already covers every `mise bootstrap packages …` command. |
| The settings CLI | for each of `set`, `reset` and `apply`: `Bash(dotfiles-settings <sub> *)`, `Bash(bin/dotfiles-settings <sub>*)`, `Bash(./bin/dotfiles-settings <sub>*)`, `Bash(*/bin/dotfiles-settings <sub>*)`, `Bash(bash bin/dotfiles-settings <sub>*)`, `Bash(sh bin/dotfiles-settings <sub>*)` | A2 (its Task 3 Step 6) | From A3 on, `set` on a `macos-default` setting edits a tracked file and changes a live preference, and A5's `apply dotfile` creates links. A rule cannot tell kinds apart, so all three subcommands ask. `list`, `get`, `tui` and `serve` do not. A call spelled `uv run --project settings dotfiles-settings set …` is not covered. |
| The migration script | `Bash(migrate/legacy-to-mise*)`, `Bash(./migrate/legacy-to-mise*)`, `Bash(*/migrate/legacy-to-mise*)`, `Bash(bash migrate/legacy-to-mise*)`, `Bash(sh migrate/legacy-to-mise*)` | Part B (its P15) | It changes the machine. Every way to start it asks, `--dry-run` included. No bare-name rule, because the script is not on `PATH`. Only while `migrate/legacy-to-mise` exists (see Decisions). |

**Files:**
- Modify: `bin/lib/test-conventions` (directly after the `done` of the `for s in sysup set-defaults` loop, before the rtk block)
- Modify: `.claude/settings.json` (`permissions.ask`, and two rules out of `permissions.allow`)
- Modify: `rtk/config.toml` (`exclude_commands` and its comment)
- Modify: `.claude/rules/claude-config.md` (the **Permissions** bullet), `settings/README.md` (one sentence)

**Interfaces:**
- Consumes: the `rules <file> <list> present|absent <rule>…` helper in `bin/lib/test-conventions`, and its rtk probe block, which reads every `Bash(` ask rule in `.claude/settings.json`, skips a rule holding a `/` (so the five script rules are not probed), and probes a rule's command plus ` x` when the command holds a space.
- Produces: the ask rules above and their assertions. `Bash(mise bootstrap*)` matches the bare command, every flag and every subcommand. `Bash(mise dot *apply*)` and `Bash(mise dotfiles *apply*)` match `apply` with any flags, and `unapply` too.

- [ ] **Step 1: Write the failing checks**

In `bin/lib/test-conventions`, directly after the `done` that closes the `for s in sysup set-defaults` loop, add:

```bash
# mise bootstrap and mise dot apply change the machine too: bare, with flags (--yes, --only), every subcommand, and unapply
rules .claude/settings.json ask present 'Bash(mise bootstrap*)' 'Bash(mise dot *apply*)' 'Bash(mise dotfiles *apply*)'
# mise install, self-update and plugins link change the machine, as mise bootstrap does
rules .claude/settings.json ask present 'Bash(mise install*)' 'Bash(mise self-update*)' 'Bash(mise plugins link*)'
# dotfiles-settings set, reset and apply change settings, for some kinds a
# tracked file and live preferences: every way to start them asks
for sub in set reset apply; do
  s="dotfiles-settings $sub"
  rules .claude/settings.json ask present "Bash($s *)" "Bash(bin/$s*)" "Bash(./bin/$s*)" "Bash(*/bin/$s*)" \
    "Bash(bash bin/$s*)" "Bash(sh bin/$s*)"
done
# an ask rule wins over an allow rule, so these two would be dead under Bash(mise bootstrap*)
rules .claude/settings.json allow absent 'Bash(mise bootstrap status *)' 'Bash(mise bootstrap packages status *)'
# migrate/legacy-to-mise changes the machine, so every way to start it asks (temporary: goes with migrate/)
if [ -e migrate ]; then
  rules .claude/settings.json ask present 'Bash(migrate/legacy-to-mise*)' 'Bash(./migrate/legacy-to-mise*)' \
    'Bash(*/migrate/legacy-to-mise*)' 'Bash(bash migrate/legacy-to-mise*)' 'Bash(sh migrate/legacy-to-mise*)'
fi
```

Run `ls migrate/legacy-to-mise` before adding them. When it reports no such file (Part B's Task 8 removed it, or Part B never landed), leave out the last five lines here (the comment and the `if` block), the five script rules in Step 3 and their docs words in Step 5, and expect twenty-four rules in Step 4. Add the settings clause to the list in the file's header comment.

- [ ] **Step 2: Run it and see it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: .claude/settings.json ask: Bash(mise bootstrap*) should be present`, exit 1.

If it passes the first `rules` line instead, an earlier phase already added those rules. Run `git log -S'mise bootstrap*' --oneline -- .claude/settings.json` (and the same for `mise install*` and `legacy-to-mise*` when a later line passes too), report the commit, and keep the check lines and the docs row for the rules already there.

- [ ] **Step 3: Add the rules**

In `.claude/settings.json`, append to `permissions.ask`, after the `sysup` rules, keeping the file's two-space JSON:

```json
      "Bash(mise bootstrap*)",
      "Bash(mise dot *apply*)",
      "Bash(mise dotfiles *apply*)",
      "Bash(mise install*)",
      "Bash(mise self-update*)",
      "Bash(mise plugins link*)",
      "Bash(dotfiles-settings set *)",
      "Bash(bin/dotfiles-settings set*)",
      "Bash(./bin/dotfiles-settings set*)",
      "Bash(*/bin/dotfiles-settings set*)",
      "Bash(bash bin/dotfiles-settings set*)",
      "Bash(sh bin/dotfiles-settings set*)",
      "Bash(dotfiles-settings reset *)",
      "Bash(bin/dotfiles-settings reset*)",
      "Bash(./bin/dotfiles-settings reset*)",
      "Bash(*/bin/dotfiles-settings reset*)",
      "Bash(bash bin/dotfiles-settings reset*)",
      "Bash(sh bin/dotfiles-settings reset*)",
      "Bash(dotfiles-settings apply *)",
      "Bash(bin/dotfiles-settings apply*)",
      "Bash(./bin/dotfiles-settings apply*)",
      "Bash(*/bin/dotfiles-settings apply*)",
      "Bash(bash bin/dotfiles-settings apply*)",
      "Bash(sh bin/dotfiles-settings apply*)",
      "Bash(migrate/legacy-to-mise*)",
      "Bash(./migrate/legacy-to-mise*)",
      "Bash(*/migrate/legacy-to-mise*)",
      "Bash(bash migrate/legacy-to-mise*)",
      "Bash(sh migrate/legacy-to-mise*)"
```

One `mise bootstrap` rule, not `Bash(mise bootstrap)` plus `Bash(mise bootstrap *apply*)`: those two match nothing for `mise bootstrap --yes` or `mise bootstrap --only macos-defaults`. The cost is that the read-only `mise bootstrap … status` and `--dry-run` commands ask too when an agent runs them, and no allow rule can undo that. Claude Code evaluates deny rules, then ask rules, then allow rules, the first match decides, and a matching ask rule prompts even when a narrower allow rule matches the same call (`https://code.claude.com/docs/en/permissions`, "Manage permissions", read from the local docs cache on 2026-11-09). `.claude/settings.json` holds three allow rules added for the build (commits `96ee341` and `1fcb304`): `Bash(mise bootstrap status *)`, `Bash(mise bootstrap packages status *)` and `Bash(mise dot status *)`. The first two match only commands that `Bash(mise bootstrap*)` also matches, so from this commit they never apply. Delete both from `permissions.allow` in this step, so the file does not promise a prompt-free command it no longer gives (the `allow absent` line of Step 1 pins it). `Bash(mise dot status *)` stays and keeps working: `Bash(mise dot *apply*)` matches a `mise dot status` command only when it holds the word `apply`. Not verified: whether the `allowed-tools` grant A6 gives the validate-setup skill (`Bash(mise bootstrap status*)`, `Bash(mise bootstrap --dry-run*)`) still applies under the ask rule. Running `/validate-setup before` after this commit settles it. If it prompts, that is the cost named above, not a fault. The self-checks `pnpm check` runs (A4's `bin/lib/test-packages`, which runs `mise plugins link`, A5's `bin/lib/test-dotfiles`, Part B's `bin/lib/test-migrate`) call mise or the script from inside a script, which no rule matches, and `Bash(pnpm check *)` is allowed. `bash bin/lib/test-migrate` is not matched by the script rules either. `mise dot` and `mise dotfiles` are two rules because `mise dot *` needs the space after `dot`.

- [ ] **Step 4: Run it, see the rtk probe fail, and exclude `mise install` from rtk**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: rtk rewrites 'mise install x' to 'rtk mise install x', so its ask rule never matches: add the command to rtk/config.toml`. Measured on 2026-11-09 with rtk 1.2.0 and the tracked `rtk/config.toml` in a scratch `HOME`: `rtk rewrite` rewrites `mise install x` and `mise exec x`, and prints nothing for `mise bootstrap x`, `mise bootstrap status`, `mise dot x`, `mise dot apply`, `mise dotfiles x`, `mise self-update x`, `mise plugins x` and `mise plugins link x`. The eighteen `dotfiles-settings` rules need no entry: A2 measured that `rtk rewrite` prints nothing for `dotfiles-settings set x`, `reset x` and `apply x`. If the run passes instead, an rtk upgrade stopped rewriting `mise install`: skip the edit below and say so in the commit message.

In `rtk/config.toml`, add `"mise install"` to `exclude_commands`, after `"gh"`, and change the comment's `(curl, gh)` to `(curl, gh, mise install)`. The entry is matched as a command prefix: measured in the same scratch `HOME`, with `"mise install"` excluded `rtk rewrite "mise install x"` prints nothing and `mise exec x` is still rewritten. `"mise"` would also work but would stop rtk filtering every other mise command.

Run: `bash bin/lib/test-conventions | tail -1`
Expected: `conventions: all checks passed`.

Run: `/usr/bin/jq -r '.permissions.ask[] | select(test("^Bash\\(mise (bootstrap|dot |dotfiles |install|self-update|plugins link)|legacy-to-mise|dotfiles-settings (set|reset|apply)"))' .claude/settings.json | sort | uniq -c`
Expected: the twenty-nine rules, each with count 1.

- [ ] **Step 5: Update the Permissions bullet in `.claude/rules/claude-config.md`**

Find it with `grep -n "asks first, because they change the machine" .claude/rules/claude-config.md`. Stale text (Part A may have changed the command list; keep whatever list is there): "running `setup.sh`, `setup/*`, `set-defaults` or `sysup` asks first, because they change the machine."

Replace with the same list plus the new commands: "running `setup.sh`, `setup/*`, `set-defaults`, `sysup`, `mise bootstrap` (any form, its read-only `status` and `--dry-run` too), `mise dot apply` / `mise dotfiles apply`, `mise install`, `mise self-update`, `mise plugins link`, `dotfiles-settings set` / `reset` / `apply` or `migrate/legacy-to-mise` asks first, because they change the machine." Leave the rest of the bullet as it is. In `settings/README.md`, after the CLI contract table A2 wrote, add: "In Claude Code, `set`, `reset` and `apply` ask first." The file was 3,369 bytes on 2026-11-09 against the 6,000-byte cap.

- [ ] **Step 6: Gate and commit**

Run: `pnpm check`
Expected: exit 0.

`.claude/settings.json` may hold other uncommitted edits (decision 7's allow list is already committed). Run `git diff .claude/settings.json` first. When it shows any hunk other than the twenty-nine added lines and the two removed allow rules from Step 3, stop and ask the owner which change goes in this commit. Do not use `git add -p` (interactive) or `git add -A`.

```bash
git add bin/lib/test-conventions .claude/settings.json rtk/config.toml .claude/rules/claude-config.md settings/README.md
git diff --cached --name-only | grep -x "agents/claude-settings.json" && echo "STOP: unstage it"
git commit -m "Ask before the mise commands and the migration script that change the machine"
```

Leave `rtk/config.toml` off the `git add` line only when Step 4 found nothing to change.

---

## Later: Claude Code panel

No task here builds the panel (D9). This records what it will stand on.

- **Contract.** The panel runs `dotfiles-settings list --json`, `get <id> --json`, `set <id> <value>` and `reset <id>`, and reads exit codes 0, 1, 2, 3. It reads its own switch with `dotfiles-settings get ui.claude_panel --json`, not from its environment. An app-launched Claude Code does not see mise overrides (spec, Verified facts: non-interactive shells get shims only).
- **Known.** A Claude Code mod can run a process. The jstack plugin's module calls `$.process.run`, `$.fs.read`, `$.store.get` and `$.ui.toast` (`hooks/register.tsx` in the installed jstack plugin, read 2026-11-09).
- **Unknown: whether a mod can add a panel beside the chat that the user can toggle, and with which call.** The `plugin-authoring` skill (`/plugin-authoring`) is the doc that settles it.
- **Unknown: the PATH a mod's `$.process.run` gets.** `uv tool install` puts `dotfiles-settings` in `~/.local/bin`. A mod that runs `$.process.run` with `command -v dotfiles-settings` settles it.
- **The JSON is enough to draw every row.** `list --json` carries `type`, `choices` and `widget` for each setting. A panel can draw an enum from `choices`, the path list from `widget = "lines"` and a seat editor from `widget = "seats"`. The seat grammar and the role lists (`LIST_ROLES`, `CODEX_ROLES`) are not in the JSON. A panel that offers seat pickers copies them or sends free text and reads exit code 2.

## Not in this plan

- No `claude-stack reset` action in the stack screen. `--keep` undoes an `--off` and the reverse. A full reset stays a terminal command.
- No `apply tool`. Every `tool` write takes effect at once.
- No budget row for jstack. The `# budget:` comment belongs to `/jstack:setup-jstack`.
- No write path for `hindsight.daemon`. Starting and stopping the daemon stays with the vendor's tooling.
