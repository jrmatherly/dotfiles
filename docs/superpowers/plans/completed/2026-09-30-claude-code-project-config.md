# Claude Code Project Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude Code enforce this repo's format/lint rules deterministically, guard its dangerous and vendored paths, load topic rules only when relevant, package the recurring workflows (add a tool, audit docs, validate setup) as skills, and put the user-level Claude config under version control.

**Architecture:** Project config lives in `.claude/` (committed): `settings.json` (permissions + one `PostToolUse` hook), `hooks/`, `rules/`, `skills/`, `agents/`. User-level config that is hand-written (`~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`) moves into `tilde/.claude/` and is symlinked per file by `setup/symlinks.sh`; tool-rewritten files (`~/.claude/settings.json`, `~/.claude.json`) stay untracked. The shellcheck gate is tightened from `error` to `warning` after fixing the 17 existing warnings.

**Tech Stack:** Claude Code v2.1.285, bash, jq 1.8, prettier 3.9.6 + prettier-plugin-sh 0.19.0, shellcheck 0.11.0, Serena 1.7.0 (uv tool), CodeGraph 1.6.0 (mise npm tool), auto-memory plugin 0.9.2.

**Spec:** This conversation's recommendations report (2026-09-30), validated by the research summarized in [Validated findings](#validated-findings) below.

## Global Constraints

- Match repo style: 2-space indent, LF, prettier (`singleQuote`, `semi: false`); bash scripts start with a header comment and use `set -euo pipefail` unless a step says otherwise.
- `pnpm check` must pass after every task (currently it fails only on the pre-existing, uncommitted `vscode/User/settings.json` edit — leave that file alone; stage files explicitly, never `git add -A`).
- Never format `.zsh` / `tilde/.zsh*` with prettier (prettier-plugin-sh corrupts zsh: `(( $+functions[fast-theme] ))` → `(($ + functions[fast - theme]))`).
- Never track `~/.claude/settings.json` or `~/.claude.json` (rewritten by Claude Code, plugins, NotchBar, CodeGraph; `.claude.json` holds OAuth/machine IDs).
- Docs mirror behavior: every behavior change updates `README.md` / `setup/README.md` / `agents/README.md` in the same commit.
- Commit subjects: short, imperative, sentence case, no `feat:` prefix.

## Decisions for review (defaults chosen; change before executing)

