# Bin Script Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `bin/` scripts that corrupt a tracked file, touch the real home from a self-check, or no longer work on this Mac, and lock each fix with a fixture test that `pnpm check` runs.

**Architecture:** Two new self-checks in the existing `bin/lib/test-*` style: `test-claude-config` runs the real `bin/claude-config` against scratch `HOME`, `CLAUDE_CONFIG_DIR` and `CLAUDE_CONFIG_SAVE_DIR`; `test-bin` gives the small scripts (`git-find`, `git-tidy`, `help`, `serve`) a scratch repo and asserts observable results. Existing self-checks (`test-upup`, `test-hindsight-memory`, `test_build_catalog.py`, `test-conventions`) gain the cases their scripts were missing. Each fix is the smallest change in the script that owns it.

**Tech Stack:** bash 3.2, jq, Node (`bin/lib/get-tldr-md`), tlrc (`tldr`), Python 3.11+ through mise for the catalog test.

**Spec:** `docs/superpowers/specs/2026-10-27-repo-audit-assessment.md`, section C (C1 to C17) and A9.

## Global Constraints

- Self-checks never touch the real `$HOME`, `~/.claude` or the repo's tracked files: every one exports a scratch `HOME` and `CLAUDE_CONFIG_DIR`, and the scripts they drive must honour both (`bin/upup`, `bin/claude-config` and `agents/catalog/build_catalog.py` included).
- A tracked file (`agents/claude-*.txt`, `agents/claude-settings.json`) is rewritten only through `.tmp` + `mv`, and only when its source parsed; an unparsable source warns and keeps the file.
- Every `bin/` script keeps a header comment that `help <script>` renders (tlrc's page format: one sentence per line, no wrapped lines).
- `docs/README.md` lists every user-facing `bin/` script; internal helpers (`bin/lib/*`, `docker-devcontainer`, `rea-mcp`, `nyan`, `lint-*`) are exempt.
- One task is one commit, `pnpm check` green before it, subject short and imperative, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (omitted below). `bin/CLAUDE.md` is edited in the same commit when a script's documented behavior changes. No em-dash characters.

## Review Focus

1. `claude-config save` while Claude Code is writing `installed_plugins.json` (a half-written file): the tracked list must survive (Task 1).
2. `pnpm check` on a Mac where `~/.claude/skills/reverse-engineer-anything` is a symlink: nothing outside the scratch home may be deleted (Task 2).
3. `help <script>` on a Mac without `tldr` (the CI runner): the render check must skip, not fail (Task 4).
4. `git-tidy` with a merged branch checked out in another worktree: `git branch -d` refuses it; the script must report and continue, not abort the loop (Task 6).
5. `upup` when `rea setup` prints a warning on stderr before its JSON: the step must still report `changed` or `ok` from the JSON, not fall back to `ok` on a parse failure (Task 7).

---

### Task 1: `claude-config save` never shrinks a tracked list, and never saves a token (C1, A9, C13, C14)

**Files:**
- Modify: `bin/claude-config:57` (env filter), `:90-101` (`known_marketplaces`, `installed_plugins`), `:113-129` (`save_plugins`), `:252` (`tildify`), plus a `trap` for `.tmp` files
- Create: `bin/lib/test-claude-config`
- Modify: `bin/lib/check`, `CLAUDE.md` (gate list), `.claude/rules/claude-config.md` (the "never shrinks" sentence gains "or when its source does not parse")

**Interfaces:**
- Produces: `valid_json <file>` in `bin/claude-config`, exit 0 when `jq -e . "$1"` succeeds, else prints `claude-config: <~/path> is not valid JSON — kept <~/tracked>` to stderr and exits 1.

- [x] **Step 1: Write the failing test**

`bin/lib/test-claude-config` sets `HOME=$tmp/home CLAUDE_CONFIG_DIR=$tmp/cfg CLAUDE_CONFIG_SAVE_DIR=$tmp/save`, seeds `$tmp/save/claude-plugins.txt` with `marketplace a b`, `plugin x@a`, `plugin y@a disabled`, and checks:

```bash
echo '{"plugins": {' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
"$script" save plugins 2> "$tmp/err"
check "corrupt registry keeps the list" "[ \"\$(grep -c '^plugin ' '$CLAUDE_CONFIG_SAVE_DIR/claude-plugins.txt')\" = 2 ]"
check "corrupt registry warns" "grep -q 'not valid JSON' '$tmp/err'"
check "no tmp file left" "[ ! -e '$CLAUDE_CONFIG_SAVE_DIR/claude-plugins.txt.tmp' ]"
printf '{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"x","CLAUDE_CODE_CERT_STORE":"bundled,system","DISABLE_TELEMETRY":"1"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
"$script" save settings
check "token never saved" "! grep -q OAUTH_TOKEN '$CLAUDE_CONFIG_SAVE_DIR/claude-settings.json'"
check "cert store kept" "grep -q CERT_STORE '$CLAUDE_CONFIG_SAVE_DIR/claude-settings.json'"
check "warning paths use ~" "grep -q '~/' '$tmp/err'"
```

Run the whole file twice when `/opt/homebrew/bin/bash` exists, once per bash, so the `tildify` fix (C13) is covered under bash 5.

- [x] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-claude-config`
Expected: `FAIL corrupt registry keeps the list` (0 plugin lines), `FAIL token never saved`.

- [x] **Step 3: Fix the script**

Add `valid_json`; in `save_plugins` call `valid_json "$config/plugins/installed_plugins.json" || return 0` after `missing_source`, and the same for `known_marketplaces.json` when present and for `$settings` before the `disabled` lookup; drop the three `|| true`. Extend the env filter with `and (.key | test("TOKEN|SECRET|PASSPHRASE|API_KEY|CLIENT_KEY") | not)`. Add `trap 'rm -f "$save_dir"/*.tmp' EXIT` near the top. Change `tildify` to `[[ $1 == "$HOME"* ]] && printf '~%s' "${1#"$HOME"}" || printf '%s' "$1"` (the form `bin/hindsight-memory` uses), and apply the same to `bin/copy-ssh:17`.

- [x] **Step 4: Run the test and the gate**

Run: `bash bin/lib/test-claude-config && pnpm check`
Expected: all `ok`; gate exit 0 after adding `bash bin/lib/test-claude-config > /dev/null` to `bin/lib/check`.

- [x] **Step 5: Commit**

```bash
git add bin/claude-config bin/copy-ssh bin/lib/test-claude-config bin/lib/check CLAUDE.md .claude/rules/claude-config.md
git commit -m "Keep the tracked plugin list when the registry does not parse"
```

### Task 2: `test-upup` runs in a scratch home (C2)

**Files:**
- Modify: `bin/lib/test-upup:22` (export `HOME="$tmp/home"` and create it)
- Modify: `bin/upup:322` (use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/…`)

