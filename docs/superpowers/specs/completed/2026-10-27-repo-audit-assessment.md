# Repo audit, October 2026: assessment

Date: 2026-10-27. HEAD `688180a`, main, clean tree. macOS 27.0.1 (arm64), Claude Code 2.1.310, git 2.56.0, zsh from Homebrew.

Question: what in this repo is wrong, risky, stale or worth improving? Method: six read-only audits in parallel (the setup flow, `bin/`, the shell config, packages and CI, security and privacy, the user-facing docs), each reporting with file:line evidence, then the highest-impact claims re-run by hand before ranking. Every finding below is labelled **measured** (a command reproduced it), **read** (the defect is visible in the code and needs no run), or **guess** (plausible, with the command that would settle it). Nothing was changed.

The plans that act on this are `docs/superpowers/plans/2026-10-27-*.md`; each finding names the plan that owns it.

## Verdict

The guardrails hold. No secret is tracked or in history (gitleaks over 242 commits, plus targeted `git log -S` searches), CI and the required status check line up, every Brewfile package is live upstream, and the `.claude/` surface was audited and fixed separately the same day (`688180a`). The exposure is in what the interactive shell hands to agents and child processes, in a handful of setup and script paths that abort or lose data, and in docs that drifted. None of it is urgent in the sense of a live leak; three items (a token in every process, a permissive agent allowlist, and a `source` builtin that no longer works) are the ones to take first.

## Findings

Severity: **high** breaks a run, loses data, or is a credential exposure an agent can act on. **medium** is wrong on some path or a gap one more mistake away from mattering. **low** is hygiene or an opportunity.

