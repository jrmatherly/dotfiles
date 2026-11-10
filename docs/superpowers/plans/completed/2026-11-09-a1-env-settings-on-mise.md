# A1. Env Settings on mise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A value written with `mise set --override KEY=value` beats the shell's own export of `KEY` in every new zsh, including shells that never reach a prompt, and `mise unset --override KEY` gives the export back.

**Architecture:** mise's `config.override.toml` is the only store. Interactive shells already get it from `mise activate` at the first prompt. A new `zsh/override-env.zsh` covers every other shell: it sources a cache of the override file's `[env]` keys and runs mise only when the override file is newer than the cache. A version floor script guards setup, CI installs mise and uv, and one self-check proves the whole loop on every `pnpm check`.

**Tech Stack:** zsh 5.9, bash 3.2, mise 2026.11.5, GitHub Actions (`jdx/mise-action`, `astral-sh/setup-uv`).

**Spec:** `docs/superpowers/specs/2026-11-09-mise-first-setup-and-settings-ui.md`, phase "A1. Env settings on mise".

**Line numbers** are from commit `9af6244`. An earlier phase may have moved them, so find the quoted text with `grep -n` before editing.

## Global Constraints

- Minimum mise version: 2026.11.5. Setup fails with a clear message below it.
- Shell startup must not run an interpreter or mise unless a cached file is stale.
- Machine-local files never enter git: `config.override.toml`, `config.*.override.toml`, `config.local.toml`, `config.*.local.toml`, `miserc.local.toml` under `tilde/.config/mise/`.
- Tests that isolate mise set `MISE_CONFIG_DIR` only. Never set `MISE_GLOBAL_CONFIG_FILE`. It turns override files off.
- Existing shell exports (`zsh/env.zsh`, `tilde/.zshenv`, `~/.zsh.local`) stay where they are. They are seeds (spec D3).
- Bash scripts start with `#!/bin/bash` and a tldr-style header, define their helpers inline, and pass `pnpm check`.
- GitHub Actions are pinned to a commit SHA with the version in a comment, as in `check.yml`.
- Commit subjects are short, imperative, sentence case, with no conventional-commit prefix. Run `pnpm check` before every commit.
- Do not hand-format `CLAUDE.md` (Prettier ignores it). Keep it under 12000 bytes and every line under 1000 bytes (`bin/lib/test-conventions`).
- No task runs `mise set --override` against the live config. All mise writes happen under a temp `MISE_CONFIG_DIR`.

## Decisions this plan makes

The spec leaves these open. Each was run in a scratch copy of the repo on 2026-11-09 with mise 2026.11.5.

1. **Two source sites.** The spec names `tilde/.zshenv` only. `zsh/env.zsh` and `~/.zsh.local` export after `.zshenv`, so in `zsh -ic` a seed beat the override (measured: `local`, expected `over`). The file is sourced again as the last line of `tilde/.zshrc`. The second source costs two `stat` calls.
2. **Cache format.** `mise env --dotenv` prints values raw and unquoted (`SP=a b "q"`). The cache holds `export KEY='value'` lines requoted with zsh `${(qq)}`. Known limits: a multi-line value keeps its first line, and `KEY = false` (mise's unset) is not carried.
3. **Staleness test** is `[[ ! $cache -nt $override ]]`. It is true for a missing cache and for equal timestamps.
4. **mise path.** `.zshenv` runs before `.zprofile` puts mise on PATH. The file takes the first executable of `${commands[mise]}`, `~/.local/bin/mise` (where mise lives after A4) and `${HOMEBREW_PREFIX:-/opt/homebrew}/bin/mise` (where it lives today). No later plan needs to touch this. `HOMEBREW_PREFIX` is read, as `zsh/init.zsh` reads it, so the self-check can point it at an empty folder and reach the no-mise branch on a Mac that has Homebrew's mise.
5. **Failure keeps the last good cache.** When `mise env` fails (bad TOML, bad template) or mise is not found, the old cache is still sourced. An interactive shell prints one warning line, although it sources the file twice (a shell-local flag, `_override_env_warned`).
6. **`DOTFILES_NO_OVERRIDE_ENV`** set to anything makes the file do nothing. A2's env adapter uses it to read a seed.
7. **The floor lives in `setup/mise-floor.sh`**, called from `setup/misc.sh`. Shell code reads the value `2026.11.5` from that file only. CI pins mise to the same value and the self-check asserts they match. A2's settings package carries its own copy as `FLOOR`, so raising the floor means editing both.
11. **One cache per override file.** The cache file name carries the override file's path with every character outside `A-Za-z0-9` replaced by `_`. Two mise config dirs under one `HOME` (a later plan's test with a scratch `MISE_CONFIG_DIR` and the real `HOME`) then never read each other's values.
8. **`bin/lib/check` keeps CI's Python.** With mise on the runner, `mise exec python` would download a Python. The guard becomes "mise has a python installed".
9. **Docs describe the mechanism, not the UI.** The UI arrives in A2. A1 documents `mise set --override` and `mise unset --override`.
10. **The self-check fails, not skips, without mise.** The spec wants it on every `pnpm check`.