1. **Serena stays on in this repo, with its limits handled** (Tasks 1, 2, 3). Serena's bash support matches `.sh`/`.bash` files only (`FilenameMatcher(".sh", ".bash")` in `solidlsp/ls_config.py`; upstream [oraios/serena#2020](https://github.com/oraios/serena/issues/2020), open), so its symbol tools see ~10 files here and none of `bin/`'s 44 extensionless scripts or the zsh config. Remediation: commit `.serena/project.yml` + memories (Serena's docs version `project.yml`); run the lint hook on Serena's edit tools too; add an always-loaded rule that says which tool to use where; slim the onboarding memories to what isn't in CLAUDE.md. Remaining gap: auto-memory only sees `Edit|Write|Bash` — see Decision 5.
2. **Prettier leaves tool-owned files alone (applied 2026-09-30).** `.prettierignore` now lists `CLAUDE.md` (any depth), `.serena/`, `.claude/auto-memory/` and `docs/superpowers/`; the CLI, `pnpm check`, the hook and the VS Code Prettier extension all honor it. (VS Code formats Markdown with markdownlint, not prettier, only when you save a file there.)
3. **ShellCheck: no global disable** (Task 9). A repo-wide `disable=SC2088` would also hide the real bug SC2088 exists for (`cd "~/x"`, `[ -f "~/.foo" ]`), which dotfiles are prone to. Instead: use the existing `tildify` helper in `setup/symlinks.sh` (2 lines) and one scoped `# shellcheck disable=SC2088` with a reason in `setup.sh` and `setup/misc.sh`. `.shellcheckrc` then holds the one optional check that pays off here, `enable=check-unassigned-uppercase` (catches unset/typo'd `UPPERCASE` vars like the `bin/pull` bug class; 1 finding in the repo, an intentional optional env var); the other 10 optional checks add nothing at `warning` level. Editor (`timonwong.shellcheck`) and `pnpm check` read the same file.
4. **Plan location (settled):** open plans live in `docs/superpowers/plans/`; once a plan is fully implemented it moves to `docs/superpowers/plans/completed/` (Task 10).
5. **auto-memory → `gitmode` (chosen 2026-09-30, applied before Task 1).** It triggers on commits, so it catches every edit whatever the tool (including Serena's), and updates CLAUDE.md at commit time: its PreToolUse hook blocks `git commit` until the memory-updater has run.

## Review Focus

- Hook fires on a file Claude creates in a gitignored dir (e.g. `private/x.sh`) → hook must exit 0 silently, not lint it (Task 1 test 6).
- Hook fires on a `.zsh` file → content byte-identical afterwards, `zsh -n` still reports syntax errors (Task 1 tests 3–4).
- Hook fires on an extensionless non-bash script in `bin/` (`bin/ocr` is Swift) → exit 0, file untouched (Task 1 test 7).
- `codegraph install` re-run after Task 7 → `~/.claude/CLAUDE.md` must still be a symlink (Task 7 step 5).
- Serena edits a file (`replace_content` etc. send `relative_path`, not `file_path`) → the hook must still format/lint it (Task 1 test 8).
- Running `./setup.sh` or `./setup/macos.sh` from a Claude session → prompts even in auto mode (Task 2 step 4, manual).

---

## Validated findings

Sources: official Claude Code docs cache `~/.claude-code-docs/cache/` (v2.1.284 changelog), prettier.io/docs (cli, ignore, configuration), shellcheck.1.md, oraios.github.io/serena, severity1/claude-code-auto-memory, plus local experiments under `/private/tmp/claude-501/`.

| Area | Confirmed fact | Consequence for this plan |
| --- | --- | --- |
| Hook matcher | File-edit tools are `Edit`, `Write`, `NotebookEdit` (no `MultiEdit`) | `"matcher": "Edit\|Write"` |
| Hook path | Exec form (`"args": []`) + `${CLAUDE_PROJECT_DIR}`; input `tool_input.file_path` is absolute | Script reads path with `jq` |
| Hook feedback | PostToolUse exit 2 → stderr shown to Claude (edit already applied); exit 1 → Claude sees nothing | Script exits 2 with the tool output |
| Hook scope | Settings hooks fire for subagent tool calls too; formatter rewrites don't break Edit (re-read on mismatch) | auto-memory's CLAUDE.md edits get formatted |
| Prettier ignore | Reads `.gitignore` + `.prettierignore` from **cwd**; explicit ignored path → silent exit 0; plugin resolves from cwd | Hook `cd`s to project root first |
| Prettier exit codes | 0 ok, 1 unformatted, 2 error; `-u` skips files with no parser (swift/perl/python in `bin/`) | Hook uses `--ignore-unknown` |
| plugin-sh | Detects bash shebang in extensionless files; parses zsh as bash and corrupts it | Hook never prettiers zsh; `zsh/key-bindings.zsh` ignore entry is dead |
| Permissions | Deny > ask > allow, first match; `Edit(...)` covers Edit/Write/NotebookEdit and recognized Bash file writes; leading `/` anchors to project root; `Bash(cmd *)` also matches bare `cmd`; ask rules still prompt in auto mode; MCP tool globs allowed in deny | Rule set in Task 2 |
| Rules | `.claude/rules/*.md`, only `paths` frontmatter is read; path rules load when Claude **reads** a matching file | Rules in Task 3 |
| Skills | `context: fork` + `agent: <project agent name>`; `disable-model-invocation: true` for side-effect skills; `allowed-tools` grants last one turn; injected `` !`cmd` `` aborts on non-zero exit | Tasks 4–6 |
| Agents | `name` + `description` required; on macOS a subagent only gets Glob/Grep if it lists them and omits Bash | `tools: Read, Grep, Glob` |
| Symlinked config | Claude Code writes through symlinked `settings.json`/`.claude.json` but re-serializes/adds keys; symlinked `~/.claude/CLAUDE.md` and per-file rule symlinks load (except Cowork) | Track CLAUDE.md + rules only |
| CodeGraph 1.6.0 | `codegraph install` no longer writes CLAUDE.md, but strips an old `CODEGRAPH_START/END` block (tmp + rename → would replace a symlink) | Tracked copy drops the markers; `setup/README.md` text is stale |
| Serena | bash LS matches `.sh`/`.bash` only (issue #2020); install `uv tool install -p 3.13 serena-agent`; `claude mcp get serena \|\| claude mcp add …` is the idempotent form; `.serena/.gitignore` ignores `cache/` + `project.local.yml` | Task 8, Decision 1 |
| auto-memory | Tracks `Edit\|Write\|Bash(rm/mv)` only; Stop hook spawns a Sonnet updater that edits with `Edit`; no excludes/formatter config (issue #35); ignores `.claude/rules/` | Hook formats its edits; rules may get duplicated back into CLAUDE.md (watch) |
| shellcheck | rc discovered from script dir upwards; severity is CLI-only; 17 warnings at `-S warning`, incl. a real bug (`bin/pull` never sets `base_dir`/`current_dir`) | Task 9 |

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `.claude/settings.json` (create) | Project permissions + the lint hook registration |
| `.claude/hooks/lint-edited.sh` (create) | Format/lint the single edited file, exit 2 on problems |
| `.claude/hooks/test-lint-edited.sh` (create) | Runnable self-check for the hook |
| `.claude/rules/{setup,telemetry-sync,vscode,macos-defaults}.md` (create) | Path-scoped instructions |
| `.claude/agents/docs-auditor.md` (create) | Read-only doc-vs-code auditor |
| `.claude/skills/docs-audit/SKILL.md` (create) | Forked skill running the auditor |
| `.claude/skills/add-tool/SKILL.md` (create) | Checklist for adding a CLI/app/runtime |
| `.claude/skills/validate-setup/{SKILL.md,snapshot.sh}` (create) | Before/after machine-state diff around `setup.sh` |
| `tilde/.claude/CLAUDE.md`, `tilde/.claude/rules/serena.md` (create) | Tracked user-level Claude instructions |
| `setup/symlinks.sh`, `setup/misc.sh`, `bin/upup` (modify) | Link Claude config; install/register Serena; upgrade uv tools |
| `bin/lib/check` (modify) | Lint `.claude/**/*.sh`; severity `warning` |
| `.shellcheckrc` (create), `bin/pull`, `bin/br`, `bin/optimize-image` (modify) | Clear the 17 warnings |
| `CLAUDE.md`, `.prettierignore`, `.gitignore`, `README.md`, `setup/README.md`, `agents/README.md` (modify) | Trim, dead-entry removal, docs |

Tasks 1–6 (project config), 7–8 (user-level config), 9 (shellcheck) are independently shippable in that order; Task 9 edits the hook's severity, so it goes after them; Task 10 archives this plan.

---

### Task 1: Lint-on-edit hook

**Files:**

- Create: `.claude/hooks/lint-edited.sh`, `.claude/hooks/test-lint-edited.sh`, `.claude/settings.json`
- Modify: `bin/lib/check:7-10`, `.prettierignore` (remove `zsh/key-bindings.zsh`)

**Interfaces:**

- Produces: `.claude/settings.json` with a top-level `hooks` key (Task 2 adds `permissions` to the same file); `lint-edited.sh` reads hook JSON on stdin, uses `$CLAUDE_PROJECT_DIR`, exits 0 (clean/skipped) or 2 (problems on stderr). Its shellcheck severity string is `--severity=error` (Task 9 changes it).

- [ ] **Step 1: Write the self-check first**

`.claude/hooks/test-lint-edited.sh`:

```bash
#!/bin/bash
#
# Self-check for lint-edited.sh — run: .claude/hooks/test-lint-edited.sh

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
hook=.claude/hooks/lint-edited.sh
tmp=hooktest-$$
mkdir -p "$tmp" private
trap 'rm -rf "$root/$tmp" "$root/private/hooktest-$$.sh"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
# Feed the hook a PostToolUse payload; prints nothing, returns the hook's exit code
run() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
    | CLAUDE_PROJECT_DIR=$root "$hook" 2> /dev/null
}

# 1. Unformatted Markdown gets formatted, exit 0
printf '# T\n\n* a\n' > "$tmp/a.md"
run "$root/$tmp/a.md" || fail "markdown: non-zero exit"
grep -q '^- a$' "$tmp/a.md" || fail "markdown: not formatted"

# 2. Bash syntax error → exit 2
printf '#!/bin/bash\nif then\n' > "$tmp/b.sh"
set +e
run "$root/$tmp/b.sh"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "bash syntax error: expected exit 2, got $rc"

# 3. Valid zsh is never reformatted
printf '(( $+functions[fast-theme] )) && true\n' > "$tmp/c.zsh"
cp "$tmp/c.zsh" "$tmp/c.orig"
run "$root/$tmp/c.zsh" || fail "zsh: non-zero exit on valid file"
cmp -s "$tmp/c.zsh" "$tmp/c.orig" || fail "zsh: file was modified"

# 4. Invalid zsh → exit 2
printf 'if [[ ; then\n' > "$tmp/d.zsh"
set +e
run "$root/$tmp/d.zsh"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "zsh syntax error: expected exit 2, got $rc"

# 5. Paths outside the project and missing paths are ignored
run /etc/hosts || fail "outside path: non-zero exit"
run "$root/$tmp/missing.md" || fail "missing path: non-zero exit"

# 6. Gitignored files are skipped (private/ is gitignored)
printf '#!/bin/bash\nif then\n' > "private/hooktest-$$.sh"
run "$root/private/hooktest-$$.sh" || fail "gitignored file: should be skipped"

# 7. Extensionless non-bash script in bin/ (Swift) is skipped untouched
cp bin/ocr "$tmp/ocr.orig"
run "$root/bin/ocr" || fail "bin/ocr: non-zero exit"
cmp -s bin/ocr "$tmp/ocr.orig" || fail "bin/ocr: file was modified"

# 8. Serena's edit tools send a project-relative path
printf '# T\n\n* b\n' > "$tmp/e.md"
printf '{"tool_name":"mcp__serena__replace_content","tool_input":{"relative_path":"%s"}}' "$tmp/e.md" \
  | CLAUDE_PROJECT_DIR=$root "$hook" 2> /dev/null || fail "serena relative_path: non-zero exit"
grep -q '^- b$' "$tmp/e.md" || fail "serena relative_path: not formatted"

echo "lint-edited: all checks passed"
```

Run: `chmod +x .claude/hooks/test-lint-edited.sh`

- [ ] **Step 2: Run it to verify it fails**

Run: `.claude/hooks/test-lint-edited.sh` Expected: exits non-zero (`lint-edited.sh` doesn't exist yet: "No such file or directory" → `FAIL: markdown: non-zero exit`).

- [ ] **Step 3: Write the hook**

`.claude/hooks/lint-edited.sh`:

```bash
#!/bin/bash
#
# Claude Code PostToolUse hook (Edit|Write): format and lint the one file that
# was just edited, with the same tools and scope as `pnpm check`. Problems go
# to stderr with exit 2, which Claude Code shows to Claude so it fixes them in
# the same turn (exit 1 would only reach the user). Wired up in
# .claude/settings.json; self-check: .claude/hooks/test-lint-edited.sh

set -uo pipefail

project=${CLAUDE_PROJECT_DIR:-$(pwd -P)}
# Edit/Write send an absolute file_path; Serena's edit tools a relative_path
file=$(jq -r '.tool_input.file_path // .tool_input.relative_path // empty')
[ -n "$file" ] || exit 0
[[ $file == /* ]] || file="$project/$file"

# Only existing files inside this checkout (a directory, e.g. from
# replace_in_files, is skipped: pnpm check covers multi-file edits)
[ -f "$file" ] || exit 0
case $file in
  "$project"/*) ;;
  *) exit 0 ;;
esac

# prettier resolves its plugin, .gitignore and .prettierignore from the cwd
cd "$project" || exit 0
rel=${file#"$project"/}

# Machine-local files (private/, .codegraph/, …) aren't ours to lint
git check-ignore -q -- "$rel" && exit 0

problems=""
run() {
  local out
  if ! out=$("$@" 2>&1); then
    problems+="\$ $*"$'\n'"$out"$'\n'
  fi
}

case $rel in
  # prettier-plugin-sh parses zsh as bash and corrupts it: syntax-check only
  *.zsh | tilde/.zshrc | tilde/.zshenv | tilde/.zprofile)
    run zsh -n "$rel"
    ;;
  tilde/.bash_profile)
    run bash -n "$rel"
    ;;
  *.js | *.cjs | *.ts | *.md | *.json | *.sh | bin/*)
    # Not installed yet (fresh clone before `pnpm install`): skip formatting
    [ -x node_modules/.bin/prettier ] \
      && run node_modules/.bin/prettier --write --ignore-unknown --log-level warn -- "$rel"
    ;;
esac

# Bash scripts: the same shebang rule and bin/license exception as bin/lib/check
if [[ $rel != bin/license ]] && [[ $rel != *.zsh ]] \
  && { [[ $rel == *.sh ]] || head -n 1 "$rel" | grep -Eq '^#!(/bin/(ba)?sh|/usr/bin/env (ba)?sh)$'; }; then
  run bash -n "$rel"
  run shellcheck --severity=error "$rel"
fi

if [ -n "$problems" ]; then
  printf 'lint-edited: problems in %s (the edit was applied; fix and re-edit)\n%s' "$rel" "$problems" >&2
  exit 2
fi
exit 0
```

Run: `chmod +x .claude/hooks/lint-edited.sh`

- [ ] **Step 4: Run the self-check to verify it passes**

Run: `.claude/hooks/test-lint-edited.sh` Expected: `lint-edited: all checks passed`, exit 0.

- [ ] **Step 5: Register the hook**

`.claude/settings.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|mcp__serena__(replace_content|replace_in_files|replace_symbol_body|insert_after_symbol|insert_before_symbol|rename_symbol|safe_delete_symbol)",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-edited.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "Formatting and linting the edited file"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Lint the hook scripts in `pnpm check`**

In `bin/lib/check`, change the `shell_scripts` array to:

```bash
shell_scripts=(
  setup.sh
  setup/*.sh
  .claude/hooks/*.sh
)
```

(Task 6 adds `.claude/skills/*/*.sh`; bash expands the glob, so add it there when a file exists.)

- [ ] **Step 7: Remove the dead prettier ignore entry**

Delete the line `zsh/key-bindings.zsh` from `.prettierignore` (no glob or hook ever sends `.zsh` to prettier now).

- [ ] **Step 8: Verify**

Run: `pnpm check 2>&1 | grep -v 'vscode/User/settings.json'` Expected: only the pre-existing `vscode/User/settings.json` prettier warning; no new failures. Then start a new Claude Code session in the repo, run `/hooks`, confirm `PostToolUse · Edit|Write` lists `lint-edited.sh`; ask Claude to add a stray `* item` bullet to `docs/README.md` and confirm the file ends up with `- item` (then revert).

- [ ] **Step 9: Commit**

```bash
git add .claude/settings.json .claude/hooks/lint-edited.sh .claude/hooks/test-lint-edited.sh bin/lib/check .prettierignore
git commit -m "Format and lint each file Claude edits with a PostToolUse hook"
```

---

### Task 2: Project permissions

**Files:**

- Modify: `.claude/settings.json` (add `permissions`)
- Add to git: `.serena/project.yml`, `.serena/.gitignore`, `.serena/memories/` (slimmed)

**Interfaces:**

- Consumes: `.claude/settings.json` from Task 1.
- Produces: allow rules for `pnpm check`/`pnpm format` (Task 5 and 6 skills rely on them not prompting).

- [ ] **Step 1: Add the permissions block**

Insert after `"$schema"` in `.claude/settings.json`:

```json
  "permissions": {
    "allow": [
      "Bash(pnpm check *)",
      "Bash(pnpm format *)",
      "Bash(shellcheck *)",
      "Bash(bash -n *)",
      "Bash(zsh -n *)",
      "Bash(.claude/hooks/test-lint-edited.sh *)"
    ],
    "ask": [
      "Bash(./setup.sh *)",
      "Bash(./setup/*)",
      "Bash(set-defaults *)",
      "Bash(upup *)"
    ],
    "deny": [
      "Edit(/ql-plugins/**)",
      "Edit(/obsidian/.obsidian/plugins/**)",
      "Edit(/tilde/.config/gh/hosts.yml)"
    ]
  },
```

- [ ] **Step 2: Commit Serena's project files, slimmed (Decision 1)**

Serena's own `.serena/.gitignore` already excludes `cache/` and `project.local.yml`; `project.yml` is meant to be versioned. The onboarding memories repeat CLAUDE.md, so they would drift; keep only what Serena needs that CLAUDE.md doesn't say. Replace `.serena/memories/core.md` with:

```markdown
# dotfiles — core

Project context (commands, architecture, conventions, completion checks) lives in `CLAUDE.md`, `bin/CLAUDE.md` and `.claude/rules/` — read those, don't duplicate them here.

## Serena-specific
- Language server: bash-language-server, via `FilenameMatcher(".sh", ".bash")` — symbol tools only see `setup.sh`, `setup/*.sh` and other `*.sh` files.
- Invisible to symbol tools: every script in `bin/` (extensionless, shebang only), `zsh/*.zsh` and `tilde/.zsh*`, configs. Use `replace_content` / native Read+Edit there (upstream oraios/serena#2020).
```

and delete the four duplicates (keep Serena's own `memory_maintenance`):

```bash
rm .serena/memories/{tech_stack,conventions,suggested_commands,task_completion}.md
serena memories check
```

Expected: `No referential integrity issues found.`

- [ ] **Step 3: Validate the settings file**

Run: `jq empty .claude/settings.json && pnpm exec prettier --check .claude/settings.json && claude doctor 2>&1 | grep -iE 'invalid|skipped|warning' || echo "no settings warnings"` Expected: `no settings warnings` (or no line mentioning `.claude/settings.json`).

- [ ] **Step 4: Verify behavior in a new session (manual)**

Start a new session in the repo (accept workspace trust):

- `/permissions` lists the rules above under project settings.
- Ask Claude to "run ./setup/macos.sh --help" → a permission prompt appears (auto mode included).
- Ask Claude to "append a comment to ql-plugins/QLMarkdown.qlgenerator/Contents/Info.plist" → denied.
- `/mcp` shows serena connected; ask Claude for "the symbols in setup/symlinks.sh" → it uses `get_symbols_overview` and lists `symlink_file`, `install_dotfiles`, …

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json .serena/.gitignore .serena/project.yml .serena/memories
git commit -m "Add project permissions and commit Serena's project config"
```

---

### Task 3: Path-scoped rules and CLAUDE.md trim

**Files:**

- Create: `.claude/rules/setup.md`, `.claude/rules/telemetry-sync.md`, `.claude/rules/vscode.md`, `.claude/rules/macos-defaults.md`
- Modify: `CLAUDE.md` (remove `git-insights` and `best-practices` sections; shorten one Patterns bullet)

- [ ] **Step 1: `.claude/rules/setup.md`**

```markdown
---
paths:
  - 'setup.sh'
  - 'setup/**'
---

# Setup scripts

- A closed stdin (non-interactive run) must mean "skip", never abort or overwrite.
- `brew.sh` runs first; later scripts may use Homebrew tools but must guard with `command_exists` for `--skip-brew` on a fresh Mac.
- Every behavior change updates `setup/README.md` (and `README.md` for flags) in the same commit.
- Validate with `/validate-setup before`, then `./setup.sh --skip-brew` in a terminal (it is interactive), then `/validate-setup after`.
```

- [ ] **Step 1b: `.claude/rules/code-navigation.md`** (no `paths`: loads every session)

```markdown
# Which code tool to use here

- **Understand / locate** (what calls what, where is X): CodeGraph first (`codegraph_explore`), per the global instructions.
- **Read or edit a symbol in a `*.sh` file**: Serena's symbol tools (`get_symbols_overview`, `find_symbol`, `replace_symbol_body`, `find_referencing_symbols`).
- **Everything else** — `bin/` scripts (no extension, so Serena's language server doesn't see them), `zsh/*.zsh`, `tilde/**`, Markdown, JSON/TOML/YAML: native Read and Edit (or Serena's `replace_content`). Serena's "Edit is forbidden for code files" applies only to files its language server serves.
```

- [ ] **Step 2: `.claude/rules/telemetry-sync.md`**

```markdown
---
paths:
  - 'setup.sh'
  - 'zsh/env.zsh'
  - 'docs/privacy.md'
---

# Telemetry opt-outs are listed twice

`setup.sh` exports the same telemetry opt-out variables as `zsh/env.zsh`, because `env.zsh` isn't sourced yet on a fresh Mac. Add, rename or remove a variable in both files, and in `docs/privacy.md`, in the same change.
```

- [ ] **Step 3: `.claude/rules/vscode.md`**

```markdown
---
paths:
  - 'vscode/**'
---

# VS Code settings

- `vscode/User` is symlinked as VS Code's live user dir; VS Code rewrites these files itself. Keep them byte-identical to what VS Code writes: JSONC with no trailing commas (prettier override `trailingComma: 'none'`), existing key order and grouping.
- Don't add entries that VS Code rewrites or strips on startup (that dirtied `settings.json` before); don't re-add defaults.
```

- [ ] **Step 4: `.claude/rules/macos-defaults.md`**

```markdown
---
paths:
  - 'setup/macos.sh'
---

# macOS defaults

- Security-sensitive and per-machine settings prompt; don't apply them unconditionally.
- Verify each `defaults` domain/key against the current macOS release before adding it; prefer leaving a value at the macOS default over pinning it.
- The script force-quits Finder, Dock, Messages, Activity Monitor, Notification Center, SystemUIServer and Terminal at the end — keep that list and `README.md`'s description of it in sync.
```

- [ ] **Step 5: Trim CLAUDE.md**

In `CLAUDE.md`:

- Delete the whole `<!-- AUTO-MANAGED: git-insights -->` … `<!-- END AUTO-MANAGED -->` block and the whole `<!-- AUTO-MANAGED: best-practices -->` … `<!-- END AUTO-MANAGED -->` block (content that fails the docs' "would removing this cause mistakes?" test).
- In the `patterns` section replace the **Paired lists kept in sync** bullet with:

```markdown
- **Paired lists kept in sync**: telemetry opt-outs live in both `setup.sh` and `zsh/env.zsh` (see `.claude/rules/telemetry-sync.md`).
```

- [ ] **Step 6: Verify**

Run: `pnpm exec prettier --check .claude/rules/*.md CLAUDE.md && wc -l CLAUDE.md` Expected: formatted; CLAUDE.md under 110 lines. Manual: new session → ask Claude to read `zsh/env.zsh`, then `/memory` (or `/context`) shows `telemetry-sync.md` loaded; `/doctor prompt-audit` reports no contradictions between CLAUDE.md, `bin/CLAUDE.md` and the rules.

- [ ] **Step 7: Commit**

```bash
git add .claude/rules CLAUDE.md
git commit -m "Move topic guidance into path-scoped Claude rules"
```

---

### Task 4: docs-auditor agent and /docs-audit skill

**Files:**

- Create: `.claude/agents/docs-auditor.md`, `.claude/skills/docs-audit/SKILL.md`

**Interfaces:**

- Produces: agent `name: docs-auditor` (referenced by the skill's `agent:` field).

- [ ] **Step 1: `.claude/agents/docs-auditor.md`**

```markdown
---
name: docs-auditor
description: Read-only auditor for this dotfiles repo. Checks every claim in README.md, setup/README.md, agents/README.md, per-directory READMEs and docs/ against the scripts and configs they describe, and reports mismatches with file:line evidence. Never edits files.
tools: Read, Grep, Glob
model: sonnet
color: cyan
---

You audit documentation against code in a macOS dotfiles repo. You cannot edit files; your output is a report.

For each doc file in scope:

1. List its checkable claims: flags and their effects, commands, file paths, symlink targets, versions/pins, tool names, prompts the scripts show, ordering statements.
2. Verify each claim against the source of truth (`setup.sh`, `setup/*.sh`, `setup/Brewfile`, `bin/*`, `tilde/**`, `zsh/*.zsh`, `tilde/.config/mise/config.toml`, `package.json`, `prettier.config.cjs`). Open the code; don't infer from names.
3. Report only mismatches and dead references (paths/commands that don't exist). Skip style and wording.

Output format — one table per doc file, most severe first:

| Doc location | Claim | Actual (file:line) | Fix |

End with a one-line count: `N mismatches in M files`. If a claim can't be verified from the repo (depends on a remote service or macOS version), list it under "Unverifiable" instead of guessing.
```

- [ ] **Step 2: `.claude/skills/docs-audit/SKILL.md`**

```markdown
---
name: docs-audit
description: Audit this repo's Markdown docs against the scripts and configs they describe and report mismatches (read-only). Use after changing setup scripts, the Brewfile, mise config or bin/ scripts, or before a docs pass.
argument-hint: '[doc path or directory; default: all docs]'
context: fork
agent: docs-auditor
background: false
---

Audit these docs: $ARGUMENTS

If no path was given, audit `README.md`, `setup/README.md`, `agents/README.md`, `tilde/README.md`, every other `*/README.md` outside `node_modules/`, `obsidian/` and `ql-plugins/`, and `docs/**/*.md` except `docs/superpowers/` (implementation plans, not documentation).

Recently changed files, to check first:

!`git log --since=30.days --name-only --format= | sort -u | head -50 || true`
```

- [ ] **Step 3: Verify**

Run: `claude plugin validate .claude 2>&1 | tail -3; pnpm exec prettier --check .claude/agents/docs-auditor.md .claude/skills/docs-audit/SKILL.md` Expected: validation reports no errors (it validates the skills, agents and commands in a directory); prettier clean. Manual: new session → `/agents` lists `docs-auditor` (project); run `/docs-audit setup/README.md` → returns a table report, no file changes (`git status` unchanged).

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/docs-auditor.md .claude/skills/docs-audit/SKILL.md
git commit -m "Add a read-only docs-auditor agent and /docs-audit skill"
```

---

### Task 5: /add-tool skill

**Files:**

- Create: `.claude/skills/add-tool/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: add-tool
description: Checklist for adding a CLI, app, runtime or MCP server to these dotfiles — Brewfile vs mise vs uv, setup wiring, telemetry opt-outs, symlinked config and docs. Use whenever a new tool is being added or an existing one's install method changes.
argument-hint: '[tool name]'
---

Add `$ARGUMENTS` to the dotfiles. Work through every item; say explicitly when one doesn't apply.

1. **Install method** (pick one):
   - macOS app or system CLI → `setup/Brewfile` (`brew`/`cask`/`vscode` line with a trailing `#` comment), installed by `bin/brewpick --all`.
   - Runtime or npm CLI → `tilde/.config/mise/config.toml` `[tools]` (`"npm:<pkg>" = "<major>"`), with a comment explaining the pin. Never `npm install -g`.
   - Python CLI → `uv tool install` in `setup/misc.sh`, guarded by `command_exists uv`, plus an upgrade line in `bin/upup`.
2. **Setup wiring** (`setup/misc.sh`): only when the tool needs post-install steps (auth, MCP registration via `claude mcp get <name> || claude mcp add --scope user …`, telemetry off). Keep it idempotent and warn — don't fail — when a step can't run.
3. **Telemetry**: if the tool phones home, add its opt-out variable to **both** `setup.sh` and `zsh/env.zsh`, and to `docs/privacy.md`.
4. **Config files**: `$HOME` config goes under `tilde/` at its home-relative path. If the tool rewrites its config via temp-file + rename (breaks symlinks), don't track it — note that in `setup/README.md`.
5. **Upgrades**: confirm `bin/upup` covers it (Homebrew and `mise upgrade` already do).
6. **Docs**: `setup/README.md` (the section of the script you touched), `README.md` if user-facing, `docs/README.md` if it adds an alias or `bin/` command.
7. **Verify**: `pnpm check`; then tell the user to run `./setup.sh --skip-brew` (interactive) and, if relevant, `/validate-setup`.
```

- [ ] **Step 2: Verify**

Run: `pnpm exec prettier --check .claude/skills/add-tool/SKILL.md` Expected: clean. Manual: new session → `/add-tool jq` lists all seven items against the real files (no edits needed to test; cancel after the checklist).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/add-tool/SKILL.md
git commit -m "Add /add-tool skill for the tool-onboarding checklist"
```

---

### Task 6: /validate-setup skill

**Files:**

- Create: `.claude/skills/validate-setup/SKILL.md`, `.claude/skills/validate-setup/snapshot.sh`
- Modify: `bin/lib/check` (add `.claude/skills/*/*.sh`)

**Interfaces:**

- Consumes: `private/` is gitignored (snapshots land in `private/setup-snapshots/`).

- [ ] **Step 1: Write the snapshot script**

`.claude/skills/validate-setup/snapshot.sh`:

```bash
#!/bin/bash
#
# Print the machine state that setup.sh manages, sorted, for before/after diffs.
# Used by the /validate-setup skill: snapshot.sh > private/setup-snapshots/<phase>.txt

set -uo pipefail

repo=$(cd "$(dirname "$0")/../../.." && pwd -P)

echo "## symlinks into the repo"
for dir in "$HOME" "$HOME/.config" "$HOME/.codex" "$HOME/.claude" "$HOME/.claude/rules" \
  "$HOME/.gnupg" "$HOME/Library/Application Support/Code"; do
  find "$dir" -maxdepth 1 -type l 2> /dev/null
done | while IFS= read -r link; do
  target=$(readlink "$link")
  [[ $target == "$repo"* ]] && echo "${link/#$HOME/~} -> ${target/#$repo/\$DOTFILES}"
done | sort

echo "## mise (current)"
mise ls --current 2>&1 | sort

echo "## claude mcp (names)"
claude mcp list 2> /dev/null | grep ' - ' | sed 's/: .*//' | sort

echo "## login shell"
dscl . -read "$HOME" UserShell 2>&1

echo "## ~/.gitconfig.local present"
[ -f "$HOME/.gitconfig.local" ] && echo yes || echo no

echo "## Touch ID for sudo"
grep -c pam_tid /etc/pam.d/sudo_local 2> /dev/null || echo 0
```

Run: `chmod +x .claude/skills/validate-setup/snapshot.sh && .claude/skills/validate-setup/snapshot.sh | head -20` Expected: a `## symlinks into the repo` section listing e.g. `~/.zshrc -> $DOTFILES/tilde/.zshrc`.

- [ ] **Step 2: Write the skill**

`.claude/skills/validate-setup/SKILL.md`:

```markdown
---
name: validate-setup
description: Snapshot the machine state setup.sh manages before and after running it, and diff the two, to verify a setup change.
argument-hint: 'before|after'
disable-model-invocation: true
allowed-tools: Bash(.claude/skills/validate-setup/snapshot.sh *) Bash(mkdir -p private/setup-snapshots) Bash(diff *) Bash(pnpm check *)
---

Phase: $ARGUMENTS

- **before**: run `pnpm check` (stop and report if it fails), then `mkdir -p private/setup-snapshots` and `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/before.txt`. Tell the user to run `./setup.sh --skip-brew` (add `--skip-codegraph` if CodeGraph is irrelevant) **in their own terminal** — it prompts interactively — and then invoke `/validate-setup after`.
- **after**: run `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/after.txt`, then `diff -u private/setup-snapshots/before.txt private/setup-snapshots/after.txt`. Explain every changed line: expected from the change under test, or a regression. No diff means setup was a no-op — say whether that was expected.
- Anything else: explain the two phases and stop.

Never run `./setup.sh` yourself.
```

- [ ] **Step 3: Lint skill scripts in `pnpm check`**

In `bin/lib/check`:

```bash
shell_scripts=(
  setup.sh
  setup/*.sh
  .claude/hooks/*.sh
  .claude/skills/*/*.sh
)
```

- [ ] **Step 4: Verify**

Run: `pnpm check 2>&1 | grep -v 'vscode/User/settings.json'` Expected: no new failures. Manual: `/validate-setup before` creates `private/setup-snapshots/before.txt`; running `/validate-setup after` without running setup prints no diff.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/validate-setup bin/lib/check
git commit -m "Add /validate-setup skill: before/after snapshot diff around setup.sh"
```

---

### Task 7: Track user-level Claude instructions

**Files:**

- Create: `tilde/.claude/CLAUDE.md`, `tilde/.claude/rules/serena.md`
- Modify: `setup/symlinks.sh` (`install_dotfiles` `.config` branch; remove unused `AGENTS_DIR`), `setup/README.md` (misc CodeGraph bullet + symlinks section), `agents/README.md:12`

**Interfaces:**

- Produces: `~/.claude/CLAUDE.md` → `tilde/.claude/CLAUDE.md` and `~/.claude/rules` → `tilde/.claude/rules` (directory link, like each `~/.config/<app>`).

- [ ] **Step 1: Copy the live files into the repo, dropping CodeGraph's markers**

```bash
mkdir -p tilde/.claude/rules
grep -v -e '<!-- CODEGRAPH_START -->' -e '<!-- CODEGRAPH_END -->' ~/.claude/CLAUDE.md > tilde/.claude/CLAUDE.md
cp ~/.claude/rules/serena.md tilde/.claude/rules/serena.md
diff ~/.claude/CLAUDE.md tilde/.claude/CLAUDE.md
```

Expected diff: exactly the two removed marker lines. Without markers, `codegraph install` has no block to strip, so it never rewrites the file.

- [ ] **Step 2: Reuse the `.config` branch for `.claude`**

In `install_dotfiles` in `setup/symlinks.sh`, the generic loop links each top-level `tilde/` dir whole, except `.config`, whose children are linked one by one. Linking `~/.claude` whole would pull Claude Code's sessions, caches and `settings.json` into the repo, so give `.claude` the `.config` treatment. Replace:

```bash
      if [ "$item" != ".config" ]; then
```

with:

```bash
      # .config and .claude hold app-written state next to our files: link
      # their children one by one instead of the whole directory
      if [ "$item" != ".config" ] && [ "$item" != ".claude" ]; then
```

Also change the comment above the loop to `# Handle the .config and .claude dirs separately`. That links `~/.claude/CLAUDE.md` and `~/.claude/rules`; `~/.claude/settings.json` and `~/.claude.json` stay untracked (rewritten by Claude Code, plugins, NotchBar and CodeGraph; auth and machine state).

In the `# AI agents` section, delete the unused `AGENTS_DIR="$HOME/.agents"` (shellcheck SC2034; nothing reads it).

- [ ] **Step 3: Switch this machine to the symlinks** (run from the repo root)

`symlink_file` would prompt for the existing file and directory, so replace them directly after confirming the contents match:

```bash
diff -r ~/.claude/rules tilde/.claude/rules \
  && rm -r ~/.claude/rules && ln -s "$PWD/tilde/.claude/rules" ~/.claude/rules
diff <(grep -v CODEGRAPH_ ~/.claude/CLAUDE.md) tilde/.claude/CLAUDE.md \
  && ln -sfn "$PWD/tilde/.claude/CLAUDE.md" ~/.claude/CLAUDE.md
ls -ld ~/.claude/CLAUDE.md ~/.claude/rules
```

Expected: both are symlinks into `…/dotfiles/tilde/.claude/`. Re-running `./setup/symlinks.sh` later must report both as already linked (skipped, no prompt).

- [ ] **Step 4: Update docs**

In `setup/README.md`, misc section, the "Connects CodeGraph to Claude Code…" bullet: replace the clause about writing a marker-fenced block to `~/.claude/CLAUDE.md`, and the sentence about the installer replacing files by rename, with:

```markdown
CodeGraph 1.6+ no longer writes `~/.claude/CLAUDE.md`, but its installer still strips an old `CODEGRAPH_START`/`CODEGRAPH_END` block there by writing a new copy and renaming it over the old one — which would replace a symlink. The tracked `tilde/.claude/CLAUDE.md` keeps that guidance without the markers, so there's nothing to strip. The same rename is why the step targets Claude Code only: running it for Codex would turn the `~/.codex/AGENTS.md` symlink into a regular file.
```

In the symlinks section, change "each item under `tilde/.config/` is linked individually into `~/.config/`. `tilde/.codex` and `tilde/.ssh` are handled separately." to:

```markdown
each item under `tilde/.config/` and `tilde/.claude/` is linked individually into `~/.config/` and `~/.claude/` (Claude Code's `CLAUDE.md` and `rules/`; its `settings.json` and `~/.claude.json` are rewritten by tools and hold machine state, so they aren't tracked). `tilde/.codex` and `tilde/.ssh` are handled separately.
```

In `agents/README.md`, append to the **Claude Code** paragraph (line 12):

```markdown
Its user-level instructions and rules live in [`tilde/.claude/`](../tilde/.claude/) and are linked by `setup/symlinks.sh`.
```

- [ ] **Step 5: Verify the CodeGraph re-run keeps the symlink**

```bash
codegraph install --yes --target claude --location global --no-color > /dev/null
test -L ~/.claude/CLAUDE.md && echo "still a symlink" || echo "REPLACED"
git diff --stat tilde/.claude/
```

Expected: `still a symlink`, no diff in `tilde/.claude/`. If `REPLACED`: restore with `ln -sfn "$PWD/tilde/.claude/CLAUDE.md" ~/.claude/CLAUDE.md`, stop, and report — don't track CLAUDE.md until the installer's behavior is understood.

Then: `pnpm check 2>&1 | grep -v 'vscode/User/settings.json'` → no new failures. New Claude session → `/memory` lists `~/.claude/CLAUDE.md` and the Serena rule.

- [ ] **Step 6: Commit**

```bash
git add tilde/.claude setup/symlinks.sh setup/README.md agents/README.md
git commit -m "Track Claude Code's user-level instructions and rules in tilde/.claude"
```

---

### Task 8: Install and register Serena from setup; upgrade it in upup

**Files:**

- Modify: `setup/misc.sh` (after the mise MCP block, ~line 166), `bin/upup` (after "Updating mise tools…"), `setup/README.md` (misc), `README.md` (Updating section)

- [ ] **Step 1: Add the Serena block to `setup/misc.sh`**

After the mise MCP `fi` (the block that uses `$claude_bin`):

```bash
# Serena — symbol-level code tools over language servers, as an MCP server for
# Claude Code. Installed as a uv tool (its only documented install method);
# `bin/upup` upgrades it. Launch invariants (claude-code context, one
# user-scope registration, --project-from-cwd): ~/.claude/rules/serena.md
# https://github.com/oraios/serena
serena_bin="$HOME/.local/bin/serena"
if command_exists uv && [ ! -x "$serena_bin" ]; then
  info "🧰 Installing Serena…"
  uv tool install -p 3.13 serena-agent | indent \
    || warning "Serena install failed — run it later: uv tool install -p 3.13 serena-agent"
fi
if [ -x "$serena_bin" ] && [ -x "$claude_bin" ]; then
  if "$claude_bin" mcp get serena &> /dev/null; then
    echo "Serena MCP server already registered with Claude Code" | indent
  else
    info "🔌 Registering Serena's MCP server with Claude Code…"
    "$claude_bin" mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd | indent \
      || warning "Registering Serena failed — run: claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd"
  fi
fi
```

- [ ] **Step 2: Upgrade uv tools in `bin/upup`**

After the `mise upgrade` block's `echo`:

```bash
# uv tools (Serena)
if command -v uv > /dev/null; then
  header "Updating uv tools…"
  uv tool upgrade --all
  echo
fi
```

Also update the header comment line 3 to: `# Get macOS software updates, update Homebrew (incl. VS Code), mise and uv tools, dotfiles, Raycast and Amp.`

- [ ] **Step 3: Verify idempotence on this machine**

Run: `bash -n setup/misc.sh bin/upup && shellcheck --severity=error setup/misc.sh bin/upup` Then confirm both guards would skip on this machine (no reinstall, no duplicate registration):

```bash
test -x ~/.local/bin/serena && echo "install: skipped"
claude mcp get serena > /dev/null && echo "registration: skipped"
```

Expected: both lines print. On a fresh Mac, `./setup.sh --skip-brew` (run by the user in a terminal, bracketed by `/validate-setup before|after`) shows `serena` newly listed under `## claude mcp (names)`.

- [ ] **Step 4: Docs**

In `setup/README.md`, misc section, add after the mise MCP bullet:

```markdown
- Installs [Serena](https://github.com/oraios/serena) with `uv tool install -p 3.13 serena-agent` if missing, and registers it with Claude Code at user scope (`serena start-mcp-server --context claude-code --project-from-cwd`) unless a `serena` server exists. This repo turns Serena's tools off in `.claude/settings.json`; other projects get it automatically.
```

In `README.md`, Updating section, change the `upup` sentence to:

```markdown
Run `upup` for upgrades: macOS, Homebrew packages, mise tools (Node/Python patch releases, CodeGraph, the npm CLIs), uv tools (Serena) and Amp.
```

- [ ] **Step 5: Commit**

```bash
git add setup/misc.sh bin/upup setup/README.md README.md
git commit -m "Install and register Serena during setup; upgrade uv tools in upup"
```

---

### Task 9: Clear shellcheck warnings and raise the gate to `warning`

**Files:**

- Create: `.shellcheckrc`
- Modify: `setup.sh:~111`, `setup/misc.sh:~98`, `setup/symlinks.sh:306,317`, `bin/lint-weasel-words:30-31`, `bin/pull:13-20`, `bin/br:44`, `bin/optimize-image:71,89,108-109,133,137,149,151`, `bin/lib/check:36`, `.claude/hooks/lint-edited.sh` (severity), `CLAUDE.md` + `bin/CLAUDE.md` (severity mentions)

- [ ] **Step 1: Capture the failing baseline**

```bash
files=(setup.sh setup/*.sh .claude/hooks/*.sh .claude/skills/*/*.sh)
while IFS= read -r s; do files+=("$s"); done < <(find bin -maxdepth 1 -type f -exec grep -El '^#!(/bin/(ba)?sh|/usr/bin/env (ba)?sh)$' {} + | grep -v '^bin/license$')
shellcheck --severity=warning -f gcc "${files[@]}" | wc -l
```

Expected: `17` — 16 from the default checks (17 minus the `AGENTS_DIR` line removed in Task 7) plus 1 from the optional check enabled in Step 2 (`bin/lint-weasel-words:30` `WORDSDIR`) once `.shellcheckrc` exists; `16` before it. Any extra lines come from the new `.claude/` scripts — fix those too.

- [ ] **Step 2: `.shellcheckrc` and the SC2088 messages**

`.shellcheckrc` (read by `pnpm check`, the hook and the VS Code ShellCheck extension — found by walking up from each script):

```ini
# ShellCheck config for this repo.
# Optional check: flag UPPERCASE variables that are read but never assigned —
# the typo/unset-variable bug class (see bin/pull's base_dir, lowercase).
# Intentional optional env vars get ${VAR:-} to say so.
enable=check-unassigned-uppercase
```

`bin/lint-weasel-words:30-31` (`WORDSDIR` is an optional env var):

```bash
if [ -f "${WORDSDIR:-}/weasels" ]; then
  wordfile="${WORDSDIR:-}/weasels"
```

SC2088 — the `~` in these messages is display text, so keep it, but scope each exception:

- `setup/symlinks.sh` 306 and 317: use the file's existing `tildify` helper —
  `warn "$(tildify "$ssh_dir") is a symlink to $(readlink "$ssh_dir") — leaving it alone"` and
  `warn "$(tildify "$ssh_dir")/github_personal.pub not found — GitHub SSH needs it to pick your 1Password key (see tilde/.ssh/config)"`.
- `setup.sh` ~line 111, directly above the `if [ ! -e "$LEGACY_LINK" ]` block (a directive before a compound command covers the whole `if`/`elif`):
  `# shellcheck disable=SC2088 # "~/dotfiles" in messages is display text`
- `setup/misc.sh` line above line 98 (`warning "~/.config/mise is not linked…"`):
  `# shellcheck disable=SC2088 # display text, not a path`

- [ ] **Step 3: Fix `bin/pull` (real bug: `base_dir`/`current_dir` never set)**

After the `# Abort if this isn't a git repository` line and before `# Colors`, add:

```bash
# Lockfile checks are relative to the repo root; remember where we started
base_dir=$(git rev-parse --show-cdup)
current_dir=$(pwd)
```

- [ ] **Step 4: Remove unused variables**

- `bin/br:44`: delete `color_bold="$(tput bold)"`.
- `bin/optimize-image:71`: delete `local new_format="$4"`.

- [ ] **Step 5: `bin/optimize-image` — declare and assign separately (SC2155), annotate the trap (SC2064)**

Replace each flagged line:

```bash
local directory
directory="$(dirname "$input")"
```

```bash
local tempdir
tempdir=$(mktemp -d)
# shellcheck disable=SC2064 # expand now: $tempdir is local and gone when RETURN fires
trap "rm -rf '$tempdir'" RETURN
```

```bash
local smallest_size
smallest_size=$(stat -f%z "$input" 2> /dev/null || stat -c%s "$input")
```

```bash
local size
size=$(stat -f%z "$file" 2> /dev/null || stat -c%s "$file")
```

```bash
local original_size
original_size=$(stat -f%z "$input" 2> /dev/null || stat -c%s "$input")
local new_ext="${smallest##*.}"
local output
output="$directory/$(basename "$basename").${new_ext}"
```

- [ ] **Step 6: Verify zero warnings, then raise the gate**

Re-run the Step 1 command. Expected: `0`. Then `bin/lib/check` line 36: `shellcheck --severity=warning "${shell_scripts[@]}"`, and in `.claude/hooks/lint-edited.sh`: `run shellcheck --severity=warning "$rel"`. Update the two docs mentions: in `CLAUDE.md` (`build-commands` section) and `bin/CLAUDE.md` (conventions), `shellcheck --severity=error` → `shellcheck --severity=warning`.

- [ ] **Step 7: Behavior checks**

```bash
pnpm check 2>&1 | grep -v 'vscode/User/settings.json'
.claude/hooks/test-lint-edited.sh
bin/pull
```

Expected: check has no new failures; hook self-check passes; `bin/pull` (clean tree, after the commits above) prints an up-to-date/rebase result with no bash errors. The lockfile branch only runs when a pull brings in `package.json`/lockfile changes — confirm it on the next real pull that does.

- [ ] **Step 8: Commit**

```bash
git add .shellcheckrc setup.sh setup/misc.sh setup/symlinks.sh bin/lint-weasel-words bin/pull bin/br bin/optimize-image bin/lib/check .claude/hooks/lint-edited.sh CLAUDE.md bin/CLAUDE.md
git commit -m "Fix shellcheck warnings (incl. bin/pull's unset dirs) and gate on warnings"
```

---

### Task 10: Archive the plan

**Files:**

- Move: `docs/superpowers/plans/2026-09-30-claude-code-project-config.md` → `docs/superpowers/plans/completed/`
- Modify: `CLAUDE.md` (`architecture` section, `docs/` line)

- [ ] **Step 1: Confirm every task's checkboxes are ticked and the whole-branch review passed**

- [ ] **Step 2: Move it**

```bash
mkdir -p docs/superpowers/plans/completed
git mv docs/superpowers/plans/2026-09-30-claude-code-project-config.md docs/superpowers/plans/completed/
```

- [ ] **Step 3: Verify and commit**

Run: `pnpm check 2>&1 | grep -v 'vscode/User/settings.json'` → no new failures.

```bash
git add docs/superpowers/plans
git commit -m "Archive the Claude Code project configuration plan"
```

---

## Out of scope (noted, not planned)

- Tracking `~/.claude/settings.json` (rewritten by tools; revisit if a JSON-merge approach is wanted).
- Raising shellcheck to `info` (40× SC2086 quoting — separate cleanup).
- auto-memory excludes/formatter (upstream issue #35); watch whether it re-adds rule content to CLAUDE.md after Task 3.

---

## Execution outcome (2026-09-30)

Executed inline on branch `claude-code-project-config` (10 task commits + 3 final-review fixes). Where execution departed from the text above:

- **Task 7:** `~/.claude/CLAUDE.md` is **not** tracked. CodeGraph 1.6.0 still appends its `CODEGRAPH_START/END` block and replaces the file by rename (the research said it no longer did), so the hand-written pointer moved to the tracked `tilde/.claude/rules/index.md` and the live `CLAUDE.md` holds only CodeGraph's block.
- **Final review:** `~/.claude/rules` is a real directory with each tracked rule linked into it (not a directory link), so machine-local rules survive setup; the lint hook's scope was narrowed to exactly what `pnpm check` gates; the setup-script `ask` rules cover the common invocation forms (still a guard, not a hard boundary).
- **Task 3:** two facts from the deleted CLAUDE.md sections (the `--skip-codegraph` shim invariant, fresh-install paths being unverifiable) were kept in `.claude/rules/setup.md`.
- `.superpowers/` (plan-execution scratch) was added to `.prettierignore`; `/add-tool` says `upup` upgrades all uv tools.
- Not verified in-session (new skills/agents load only in a new session): `/docs-audit`, `/agents`, `/validate-setup`, and the `ask` prompts.