- [x] **Step 1: Add the failing check**

In `test-upup`, before the "changes" run: `mkdir -p "$CLAUDE_CONFIG_DIR/skills"; ln -s /nonexistent "$CLAUDE_CONFIG_DIR/skills/reverse-engineer-anything"`, and after it `check_true "stale REA skill symlink removed in the scratch config dir" test ! -L "$CLAUDE_CONFIG_DIR/skills/reverse-engineer-anything"`.

- [x] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-upup`
Expected: that check fails (upup looked under the real `$HOME/.claude`).

- [x] **Step 3: Fix both files**, then run `bash bin/lib/test-upup && pnpm check`.

- [x] **Step 4: Commit**

```bash
git add bin/lib/test-upup bin/upup
git commit -m "Keep upup's self-check out of the real home"
```

### Task 3: `serve` works without webrick (C3)

**Files:**
- Modify: `bin/serve:14-20`
- Create: `bin/lib/test-bin` (harness; this task adds its first case)
- Modify: `bin/lib/check`, `CLAUDE.md` (gate list)

**Interfaces:**
- Produces: `bin/lib/test-bin` with `check "<name>" "<shell test>"` from `codex-config.sh`, a scratch `HOME`, and a scratch git repo at `$tmp/repo` with `main` plus a merged branch `domain-fix` and an unmerged `wip` (Tasks 5 and 6 use it).

- [x] **Step 1: Write the failing check**

```bash
(cd "$tmp" && SERVE_NO_OPEN=1 "$root/bin/serve" 8099 > /dev/null 2>&1 &) ; sleep 1
check "serve answers" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8099/)\" = 200 ]"
pkill -f 'http.server 8099' || true
```

- [x] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-bin`
Expected: `FAIL serve answers` (ruby's `LoadError: cannot load such file -- webrick`).

- [x] **Step 3: Switch to Python's server**

`bin/serve`: `[ -n "${SERVE_NO_OPEN:-}" ] || open "http://localhost:${port}/"`, then `exec python3 -m http.server "$port"`. Update the header's "See more" link to Python's `http.server` docs.

- [x] **Step 4: Run the test and the gate, then commit**

Run: `bash bin/lib/test-bin && pnpm check`

```bash
git add bin/serve bin/lib/test-bin bin/lib/check CLAUDE.md
git commit -m "Serve with Python's http.server"
```

### Task 4: Every header renders through `help` (C5, C10)

**Files:**
- Modify: `bin/brewpick:3-4`, `bin/nnn:10-11` (join each wrapped line)
- Modify: `bin/help:36-43` (delete the temp dir after rendering; refuse a directory)
- Modify: `bin/lib/get-tldr-md:57-70` (`fs.statSync(binFilePath).isFile()` before reading)
- Modify: `bin/lib/test-conventions:34-37`

- [x] **Step 1: Replace the line-2 check with a render check**

```bash
if command -v tldr > /dev/null; then
  for file in bin/*; do
    [[ -f $file && $file != bin/CLAUDE.md ]] || continue
    bin/help "${file#bin/}" > /dev/null 2>&1 || fail "help render: $file"
  done
else
  echo "test-conventions: tldr not found, skipping the help render check" >&2
  for file in bin/*; do ... (keep the existing line-2 check as the fallback) ... done
fi
before=$(ls -d "${TMPDIR:-/tmp}"/tldr-* 2> /dev/null | wc -l)
bin/help serve > /dev/null
[ "$(ls -d "${TMPDIR:-/tmp}"/tldr-* 2> /dev/null | wc -l)" -le "$before" ] || fail "help leaves temp dirs"
bin/help lib > /dev/null 2>&1 && fail "help lib should fail cleanly" || true
```

- [x] **Step 2: Run it and watch it fail**

Run: `bash bin/lib/test-conventions`
Expected: `FAIL: help render: bin/brewpick`.

- [x] **Step 3: Fix the two headers, the temp dir and the directory case**

In `bin/help`, keep the generated page's directory in a variable and `rm -rf` it after `tldr --render` (the page lives in `$(dirname "$md")`, created by `get-tldr-md` only for `bin/` scripts). In `get-tldr-md`, `isFile()` guard; on a directory print nothing and exit 1 so `help` falls through to a `No help for <name>` line.

- [x] **Step 4: Run the lint and the gate, then commit**

Run: `bash bin/lib/test-conventions && pnpm check`

```bash
git add bin/brewpick bin/nnn bin/help bin/lib/get-tldr-md bin/lib/test-conventions
git commit -m "Render every bin header through help and clean up its temp pages"
```

### Task 5: `git-find` finds top-level files and refuses no argument (C4)

**Files:**
- Modify: `bin/git-find:17-19`
- Modify: `bin/lib/test-bin`

- [x] **Step 1: Add the failing checks** (in the scratch repo, which has a root file `top.txt` and `sub/inner.txt` committed):

```bash
check "git-find top-level" "(cd '$tmp/repo' && '$root/bin/git-find' top.txt | grep -qx top.txt)"
check "git-find nested" "(cd '$tmp/repo' && '$root/bin/git-find' inner.txt | grep -qx sub/inner.txt)"
check "git-find usage" "! '$root/bin/git-find' > /dev/null 2>&1"
```

- [x] **Step 2: Run and watch `git-find top-level` and `git-find usage` fail.**

- [x] **Step 3: Fix:** `[ $# -eq 1 ] || { echo "usage: git-find <file>" >&2; exit 64; }` and the pathspec `":(glob)**/$1"`.

- [x] **Step 4: Run `bash bin/lib/test-bin && pnpm check`, then commit**

```bash
git add bin/git-find bin/lib/test-bin
git commit -m "Let git-find match top-level files"
```

### Task 6: `git-tidy` deletes exactly the merged branches (C11)

**Files:**
- Modify: `bin/git-tidy:18-20,31`
- Modify: `bin/lib/test-bin`

- [x] **Step 1: Add the failing checks**

```bash
(cd "$tmp/repo" && "$root/bin/git-tidy" > /dev/null 2>&1)
check "merged domain-fix deleted" "! git -C '$tmp/repo' show-ref --verify -q refs/heads/domain-fix"
check "unmerged wip kept" "git -C '$tmp/repo' show-ref --verify -q refs/heads/wip"
check "main kept" "git -C '$tmp/repo' show-ref --verify -q refs/heads/main"
```

- [x] **Step 2: Run and watch `merged domain-fix deleted` fail** (its name contains `main`).

- [x] **Step 3: Fix:** `branches()` becomes `git for-each-ref --merged HEAD --format='%(refname:short)' refs/heads | grep -vxE 'main|master'`; the delete loop becomes `while read -r b; do git branch -d "$b" || true; done` so a worktree-checked-out branch is reported and skipped.

- [x] **Step 4: Run `bash bin/lib/test-bin && pnpm check`, then commit**

```bash
git add bin/git-tidy bin/lib/test-bin
git commit -m "Match whole branch names in git-tidy"
```

### Task 7: `upup` notices agree, the macOS step reports once, and REA's JSON survives stderr (C8, C9, C17)

**Files:**
- Modify: `bin/upup:109-126` (macOS), `:199-203,221` (mise prune wording, `MISE_DATA_DIR`), `:323` (REA capture)
- Modify: `bin/lib/test-upup` (stub `softwareupdate` with a `$STATE/macos` and `$STATE/macos-fails` case; make the `rea` stub print `warning: x` to stderr before its JSON)
- Modify: `bin/CLAUDE.md:29` (the `mise prune` sentence)

- [x] **Step 1: Add the failing checks**

```bash
touch "$STATE/macos" "$STATE/macos-fails"
run
check_true "failed macOS install reports fail only" has '^✖ macOS'
check_false "failed macOS install does not also say changed" has '^↻ macOS'
touch "$STATE/rea"   # stub now writes "warning: x" to stderr first
check_true "REA skill change seen despite stderr noise" has '^↻ REA skill'
```

- [x] **Step 2: Run and watch them fail.**

- [x] **Step 3: Fix:** in the macOS step record `changed` only after a successful install; in the mise-WARN notice say `a version no config pins goes with: mise prune (not while a mise rust install shadows rustup; see the Rust step)` and make the rustup notice reference `${MISE_DATA_DIR:-$HOME/.local/share/mise}`; for REA, call `rea setup … --format json 2>> "$log"` into `out` directly instead of through `capture`.

- [x] **Step 4: Run `bash bin/lib/test-upup && pnpm check`, then commit**

```bash
git add bin/upup bin/lib/test-upup bin/CLAUDE.md
git commit -m "Report the macOS step once and parse REA's JSON past stderr"
```

### Task 8: `hindsight-memory` unwires only what it wired (C6)

**Files:**
- Modify: `bin/hindsight-memory:158,243`
- Modify: `bin/lib/test-hindsight-memory:130,149`

- [x] **Step 1: Change the two expectations** to `"uninstall claude-code codex"`, run `bash bin/lib/test-hindsight-memory`, watch both fail.
- [x] **Step 2: Change both calls** to `uninstall claude-code codex` (the harness list `run_installer` installs; factor it into one variable used by both).
- [x] **Step 3: Run `bash bin/lib/test-hindsight-memory && pnpm check`, then commit**

```bash
git add bin/hindsight-memory bin/lib/test-hindsight-memory
git commit -m "Uninstall only the harnesses hindsight-memory installed"
```

### Task 9: `pull` handles several lockfiles and a no-op pull (C12)

**Files:**
- Modify: `bin/pull:49-51` and the `has_changed` logic that reads `ORIG_HEAD`

- [ ] **Step 1: Save `before=$(git rev-parse HEAD)` before the pull** and compare against it instead of `ORIG_HEAD`; in `change_dir`, take the first matching path (`head -n 1`).
- [ ] **Step 2: Verify by hand** in a scratch clone with two `package.json` files changed upstream: `pull` installs in the first one's directory; a second `pull` with nothing new installs nothing.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Compare pull against the pre-pull HEAD"`.

### Task 10: The catalog honours `CLAUDE_CONFIG_DIR` (C15)

**Files:**
- Modify: `agents/catalog/build_catalog.py:18` (`CLAUDE = Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude"))`), `:210-212` (delete the dead `by_name`)
- Modify: `agents/catalog/test_build_catalog.py`

- [ ] **Step 1: Add the failing assertion**: with `CLAUDE_CONFIG_DIR` set in `os.environ` before `import build_catalog`, `b.CLAUDE == Path(that dir)`.
- [ ] **Step 2: Run `mise exec python -- python3 agents/catalog/test_build_catalog.py`**, watch it fail, fix, rerun.
- [ ] **Step 3: `pnpm check`, commit**: `git commit -m "Read the catalog from CLAUDE_CONFIG_DIR"`.

### Task 11: Retire `radio`, index the rest (C7, C16)

**Files:**
- Delete: `bin/radio`
- Modify: `docs/README.md` (rows for `claude-config`, `claude-catalog`, `ds-delete`, `dust`, `line`, `git-setup`, `npmplease`)

Decision recorded here: `radio` is deleted (no `mpv` installed or listed; alternative is `brew "mpv"` plus a row). Change it before Step 1 if you want the alternative.

- [ ] **Step 1: `git rm bin/radio`**; add the seven rows, each one line in the existing table style, with the flags `help <script>` shows.
- [ ] **Step 2: `pnpm check`** (the Task 4 render check covers the headers), then commit: `git commit -m "Index the unlisted bin scripts and retire radio"`.

---

## Self-review notes

- Spec coverage: C1 and A9 and C13 and C14 Task 1, C2 Task 2, C3 Task 3, C5 and C10 Task 4, C4 Task 5, C11 Task 6, C8 and C9 and C17 Task 7, C6 Task 8, C12 Task 9, C15 Task 10, C7 and C16 Task 11.
- Task 9 has no fixture test (pull drives a remote); its verification is the manual scratch clone, stated in the task.
- Review Focus items map to Tasks 1, 2, 4, 6, 7.