## Review Focus

Each line names its test in `bin/lib/test-override-env`.

1. A value with spaces and quotes survives the cache unchanged. Test: `SP`, Task 3.
2. An interactive shell where `~/.zsh.local` re-exports the key still shows the override. Test: "interactive shell", Task 3.
3. A hand-edited override file that mise cannot parse keeps the last good values and does not break shell startup. Test: "unreadable override file", Task 3.
4. A new terminal window runs `.zshenv` with no mise on PATH. When mise is at none of the three places, a shell that never prompts prints nothing and an interactive shell prints the warning once. Both keep the last good values. Tests: "stale cache without mise", Task 3.
6. A shell started with another `MISE_CONFIG_DIR` under the same `HOME` does not change what the first config dir's shells see. Test: "a second mise config dir", Task 3.
5. Resetting the last key leaves an `[env]` table with no keys. The cache empties and the seed returns. Test: "resetting every key", Task 3.

---

### Task 1: Gitignore the machine-local mise files

**Files:**
- Create: `bin/lib/test-override-env`
- Modify: `.gitignore` (after line 20, `tilde/.config/hunk/state.json`)
- Modify: `bin/lib/check` (after line 83, the `test-shell` call)

**Interfaces:**
- Produces: `bin/lib/test-override-env`, a bash self-check that prints `override-env: all checks passed`. Tasks 2 and 3 append to it above that final `echo`.

- [ ] **Step 1: Write the failing test**

Create `bin/lib/test-override-env`, mode 755:

```bash
#!/bin/bash
#
# Self-check for the mise override layer: the version floor, the gitignored machine-local files and the shell cache.
#
# - Run it (pnpm check does too); exits 1 naming the first failed assertion:
#
# `test-override-env`
#
# ---
# Runs zsh against this repo's tilde/.zshenv and tilde/.zshrc through a temp
# ZDOTDIR, HOME and MISE_CONFIG_DIR, so the live mise config and
# ~/.cache/dotfiles are never touched. Fails when mise is missing.
#
# License: MIT

set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# Print the failed assertion and stop
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ~/.config/mise links into the clone, so mise writes these inside it
for f in config.override.toml config.work.override.toml config.local.toml config.work.local.toml miserc.local.toml; do
  git -C "$repo" check-ignore -q "tilde/.config/mise/$f" || fail "not gitignored: tilde/.config/mise/$f"
done
[ -z "$(git -C "$repo" check-ignore tilde/.config/mise/config.toml)" ] || fail "tilde/.config/mise/config.toml is gitignored"

echo "override-env: all checks passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bin/lib/test-override-env`
Expected: `FAIL: not gitignored: tilde/.config/mise/config.override.toml`, exit 1.

- [ ] **Step 3: Add the ignore lines to `.gitignore`**

Insert after line 20:

```gitignore
# mise's machine-local files (overrides from the settings UI, local config):
# ~/.config/mise links here, so mise writes them inside the clone
tilde/.config/mise/config.override.toml
tilde/.config/mise/config.*.override.toml
tilde/.config/mise/config.local.toml
tilde/.config/mise/config.*.local.toml
tilde/.config/mise/miserc.local.toml
```

- [ ] **Step 4: Wire the self-check into `bin/lib/check`**

Insert after line 83 (`bash bin/lib/test-shell > /dev/null`):