### A. Agent shell and secrets (plan: `agent-shell-and-secrets-hardening`; A9 in `bin-script-fixes`, A11 in `setup-robustness`, A14 and A15 in `packages-ci-and-docs`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| A1 | high | `zsh/env.zsh:170-172` | `GITHUB_TOKEN` and `GIGET_AUTH` are exported from `gh auth token` into every interactive shell, Claude Code's Bash shells included; the token has `repo` and `workflow` scope and reaches every child process (npm lifecycle scripts, MCP servers, `curl`). | measured (40-char value present under `CLAUDECODE=1`) |
| A2 | high | `agents/claude-settings.json` | The tracked user-scope allowlist includes `Bash(curl:*)`, `Bash(gh api:*)`, `Bash(git add:*)` and bare `WebFetch`; `deny` holds only three `npm -g` rules. With A1, an agent can exfiltrate any readable file without a prompt. The live `~/.claude/settings.json` is identical. | read |
| A3 | high | `zsh/aliases.zsh:7` | `alias .=…` replaces the `source` builtin; `. file` prints a glyph and `pwd`'s usage and never sources. Agent shells inherit it. | measured |
| A4 | high | `zsh/init.zsh:39` | `zoxide init --cmd cd` stays on in agent shells, so `cd <missing>` jumps to a frecency match instead of failing (`cd /tmp && cd dotfiles` landed in the repo). | measured |
| A5 | high | `zsh/aliases.zsh:155-178` | The `git()` wrapper expands `$@` unquoted (empty args dropped: `--sq-quote "" "a b"` lost the empty one) and runs `yarn`, `pnpm install`, `npm install` or `bun install` after every `git clone`, executing the cloned repo's install scripts with A1's token in the environment. `git clone --depth 1 URL` also `cd`s into `1`. | measured |
| A6 | high | `tilde/.gitconfig:90-92` | `protocol.file.allow = always` reverses the git 2.38.1 hardening for CVE-2022-39253 (file:// submodules). Present since the initial commit. | read |
| A7 | high | `tilde/.curlrc:8,17` | Every `curl` on the machine, the Homebrew and Claude installers included, sends a fake MSIE 9 user agent and `referer ;auto`. | measured (httpbin echoed the agent) |
| A8 | medium | `vscode/User/{History,workspaceStorage,globalStorage}` | VS Code's user dir is a symlink into the repo, so about 9,700 state files sit inside the working tree, gitignored but readable by any agent and addable with `git add -f`. gitleaks found tokens from another repo's config in that history. | measured (file counts, ignore state) |
| A9 | medium | `bin/claude-config:57` | The `env` save filter keeps any `CLAUDE_CODE_*` name, so a `CLAUDE_CODE_OAUTH_TOKEN` in live settings would be committed to this public repo. | measured (sample through the same jq) |
| A10 | medium | `tilde/.ripgreprc:21`, `zsh/env.zsh:196` | `--field-match-separator=` glues path, line and text (`tilde/.gitconfig35  fsmonitor`); `--smart-case` changes agent results. The config applies in agent shells. | measured |
| A11 | medium | `setup.sh:148-163` | The sudo keep-alive runs for the whole setup, including the two `curl \| bash` installers and every npm, uv and dotnet install. | read |
| A12 | medium | `zsh/aliases.zsh:196-198` | The `CLAUDECODE` unalias list misses `.`, `cd`, `git`, `ld` (hides the linker) and `RIPGREP_CONFIG_PATH`. | measured (snapshot contents) |
| A13 | low | `tilde/.ssh/config:23-24` | `Host *` offers every 1Password key to every server; `IdentitiesOnly` is set only for github.com. | read |
| A14 | low | `.claude/settings.local.json` | Ignored only by the global `tilde/.gitignore:30`, not the repo's. | measured |
| A15 | low | policy | Claude Code (`DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`), VS Code (`telemetry.telemetryLevel`) and JFrog CLI (`JFROG_CLI_REPORT_USAGE`) have no opt-out here. Codex runs `approval_policy = "never"` in `workspace-write`. Decisions, not defects. | read; JFrog default is a guess |

### B. Setup flow (plan: `setup-robustness`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| B1 | high | `setup/symlinks.sh:157` | A second `[b]ackup` for the same path overwrites the first `.backup`; for a directory, `mv d d.backup` nests the new one inside the old. | measured (worker's `mv` test) |
| B2 | high | `setup/misc.sh:131,134` | `mise install \| indent` has no `\|\|` under `set -e`, so one failed tool download aborts setup before `symlinks.sh`; `brew.sh:38-44` tolerates the same class of failure on purpose. | read |
| B3 | medium | `setup/brew.sh:28`, `setup/misc.sh:436,438,491` | `brew update`, `dotnet tool update/install` and `pnpm install` are bare under `set -e`. | read |
| B4 | medium | `setup/brew.sh:8-9`, `setup/zsh.sh:16-17`, `setup/misc.sh:13-15` | Unguarded `$(tput …)` aborts each script when `TERM` is unset or `dumb`; `setup.sh:78` and `dash.sh:25` guard it. | measured (`env -u TERM` exited 2) |
| B5 | medium | `setup/misc.sh:42-49` | `xcode-select --install &> /dev/null` exits non-zero headless and kills the run silently; a cancelled dialog loops forever. | read |
| B6 | medium | `setup/macos.sh:108,497-504,528` | TextEdit, Preview, QuickTime and helpviewer writes land in the flat plist, which `defaults read` no longer resolves on macOS 27 (the apps are sandboxed). Whether the apps honour the values is unknown. | measured (`plutil` vs `defaults read`); effect is a guess |
| B7 | low | `setup/misc.sh:461-464` | `exit 0` when npm is missing also skips the Claude restore and catalog at :503-511. | read |
| B8 | low | `setup/misc.sh:93-94,116-117` | `ln -sfn` replaces `~/.config/gh` or `~/.config/mise` whenever either is any symlink, around `symlink_file`'s never-silently-overwrite rule. | read |
| B9 | low | `setup/symlinks.sh:398-399` | `ln -f` overwrites the Firefox `userContent.css` and `userChrome.css` without a prompt. | read |
| B10 | low | `setup/symlinks.sh:481` | `symlinks.sh` never evals `brew shellenv`, so on a fresh Mac the bat cache rebuild is skipped silently. | read |
| B11 | low | `firefox/lib/get-firefox-dev-path:24` | The `profiles.ini` fallback joins `$profile_dir/$profile_path` where `Path=` already starts with `Profiles/`, so it can never match. | read |
| B12 | low | `setup/macos.sh:239,542-548` | `QLEnableTextSelection` and the `messageshelper` keys are probably dead on current macOS. | guess |
| B13 | low | `setup/zsh.sh:38-40`, `setup/misc.sh:36-39` | `sudo echo` repeats the keep-alive `setup.sh` already holds. | read |
| B14 | low | live `~/.npmrc` | Lacks `min-release-age=7`, which `misc.sh:481` sets; something rewrote the file after the last setup. | measured |

### C. `bin/` scripts (plan: `bin-script-fixes`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| C1 | medium | `bin/claude-config:93,100,116` | `jq … \|\| true` in `known_marketplaces`, `installed_plugins` and the `disabled` lookup: an unparsable `installed_plugins.json` makes `save` replace the tracked plugin list with its header, exit 0, no warning. `upup` runs this on every update. | measured (real script, scratch dirs: 3 entries became 0) |
| C2 | medium | `bin/lib/test-upup:22`, `bin/upup:322` | The self-check never overrides `HOME`, so `pnpm check` runs upup's `rm` of `~/.claude/skills/reverse-engineer-anything` against the real home when that path is a symlink. | read |
| C3 | medium | `bin/serve:20` | `ruby -run -e httpd` needs webrick, gone from Ruby since 3.0 (4.0.9 installed). | measured |
| C4 | medium | `bin/git-find:19` | `-- "**/$1"` misses top-level files (`setup.sh`: 0 vs 5 commits) and crashes with no argument. | measured |
| C5 | medium | `bin/brewpick:3-4`, `bin/nnn:10-11` | `help brewpick` and `help nnn` exit 5: a wrapped header line is not a valid tldr page. `test-conventions` only checks that line 2 starts with `#`. | measured |
| C6 | medium | `bin/hindsight-memory:158,243` | Rollback and `uninstall` run the vendor `uninstall all` (every detected agent) where `init` installs only `claude-code codex`. | read |
| C7 | low | `bin/radio` | Dead: execs `mpv`, which is neither installed nor in the Brewfile; not in `docs/README.md`. | measured |
| C8 | low | `bin/upup:201,221`, `bin/CLAUDE.md` | The mise-WARN notice recommends `mise prune`; the rustup-shim notice says not to run it; `bin/CLAUDE.md` matches neither. Line 221 hard-codes `~/.local/share/mise` where :206 honours `MISE_DATA_DIR`. | read |
| C9 | low | `bin/upup:109,123-126` | The macOS step prints `changed` before installing, so a failed install shows both `changed` and `fail`. | read |
| C10 | low | `bin/lib/get-tldr-md:65` | Every `help <script>` leaves a `tldr-XXXX` dir in `$TMPDIR` (78 found); `help lib` crashes on a directory. | measured |
| C11 | low | `bin/git-tidy:19` | `grep -vE '^\*\|master\|main'` spares any branch whose name contains `main`; a worktree-checked-out branch is listed as `+ name`. | read; worktree case is a guess |
| C12 | low | `bin/pull:49-51` | Multi-line `$file` when several `package.json` changed; `ORIG_HEAD` may be stale after a no-op pull. | read |
| C13 | low | `bin/claude-config:252`, `bin/copy-ssh:17` | `${1/#$HOME/~}` tilde-expands the replacement under bash 5 (a no-op there); bash 3.2 prints `~`. | measured |
| C14 | low | `bin/claude-config:167,219` | A failed `jq` leaves `agents/*.tmp` in the repo; no ignore rule. | read |
| C15 | low | `agents/catalog/build_catalog.py:18,210-221` | Reads `~/.claude` and ignores `CLAUDE_CONFIG_DIR`; a `by_name` built at 210-212 is overwritten at 221. | read |
| C16 | low | `docs/README.md` | Missing from the index: `claude-config`, `claude-catalog`, `ds-delete`, `dust`, `line`, `git-setup`, `npmplease`, `radio`. | measured |
| C17 | low | `bin/upup:323-324` | `capture` merges stderr into `$out`, so any stderr line from `rea setup --format json` breaks the jq parse and the `\|\| echo 0` fallback reports `ok`. | guess |

### D. Shell startup and config (plan: `shell-startup`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| D1 | medium | `zsh/completion.zsh:21-22` | `typeset -i` turns `027` into `27` and `[ 027 != 27 ]` compares strings, so days 001-099 always run a full `compinit -i` (346 ms vs 8 ms). `date +'%j' -r` is not valid BSD date, so the `stat` fallback always runs. | measured |
| D2 | medium | `zsh/init.zsh:8` | `source_brew_plugin` calls `brew --prefix` twice per plugin, 73-91 ms per shell. | measured |
| D3 | medium | `zsh/path.zsh:3-5` | `PATH="$(getconf PATH)"` discards what `.zprofile` built; SnippetsLab's `lab` is missing from every interactive shell, and a nested `zsh` loses an activated venv or `mise exec` PATH. | measured (`whence -p lab` empty) |
| D4 | medium | `zsh/env.zsh:176` | `git config --global user.name` ignores `[include]`, so `NPM_CONFIG_INIT_AUTHOR_NAME` is always empty (17 ms per shell). | measured |
| D5 | medium | `tilde/.gitconfig:25` with `zsh/env.zsh:18-21` | `core.editor = cot --wait` beats `EDITOR=nano` over SSH, so `git commit` waits on a GUI editor. | read (git's documented order) |
| D6 | medium | `zsh/init.zsh:28` | `fast-theme … --quiet` re-applies and rewrites the theme cache on every shell, 21-28 ms. | measured |
| D7 | medium | startup total | 0.37-0.47 s interactive; `init.zsh` 262-304 ms of it. A1, D2, D4 and D6 together are about 150 ms. | measured, 5 runs |
| D8 | low | `zsh/aliases.zsh:73,46` | `alias ld=lazydocker` hides the linker; `alias where=which` replaces a zsh builtin. | read |
| D9 | low | `zsh/fzf.zsh:71` | `source <(fzf --zsh)` in a non-tty interactive shell prints `can't change option: zle` twice. | measured |
| D10 | low | `zsh/env.zsh:10` | `export TERM=xterm-256color` overrides Ghostty's `xterm-ghostty`. | read |
| D11 | low | `zsh/aliases.zsh:76` | lazygit's config is reached only through the `lg` alias; plain `lazygit` runs unconfigured. | measured (`~/.config/lazygit` absent) |
| D12 | low | `tilde/.zprofile:5` | `brew shellenv` is unguarded; a Mac without Homebrew errors on every login shell. | read |
| D13 | low | `zsh/fzf.zsh:63-64` | The `llt` completion branch is dead (no such alias or command). | measured |
| D14 | low | `zsh/env.zsh:167` | `AZD_BICEP_TOOL_PATH` is exported whether or not the file exists. | guess on azd's behaviour |
| D15 | low | `tilde/.gitconfig:41` | `help.autoCorrect = 1` runs git's guess after 0.1 s, in agent shells too. | read |
| D16 | low | `tilde/.config/btop/btop.conf`, `tilde/.tlrc.toml:3` | btop 1.4.8 may rewrite the 1.4.7 config on exit; `dir = ".tlrc"` is relative and may download into the cwd. | guess |

### E. Packages, CI and licensing (plan: `packages-ci-and-docs`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| E1 | medium | `setup/Brewfile:77` | `microsoft/foundry/devpack` is listed but not installed, so `brew bundle check` fails. | measured |
| E2 | medium | `ql-plugins/` | Both bundles are x86_64-only; `qlmanage -m plugins` lists neither on this arm64 Mac. No license or provenance; redistributed under the repo's MIT `LICENSE`. | measured |
| E3 | low | `setup/Brewfile:58` | `jesseduffield/lazydocker` has no `tap` line, against the header's rule. | read |
| E4 | low | `setup/Brewfile` | Installed on request but unlisted: `git-filter-repo`, `komac`, `llama.cpp`, `jrmatherly/ai-kb/{aikb,ai-kb-lite}`, casks `gcloud-cli`, `signal`, and ten VS Code extensions. | measured |
| E5 | low | `setup/Brewfile:26-27,228-234,247` | Font casks sit under "GUI apps"; the "Fonts" section holds only the `manual` line. | read |
| E6 | low | `.github/workflows/check.yml:20` | `macos-latest` unpinned, no `timeout-minutes`, `brew install` uncached, no `actionlint` although it is in the Brewfile. | read |
| E7 | low | `.gitignore:1`, `.prettierignore:1` | `Brewfile.lock.json` is never written by current `brew bundle`; `vscode/User/prompts/` has never existed. | measured |
| E8 | low | `LICENSE` | No note that `icons/`, `ql-plugins/` and the Squirrelsong themes stay under their owners' terms. | read |
| E9 | low | `tilde/.config/mise/config.toml:9-11` | The Node comment expires when 26 becomes LTS (days away as of this audit). | measured (nodejs.org index) |

### F. Docs (plan: `packages-ci-and-docs`)

| Id | Sev | Where | Finding | Label |
| --- | --- | --- | --- | --- |
| F1 | low | `README.md:164-173` | The "Make it yours" table omits `package.json` (author) and `setup/bootstrap-runtime.archify.json` (clone URL). | measured (`git grep`) |
| F2 | low | `setup/README.md:65` | Reads as if REA's MCP registration survives a missing Ghidra formula; `misc.sh:345-349` skips it. | read |
| F3 | low | `docs/privacy.md:27` | Says four `hindsight-api` builds in the uv cache; there are five. | measured |
| F4 | low | `CLAUDE.md`, Renovate bullet | Omits the github-actions and pnpm `packageManager` managers Renovate also covers. | measured (dashboard issue) |

## Out of scope and unverified

- The `curl:*` rule's behaviour in auto mode rests on the permissions docs, not a live test.
- B6, B12, C17, D14 and D16 are guesses with the settling command named in their rows.
- The GUI apps' in-app telemetry (Warp, Raycast, Comet) and the vendor docs for Docker, Netlify, Wrangler, Sentry, Serena, Scrapling and Hindsight were not checked.
- Side effects of the audit itself: `dotnet tool list` installed an untrusted ASP.NET dev certificate (`dotnet dev-certs https --clean` removes it); `tldr --config-path` created an empty `~/Library/Application Support/tlrc`.