```bash
# mise's override layer: the version floor, the gitignored local files and zsh/override-env.zsh under a temp HOME and MISE_CONFIG_DIR
bash bin/lib/test-override-env > /dev/null
```

`bin/lib/check` already lints the file through its `bin/lib/test-*` glob.

- [ ] **Step 5: Run it to verify it passes**

Run: `bash bin/lib/test-override-env && pnpm check`
Expected: `override-env: all checks passed`, then `pnpm check` exits 0.

- [ ] **Step 6: Commit**

```bash
git add .gitignore bin/lib/check bin/lib/test-override-env
git commit -m "Gitignore mise's machine-local config files"
```

---

### Task 2: Require mise 2026.11.5, and install mise and uv in CI

**Files:**
- Create: `setup/mise-floor.sh`
- Modify: `setup/misc.sh:138-139`
- Modify: `bin/lib/check:47`
- Modify: `.github/workflows/check.yml:33-37`
- Modify: `bin/lib/test-override-env`
- Modify: `setup/README.md:47`, `.claude/rules/ci.md`

**Interfaces:**
- Produces: `setup/mise-floor.sh`. No arguments. Reads `mise --version` from PATH. Exit 0 at or above the floor. Otherwise exit 1 with this on stderr: `mise 2026.11.5 or newer is required, found <version|none>. Upgrade mise, then run setup again.` The file holds the line `floor=2026.11.5`, which the self-check reads with `sed -n 's/^floor=//p'`. A6's `setup.sh` calls the same script.
- Produces: `mise` and `uv` on PATH in the `check` workflow. `~/.config/mise` is not linked there and mise installs no tools.

- [ ] **Step 1: Write the failing test**

Insert into `bin/lib/test-override-env`, above the final `echo`:

```bash
command -v mise > /dev/null || fail "mise is not installed"
bash "$repo/setup/mise-floor.sh" || fail "the installed mise is below the floor"
floor=$(sed -n 's/^floor=//p' "$repo/setup/mise-floor.sh")
grep -q "version: $floor\$" "$repo/.github/workflows/check.yml" || fail "check.yml does not pin mise to the floor ($floor)"

# setup/mise-floor.sh compares numerically (2026.9.30 is older than 2026.11.5)
mkdir -p "$tmp/fake"
for v in 2026.11.5:0 2026.11.6:0 2026.12.0:0 2027.1.0:0 2026.11.4:1 2026.9.30:1 2025.12.31:1; do
  printf '#!/bin/bash\necho "%s macos-arm64 (2026-11-08)"\n' "${v%:*}" > "$tmp/fake/mise"
  chmod +x "$tmp/fake/mise"
  rc=0
  out=$(PATH="$tmp/fake:/usr/bin:/bin" bash "$repo/setup/mise-floor.sh" 2>&1) || rc=$?
  [ "$rc" = "${v#*:}" ] || fail "mise-floor: ${v%:*} exited $rc"
  [ "$rc" = 0 ] || [[ $out == "mise 2026.11.5 or newer is required, found ${v%:*}."* ]] || fail "mise-floor message: $out"
done
rc=0
PATH=/usr/bin:/bin bash "$repo/setup/mise-floor.sh" 2> /dev/null || rc=$?
[ "$rc" = 1 ] || fail "mise-floor: passes without mise"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bin/lib/test-override-env`
Expected: `bash: .../setup/mise-floor.sh: No such file or directory`, then `FAIL: the installed mise is below the floor`.

- [ ] **Step 3: Create `setup/mise-floor.sh`**

Mode 755. Header in the style of `bin/lib/test-shell` (a one-line description, a `- Run it:` example, `---`, `License: MIT`). Body:

```bash
set -euo pipefail

floor=2026.11.5
found=$(mise --version 2> /dev/null | awk '{ print $1; exit }') || true
if [ -z "$found" ] || [ "$(printf '%s\n%s\n' "$floor" "$found" | sort -V | head -1)" != "$floor" ]; then
  echo "mise $floor or newer is required, found ${found:-none}. Upgrade mise, then run setup again." >&2
  exit 1
fi
```

`sort -V` is in macOS's `/usr/bin/sort` (checked: it orders `2026.9.30` before `2026.11.4`). The header says why the floor exists: the override file arrived in mise 2026.10.14 and the spec was verified on 2026.11.5.

- [ ] **Step 4: Call it from `setup/misc.sh`**

Insert as the first line inside `if command_exists mise; then` (line 138), before the `info "📦 Installing runtimes with mise…"` line:

```bash
  # The settings layer needs mise's override file; stop before installing with an older mise
  bash "$DOTFILES_DIR/setup/mise-floor.sh" || exit 1
```

A Mac with no mise keeps today's "mise not found" skip line.

- [ ] **Step 5: Keep CI's catalog test on plain Python in `bin/lib/check`**

Replace line 47, `if command -v mise > /dev/null; then`, with:

```bash
if command -v mise > /dev/null && mise where python > /dev/null 2>&1; then
```

Extend the comment above it: CI has mise but no mise-installed Python, and `mise exec python` would download one. Checked: `mise where python` exits 0 on this Mac and 1 under an empty `MISE_DATA_DIR`.

- [ ] **Step 6: Install mise and uv in `.github/workflows/check.yml`**

Look up the current release and its commit SHA for each action. Do not copy a SHA from anywhere else:

```bash
for r in jdx/mise-action astral-sh/setup-uv; do
  tag=$(gh api "repos/$r/releases/latest" --jq .tag_name)
  echo "$r $tag $(gh api "repos/$r/commits/$tag" --jq .sha)"
done
```

On 2026-11-09 the tags were `v5.2.7` and `v10.3.3`. Replace lines 33-34 (the "No mise here" comment) and keep the `setup-python` step:

```yaml
      # mise's python is not installed here, so bin/lib/check runs the catalog
      # test with plain python3, which must be 3.11+ for tomllib
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        with:
          python-version: '3.15'
      # The floor in setup/mise-floor.sh (bin/lib/test-override-env checks they
      # match). install: false, because the repo's global config is not linked here
      - uses: jdx/mise-action@<sha from the lookup> # <tag>
        with:
          version: 2026.11.5
          install: false
      # No lockfile to key a cache on until the settings package lands
      - uses: astral-sh/setup-uv@<sha from the lookup> # <tag>
        with:
          enable-cache: false
```

`version`, `install` and `enable-cache` are inputs in each action's `action.yml` (read on 2026-11-09).

- [ ] **Step 7: Update the docs this task makes stale**

- `setup/README.md:47`. After the sentence "The script links that config into `~/.config/mise` and runs `mise install` before touching npm." add: "It first runs [`mise-floor.sh`](mise-floor.sh) and stops when mise is older than 2026.11.5, the version the settings layer needs."
- `.claude/rules/ci.md`. Add one bullet: "`check.yml` installs mise at the floor in `setup/mise-floor.sh` and uv. Renovate does not bump the `version:` input: raise it with the floor (`bin/lib/test-override-env` fails when they differ)."

- [ ] **Step 8: Run the checks**

Run: `bash bin/lib/test-override-env && actionlint .github/workflows/check.yml && pnpm check`
Expected: `override-env: all checks passed`, no actionlint output, `pnpm check` exits 0.

- [ ] **Step 9: Commit, push, and confirm CI**

```bash
git add setup/mise-floor.sh setup/misc.sh setup/README.md bin/lib/check bin/lib/test-override-env .github/workflows/check.yml .claude/rules/ci.md
git commit -m "Require mise 2026.11.5 and install mise and uv in CI"
git push
gh run watch "$(gh run list --workflow check --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: the `check` run passes. This is the first run with mise on the runner.

---

### Task 3: The override cache for shells that never prompt

**Files:**
- Create: `zsh/override-env.zsh`
- Modify: `tilde/.zshenv` (append after line 24)
- Modify: `tilde/.zshrc` (insert after line 38, the `~/.zsh.local` line)
- Modify: `bin/lib/test-override-env`
- Modify: `.claude/rules/zsh.md:12`, `tilde/README.md:19,21`

**Interfaces:**
- Consumes: Task 2's block in the self-check, which has already failed the run when mise is missing or below the floor.
- Produces: `zsh/override-env.zsh`, sourced with no arguments. Reads `${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.override.toml`. Writes `$HOME/.cache/dotfiles/override-env.<override file path with every character outside A-Za-z0-9 as _>.zsh` (for the default config dir, `override-env._Users_<you>__config_mise_config_override_toml.zsh`), one `export KEY='value'` line per key in the override file's `[env]` table. Does nothing when `DOTFILES_NO_OVERRIDE_ENV` is non-empty or the override file is absent.
- Part B hook. The migration plan's `env` step needs only this from A1: it writes with `mise set --override KEY=VALUE` run from `$HOME` and never edits the cache. The next shell sees a newer override file and rebuilds the cache. To list keys already overridden it reads the `[env]` table of the override file at the path above. A key is a line matching `^[[:space:]]*"?([A-Za-z_][A-Za-z0-9_]*)"?[[:space:]]*=` between the `[env]` header and the next line that starts with `[`. `mise set` with no arguments prints the same keys with their source file.

- [ ] **Step 1: Write the failing test**

Insert into `bin/lib/test-override-env`, above the final `echo`:

```bash
# A mise that logs each call, so a fresh cache can be shown to start none
real=$(command -v mise)
mkdir -p "$tmp/bin" "$tmp/cfg" "$tmp/home" "$tmp/zd"
printf '#!/bin/bash\necho "$*" >> "%s/mise.log"\nexec "%s" "$@"\n' "$tmp" "$real" > "$tmp/bin/mise"
chmod +x "$tmp/bin/mise"
printf 'source %q\n' "$repo/tilde/.zshenv" > "$tmp/zd/.zshenv"
printf 'source "$DOTFILES/tilde/.zshrc"\n' > "$tmp/zd/.zshrc"
override="$tmp/cfg/config.override.toml"
cache="$tmp/home/.cache/dotfiles/override-env.${override//[^A-Za-z0-9]/_}.zsh"

# Run a command with nothing inherited but the temp HOME, mise config and ZDOTDIR
iso() { env -i HOME="$tmp/home" MISE_CONFIG_DIR="$tmp/cfg" ZDOTDIR="$tmp/zd" PATH="$tmp/bin:/usr/bin:/bin" "$@"; }
# val <name> [VAR=value]: the variable in a shell that never prompts, seeded with K=seed
val() { iso K=seed "${@:2}" zsh -c "print -r -- \"\${$1-unset}\"" 2> /dev/null; }
# How many times a shell started mise
calls() { [ -f "$tmp/mise.log" ] && wc -l < "$tmp/mise.log" | tr -d ' ' || echo 0; }
# The real mise against the temp config, from the temp HOME as the UI will run it
m() { (cd "$tmp/home" && iso "$real" "$@"); }

[ "$(val K)" = seed ] || fail "no override file: the seed is not kept"
[ ! -e "$cache" ] && [ "$(calls)" = 0 ] || fail "no override file: a cache was written or mise ran"

m set --override K=over "SP=a b 'q' \"d\"" > /dev/null
[ "$(val K)" = over ] || fail "override does not beat the seed"
[ "$(val SP)" = "a b 'q' \"d\"" ] || fail "a value with spaces and quotes is not kept: $(val SP)"
[ "$(calls)" = 1 ] || fail "stale cache: expected one mise run, saw $(calls)"
! grep -q "^export PATH=" "$cache" || fail "the cache holds keys the override file does not set"

: > "$tmp/mise.log"
[ "$(val K)" = over ] && [ "$(calls)" = 0 ] || fail "fresh cache: mise ran at shell startup"

[ "$(val K DOTFILES_NO_OVERRIDE_ENV=1)" = seed ] || fail "DOTFILES_NO_OVERRIDE_ENV does not skip the cache"

m set --override K=again > /dev/null
[ "$(val K)" = again ] && [ "$(calls)" = 1 ] || fail "a changed override file does not refresh the cache once"

# Another mise config dir under the same HOME gets its own cache
mkdir -p "$tmp/cfgB"
printf '[env]\nK = "other"\n' > "$tmp/cfgB/config.override.toml"
[ "$(val K MISE_CONFIG_DIR="$tmp/cfgB")" = other ] || fail "a second mise config dir: its override is not applied"
[ "$(val K)" = again ] || fail "a second mise config dir changed the first one's values"

# A broken override file keeps the last good values
cp "$tmp/cfg/config.override.toml" "$tmp/good.toml"
echo '[env' > "$tmp/cfg/config.override.toml"
[ "$(val K)" = again ] || fail "unreadable override file: last good value lost"
out=$(iso zsh -i -c : < /dev/null 2>&1)
[ "$(grep -c '^override-env: mise could not read ' <<< "$out")" = 1 ] || fail "unreadable override file, interactive: expected one warning, got: $out"
cp "$tmp/good.toml" "$tmp/cfg/config.override.toml"

m unset --override K > /dev/null
[ "$(val K)" = seed ] || fail "reset does not restore the seed"
[ "$(val SP)" = "a b 'q' \"d\"" ] || fail "reset of one key dropped another"

# Interactive shells: ~/.zsh.local (a seed) exports after .zshenv, and the override still wins
m set --override K=over > /dev/null
echo 'export K=local' > "$tmp/home/.zsh.local"
out=$(iso PATH="$tmp/bin:/opt/homebrew/bin:/usr/bin:/bin" zsh -i -c 'print -r -- $K' < /dev/null 2> /dev/null)
[ "$out" = over ] || fail "interactive shell: ~/.zsh.local beat the override ($out)"

# A new terminal window runs .zshenv before PATH has mise. With mise at none of
# the fallback paths either (HOME is the temp one, HOMEBREW_PREFIX an empty
# folder), a stale cache keeps its values: silently, or with one warning at a prompt
touch "$tmp/cfg/config.override.toml"
nomise() { iso K=seed PATH=/usr/bin:/bin HOMEBREW_PREFIX="$tmp/none" "$@"; }
out=$(nomise zsh -c 'print -r -- $K' 2>&1)
[ "$out" = over ] || fail "stale cache without mise: expected only the last good value, got: $out"
out=$(nomise zsh -i -c 'print -r -- $K' < /dev/null 2>&1)
[ "$(grep -c '^override-env: mise could not read ' <<< "$out")" = 1 ] || fail "stale cache without mise, interactive: expected one warning, got: $out"
[ "$(tail -1 <<< "$out")" = over ] || fail "stale cache without mise, interactive: last good value lost: $out"

# Resetting the last key empties the cache
m unset --override K SP > /dev/null
[ "$(val K)" = seed ] && ! grep -q '^export ' "$cache" || fail "resetting every key left exports in the cache"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bin/lib/test-override-env`
Expected: `FAIL: override does not beat the seed`.

- [ ] **Step 3: Create `zsh/override-env.zsh`**

The whole file. It ran against the test above in a scratch copy of the repo.

```zsh
# Values set with `mise set --override` live in mise's override file. mise
# applies them at the first prompt only (zsh/init.zsh), so shells that never
# prompt read this cache of them. mise runs only when the override file is newer
# than the cache. Sourced from tilde/.zshenv, and again from tilde/.zshrc because
# zsh/env.zsh and ~/.zsh.local (the seeds) export after .zshenv.
# shortcut: `mise env --dotenv` prints values raw, so a multi-line value keeps
# its first line only; switch to --json if a setting ever needs one.
() {
  # Lets the settings package read a seed without the override on top
  [[ -z ${DOTFILES_NO_OVERRIDE_ENV:-} ]] || return 0
  local override=${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.override.toml
  # One cache per override file, so another MISE_CONFIG_DIR never reads this one's values
  local cache=$HOME/.cache/dotfiles/override-env.${override//[^A-Za-z0-9]/_}.zsh
  [[ -f $override ]] || return 0
  if [[ ! $cache -nt $override ]]; then
    # .zshenv runs before .zprofile puts mise on PATH, so try where it installs
    local mise line out in_env=0
    for mise in ${commands[mise]:-} $HOME/.local/bin/mise ${HOMEBREW_PREFIX:-/opt/homebrew}/bin/mise; do
      [[ ! -x $mise ]] || break
    done
    local -a keys match mbegin mend
    for line in "${(@f)$(<$override)}"; do
      if [[ $line == \[* ]]; then
        [[ $line == '[env]'* ]] && in_env=1 || in_env=0
      elif (( in_env )) && [[ $line =~ '^[[:space:]]*"?([A-Za-z_][A-Za-z0-9_]*)"?[[:space:]]*=' ]]; then
        keys+=($match[1])
      fi
    done
    # -C $HOME: an untrusted mise.toml in the current directory must not fail the run
    if [[ -x $mise ]] && out=$("$mise" env --dotenv -C $HOME 2> /dev/null) && mkdir -p ${cache:h}; then
      for line in "${(@f)out}"; do
        if (( ${keys[(Ie)${line%%=*}]} )); then print -r -- "export ${line%%=*}=${(qq)${line#*=}}"; fi
      done >| $cache.$$ && command mv -f $cache.$$ $cache
    elif [[ -o interactive && -z ${_override_env_warned:-} ]]; then
      # Sourced twice per interactive shell; warn once
      typeset -g _override_env_warned=1
      print -u2 "override-env: mise could not read $override; keeping the last good values"
    fi
  fi
  [[ ! -r $cache ]] || source $cache
}
```

Keep the `if … fi` form inside the output loop. With `(( … )) && print`, a last line that is not an override key makes the loop return 1 and the `mv` never runs (found in the scratch run).

`mise env --dotenv` and the global `-C` flag are in `mise env --help`. `.prettierignore` needs no edit: its `*.zsh` line (line 8) already covers the file, and `bin/lib/test-conventions` checks every `zsh/*.zsh`. `bin/lib/check` already runs `zsh -n` on `zsh/*.zsh`.

Keep `command mv`. The second source runs after `zsh/aliases.zsh` has defined `alias mv='mv -iv'`, and a bare `mv` then prints `old -> new` to stdout on every refresh from `.zshrc` (found when the review fixes were run: the first source could not find mise, the second could).

- [ ] **Step 4: Source it from `tilde/.zshenv` and `tilde/.zshrc`**

Append to `tilde/.zshenv`:

```zsh

# Values set with `mise set --override` beat the exports above (zsh/override-env.zsh)
source "$DOTFILES/zsh/override-env.zsh"
```

Insert into `tilde/.zshrc` after line 38 (`[ -f ~/.zsh.local ] && source ~/.zsh.local`):

```zsh
# Again, because zsh/env.zsh and ~/.zsh.local exported since .zshenv
source $DOTFILES/zsh/override-env.zsh
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bash bin/lib/test-override-env && bash bin/lib/test-shell`
Expected: `override-env: all checks passed` and `shell: all checks passed`.

- [ ] **Step 6: Confirm the live shell is untouched**

Run: `ls ~/.config/mise/ && ls ~/.cache/dotfiles 2>&1`
Expected: `config.toml` only, and `No such file or directory`. No override file exists on this Mac yet, so the new file returns at its third line.

- [ ] **Step 7: Update the docs this task makes stale**

- `.claude/rules/zsh.md:12`. The load order ends "→ `~/.zsh.local`. `tilde/.zprofile` activates mise shims for GUI apps." Change that tail to: "→ `~/.zsh.local` → `override-env.zsh`. `tilde/.zprofile` activates mise shims for GUI apps." Add one bullet: "**Overrides** (`zsh/override-env.zsh`, sourced by `tilde/.zshenv` and last in `tilde/.zshrc`): exports of the keys in mise's `config.override.toml`, read from a cache under `~/.cache/dotfiles/` named after the override file's path. mise runs only when the override file is newer than the cache, so a fresh start runs no process. It is sourced twice because `env.zsh` and `~/.zsh.local` are seeds that export after `.zshenv`." Keep the file under 6000 bytes.
- `tilde/README.md:19`. Replace "Runs for every zsh. Exports `$DOTFILES`, the repo's location" with "Runs for every zsh. Exports `$DOTFILES`, the repo's location, then the values set with `mise set --override`".
- `tilde/README.md:21`. Replace "loads everything in [`zsh/`](../zsh/), then `~/.zsh.local` if it exists" with "loads everything in [`zsh/`](../zsh/), then `~/.zsh.local` if it exists, then the `mise set --override` values again so they win".

- [ ] **Step 8: Commit**

```bash
pnpm check
git add zsh/override-env.zsh tilde/.zshenv tilde/.zshrc tilde/README.md bin/lib/test-override-env .claude/rules/zsh.md
git commit -m "Apply mise override values in shells that never prompt"
```

---

### Task 4: Document seeds and overrides

**Files:**
- Modify: `README.md:185`, `README.md:284`
- Modify: `bin/upup:6-7`
- Modify: `.claude/rules/upup.md:20`
- Modify: `CLAUDE.md:59`

**Interfaces:**
- Consumes: the behaviour Tasks 1 to 3 shipped. No code changes.

The instructions at `README.md:258` and `README.md:276` ("Add it to `~/.zsh.local`", "add this to `~/.zsh.local`") stay. They are still correct, because exports remain the seed (spec D3). A2 rewrites them for the UI.

- [ ] **Step 1: Write the failing check**

Run:

```bash
grep -c 'mise set --override' README.md bin/upup CLAUDE.md .claude/rules/upup.md
```

Expected now: `0` for all four files.

- [ ] **Step 2: `README.md:185`, the `~/.zsh.local` section**

Current: "If this file exists, it's sourced near the end of `~/.zshrc` (after `zsh/init.zsh`), so its content can add to or override the existing aliases, settings, PATH, etc."

Add a second paragraph below it:

"An `export` here is a starting value. `mise set --override KEY=value`, run from your home directory, beats it in every new shell, and `mise unset --override KEY` hands the variable back to the export. Overrides are stored in `tilde/.config/mise/config.override.toml` inside the clone (`~/.config/mise` is a link to that folder), which git ignores."

A2 replaces this paragraph with one that names `dotfiles-settings`. Write it as a paragraph of its own so that edit stays a clean swap.

- [ ] **Step 3: `README.md:284`, undoing the CA roots opt-in**

Current ending: "and delete the line from `~/.zsh.local`. Removing the roots can break HTTPS connections to some websites."

Replace with: "and delete the line from `~/.zsh.local` (run `mise unset --override DOTFILES_TRIM_CA_ROOTS` too if you set it that way). Removing the roots can break HTTPS connections to some websites."

- [ ] **Step 4: `bin/upup:6-7`, the header**

Line 6 current: "Set `DOTFILES_MAC_PASSWORD_OP` in `~/.zsh.local` to a 1Password secret reference". Change "in `~/.zsh.local`" to "in `~/.zsh.local` (or with `mise set --override`)".

Line 7 current: "Set `DOTFILES_TRIM_CA_ROOTS=1` in `~/.zsh.local` to let it remove". Make the same change.

Each header line stays one line. tlrc rejects a wrapped line.

Run: `bin/help upup > /dev/null && echo ok`
Expected: `ok`.

- [ ] **Step 5: `.claude/rules/upup.md:20`**

Current start: "**CA roots**: with `DOTFILES_TRIM_CA_ROOTS` set in `~/.zsh.local`, `ca-roots trim` runs before `brew doctor`". Change "set in `~/.zsh.local`" to "set (in `~/.zsh.local`, or with `mise set --override`, which wins)".

- [ ] **Step 6: `CLAUDE.md:59`, machine-local config**

Current ending: "The one in-repo exception is `mole/*.local` (gitignored, kept next to the shared file it replaces); a re-clone loses it."

Replace with: "The in-repo exceptions are gitignored and lost on a re-clone: `mole/*.local` (kept next to the shared file it replaces) and mise's local files under `tilde/.config/mise/` (`config.override.toml`, `config.local.toml`, `miserc.local.toml`), which land in the clone because `~/.config/mise` is a link. A `mise set --override` value beats the same export in `~/.zsh.local` (`zsh/override-env.zsh`)."

Run: `wc -c CLAUDE.md && awk 'length($0) > 1000' CLAUDE.md | wc -l`
Expected: under 12000 bytes, and `0` long lines. The file is 10829 bytes before this edit.

- [ ] **Step 7: Run the checks**

Run: `grep -c 'mise set --override' README.md bin/upup CLAUDE.md .claude/rules/upup.md && pnpm check`
Expected: every count is 1 or more, and `pnpm check` exits 0.

- [ ] **Step 8: Commit**

```bash
git add README.md bin/upup CLAUDE.md .claude/rules/upup.md
git commit -m "Document that a mise override beats a ~/.zsh.local export"
```

---

## After the last task

Move this plan to `docs/superpowers/plans/completed/`. The spec stays open until every plan built on it is completed.
