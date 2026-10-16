# Mole (`mo`)

Mole is a Mac cleaner and maintenance tool from the Brewfile (`brew "mole"`). This page says what each command does on a Mac set up from this repo, which of them to use, and how its config is tracked. It was checked against Mole 1.60.0. Source citations are relative to the install, `$(brew --prefix mole)/libexec`.

## Summary

- `mo clean` and `mo optimize` are safe for this setup with the tracked whitelist. Mole leaves alone what the setup depends on: mise installs, uv tools (Serena, Scrapling), `~/.claude`, `~/.claude.json`, Claude plugin caches, Scrapling's Playwright Chromium, iCloud and Mail.
- Run every destructive command from a terminal, never from an agent shell. Without a TTY, `mo clean` and `mo optimize` start deleting without asking.
- Run `mo purge` interactively only. Its git-tracked protection can't help a project that isn't a git repo.
- Skip `mo touchid`, `mo completion` and `mo update`. The setup already covers each of them, and `mo completion` breaks the `~/.zshrc` symlink.
- Mole's space estimate leaves out the largest caches, such as Go's build cache and Docker or OrbStack data.

## What each command does

| Command | What it does | Verdict |
| --- | --- | --- |
| `mo clean` | Deletes caches, logs, crash reports, Trash, old app versions and leftovers from uninstalled apps. Deletion is permanent `rm -rf` through `safe_remove` (`lib/core/file_ops.sh`), with no undo. | Use, with the whitelist below. |
| `mo optimize` | Runs 19 maintenance tasks (`lib/optimize/catalog.sh`), listed after this table. | Use. |
| `mo purge` | Deletes project artifacts under project roots such as `~/dev`. It matches 34 folder names (`lib/clean/purge_shared.sh`), including `node_modules`, `.venv`, `build`, `dist`, `target`, `.next`, `obj`, `bin` (.NET projects only) and `vendor` (Composer projects only). | Interactive only. Never with `--yes` from a script. |
| `mo installer` | Finds `.dmg`, `.pkg`, `.iso`, `.xip` and installer zips in Downloads, Desktop, Documents, Homebrew's cache, Mail and Telegram. | Fine. |
| `mo uninstall` | Moves `.app` bundles and their leftovers to Trash (`bin/uninstall.sh`). Casks go through `brew uninstall --cask --zap` (`lib/uninstall/brew.sh`). | Fine for GUI apps. For a cask, also delete its line in `setup/Brewfile`, or the next `setup.sh` reinstalls it. Formulae, mise and uv tools are out of scope. |
| `mo analyze` | Interactive disk explorer. It moves items to Trash after you confirm. | Use it to find what clean doesn't cover. |
| `mo status` | Read-only live dashboard. It prints JSON when piped. | Use freely. |
| `mo history` | Reads `~/Library/Logs/mole/operations.log`. | Use after a run. |
| `mo touchid` | Writes `pam_tid.so` to `/etc/pam.d/sudo_local`. | Skip. `setup.sh` writes the same line, and Mole reports "already enabled" (`bin/touchid.sh`). |
| `mo completion` | Appends an `eval` line to `~/.zshrc` through a temp file and `mv` (`bin/completion.sh`). | Skip. `mv` onto a symlink replaces the link with a regular file, so edits would stop reaching `tilde/.zshrc`. Homebrew's `share/zsh/site-functions/_mole` already completes `mo`. |
| `mo update` | For a Homebrew install, runs `brew update` and `brew upgrade mole` (`lib/core/common.sh`). | Skip. `upup` already upgrades Homebrew. |

The optimize tasks, by effect:

- **Cache refresh.** QuickLook and icon caches. Also flushes DNS (sudo) and, only when probes show a problem, routes and ARP (sudo). Both network tasks are skipped while a VPN is active.
- **Database upkeep.** SQLite `VACUUM` on the Mail, Messages and Safari databases. Skipped while those apps run or when a database is over 100 MB.
- **Deletes history.** Saved app states older than 30 days. Notification records older than 30 days. Usage data (`knowledgeC.db`) older than 90 days. The quarantine "downloaded from" history.
- **Repairs.**
  - Deletes preference and shared-file-list files that fail `plutil -lint`.
  - Runs `sudo diskutil resetUserPermissions` only when your home folders are not writable (`lib/optimize/tasks.sh`).
  - Runs `sudo mdutil -E /`, a full Spotlight reindex, only when two search probes are slow and the Mac is on AC power.
- **Settings writes.**
  - `DSDontWriteNetworkStores` and `DSDontWriteUSBStores`. `setup/macos.sh` already sets both.
  - Removes legacy App Nap and disk-image overrides.
  - Prunes Spotlight rules for removed apps.
- **Report-only.** Login items and LaunchAgents.
- **Off or unavailable.** Disk verify (`diskutil verifyVolume /`) runs only with `MOLE_ENABLE_DISK_VERIFY=1`. Periodic maintenance needs macOS's `periodic` scripts, which macOS 26 removed (`lib/optimize/tasks.sh`).
- **Never touched.** Swap, Time Machine snapshots and power settings.

## What `mo clean` touches in this toolchain

A dry-run writes its full file list to `~/.config/mole/clean-list.txt`.

### Cleared but rebuilt on demand

These are safe to clear. Expect slower first runs afterwards.

- **npm.** Runs `npm cache clean --force`. It would also delete every entry under `~/.npm/_npx` (`clean_dev_npm`, `lib/clean/dev.sh`), but the tracked whitelist protects that folder: Claude Code plugin MCP servers such as chrome-devtools launch through `npx`, and a clean that runs while a session is live can leave an entry with its `package.json` gone. npx then treats it as installed and fails with ENOENT until the entry is removed by hand (`rm -rf ~/.npm/_npx/<hash>`).
- **pnpm.** Runs `pnpm store prune`, which removes unreferenced packages only. Skipped while pnpm runs. Also sweeps `~/Library/Caches/pnpm`.
- **mise.** Runs `mise cache clear` on `~/Library/Caches/mise`. Installs under `~/.local/share/mise/installs` are report-only (`lib/clean/user.sh`).
- **uv.** Runs `uv cache prune`, which removes only dangling entries. Nothing in `lib/clean` references `~/.local/share/uv/tools`.
- **Go.**
  - Runs `go clean -cache` on `~/Library/Caches/go-build`, which can grow past 100 GB.
  - Runs `go clean -modcache`, which empties `~/go/pkg/mod`. It's skipped while `go` or `gopls` runs. The tracked whitelist protects it permanently.
- **Lint and editor tooling.** `gopls`, `golangci-lint`, `typescript`, `node-gyp` and `pre-commit` caches.
- **Homebrew.**
  - Runs `brew cleanup --prune=30`, at most weekly (`lib/clean/brew.sh`).
  - The generic `~/Library/Caches/*` sweep also removes `~/Library/Caches/Homebrew`.
  - Whitelisting that folder would also turn off `brew cleanup` (`lib/clean/brew.sh`). Leave it alone.
- **Claude Code.**
  - Deletes old versions in `~/.local/share/claude/versions`. It keeps the active one plus one previous (`MOLE_AI_AGENTS_KEEP`, default 1).
  - Sweeps `~/Library/Caches/claude-cli-nodejs`.
  - Leaves `~/.claude`, `~/.claude.json` and the plugin cache alone (`lib/clean/dev.sh`).
- **VS Code.**
  - Clears logs, `Cache`, `CachedData`, `CachedExtensionVSIXs` and `WebStorage/*/CacheStorage`.
  - Removes extension folders superseded by a newer installed version.
  - Never touches `workspaceStorage`, `globalStorage`, or the symlinked `User/` folder.
- **Browsers.** Removes Chrome, Comet and Firefox caches only, and only while each browser is closed. Also removes old Chrome framework versions. Leaves cookies, history and profiles alone. `firefox/user.js` is untouched.
- **Other apps.**
  - Obsidian, Ghostty, Warp and Electron apps lose only their caches.
  - The repo-owned configs (`obsidian/`, `tilde/.config/*`) are not in any target.
- **Logs.**
  - Deletes everything in `~/Library/Logs`, with no age limit.
  - That includes crash reports in `~/Library/Logs/DiagnosticReports` (`lib/clean/user.sh`). Save any you still need first.
  - `private/setup-logs/` lives in the repo and is unaffected.
- **Trash.** Emptied. This needs Full Disk Access for the terminal app (`lib/clean/user.sh`). Otherwise it's skipped.

### Protected

- **Playwright Chromium.** `~/Library/Caches/ms-playwright*` holds Scrapling's Chromium. It's hard-protected (`lib/core/app_protection.sh`) and also in the whitelist.
- **Docker and OrbStack.** Report-only. Only `~/.docker/buildx/cache` is deleted.
- **Apple and app data.** iCloud (`Mobile Documents`), `~/Library/Mail`, 1Password, keychains, SSH and GPG paths.
- **Dotfolders.** `.codegraph/`, `.serena/`, `.claude/` and `private/` match no clean or purge target.
- **Tools without an app bundle.** Serena, CodeGraph and REA are safe. The leftovers step only looks at reverse-DNS names (`com.*`, `org.*`, `net.*`, `io.*`) in `~/Library/Caches` and `~/Library/Logs` (`lib/clean/apps.sh`).
- **tldr pages.** `tlrc` caches in `~/.tlrc` (`tilde/.tlrc.toml`), outside every target.

### One side effect

`mo clean` kills orphaned `playwright_chromiumdev_profile` Chromium processes, meaning parent PID 1 and running over an hour. It also deletes stale automation profiles in `$TMPDIR` older than 2 hours (`lib/clean/dev.sh`). A browser left running for hours by an MCP session can disappear.

## Configuration

Mole reads two config files at fixed paths, `~/.config/mole/whitelist` and `~/.config/mole/whitelist_optimize` (`lib/manage/whitelist.sh`, `lib/core/base.sh`). It also writes `clean-list.txt` and `purge_paths` into that folder, so the folder itself stays machine-local and `setup/symlinks.sh` links the two files alone.

| Repo file | Linked to | Tracked |
| --- | --- | --- |
| `mole/whitelist` | `~/.config/mole/whitelist` | Yes, the shared default |
| `mole/whitelist_optimize` | `~/.config/mole/whitelist_optimize` | Yes, the shared default |
| `mole/whitelist.local` | `~/.config/mole/whitelist`, in place of the shared file | No, gitignored |
| `mole/whitelist_optimize.local` | `~/.config/mole/whitelist_optimize`, in place of the shared file | No, gitignored |

A `.local` file replaces the shared one; nothing is merged. Start one as a copy of the shared file and add the Mac's own lines. After adding or removing a `.local`, run `setup/symlinks.sh` again. It switches the link without a prompt. Any other file or link already at the destination gets the usual skip/overwrite/backup prompt, except a dangling link, which is replaced.

Edit the files in the repo. Mole's own editors (`mo clean --whitelist`, `mo optimize --whitelist`) rewrite the file through the link, which drops its comments.

### Clean whitelist

How the file works:

- Once it exists, it replaces Mole's 14 built-in optional patterns (`DEFAULT_WHITELIST_PATTERNS`, `lib/core/base.sh`).
- Seven hard-coded safety entries (Spotlight, FontRegistry, CloudKit and others) always merge back in (`lib/core/base.sh`).
- One absolute path or glob per line. `~`, `$HOME` and `${HOME}` are expanded. `#` starts a comment only at the start of a line.
- `*` also matches `/`.
- `mo purge` reads this file too (`bin/purge.sh`).

The shared `mole/whitelist` keeps four of the optional defaults (Playwright, iCloud, Finder's cache and `FINDER_METADATA`) and adds the Go module cache, `~/go/pkg/mod/*`, since every Go repo needs its sources offline, and the npx cache, `~/.npm/_npx/*`, which Claude Code plugin MCP servers run from (see npm above). A dry-run with it reports "10 core + 2 custom patterns active", "Go module cache · would skip (whitelist)" and "npm cache · would skip (whitelist)". That last line is Mole's parent rule (`is_path_whitelisted`, `lib/core/app_protection.sh`): a pattern under `~/.npm` also protects `~/.npm` itself, so the `npm cache clean --force` step is skipped. The "npm cache directory" (`_cacache`) and "npm logs" sweeps still run, so the whitelist costs only the npx entries themselves.

The defaults left out cover Gradle, Ollama, Surge, R, JetBrains and tealdeer.

- R's `renv` cache is also a hard safety entry, so it stays protected regardless.
- Mole never targets `~/.ollama` outside its cache.
- tealdeer isn't used here (`tlrc` is).
- Add `~/.gradle/caches/*` and `~/.gradle/daemon/*` to a `.local` if a Mac builds with Gradle. The Brewfile's Java and Gradle VS Code extensions can create `~/.gradle`.

To keep Trash, add `~/.Trash` to a `.local`, or set `MOLE_SKIP_TRASH_CLEANUP=1` for one run.

### Optimize whitelist

One task id per line, exact match only. The shared `mole/whitelist_optimize` holds only comments, so every task runs (`DEFAULT_OPTIMIZE_WHITELIST_PATTERNS` is empty anyway).

Two tasks delete history:

- `coreduet_cleanup` drops usage-data rows older than 90 days.
- `quarantine_cleanup` empties the "downloaded from the internet" history.

Both deletions favor privacy, so they stay on. To keep that history on one Mac, put either id in `mole/whitelist_optimize.local`. `mo optimize --dry-run` then shows "Skipped (whitelisted)" for it.

### Purge scan roots

The first `mo purge` run writes `~/.config/mole/purge_paths` from auto-discovery. It isn't tracked. With every repo under `~/dev`, it should list `~/dev`. Scans go six levels deep (`lib/clean/project.sh`).

Purge protects an artifact folder if any of these holds:

- git tracks a file in it
- it contains a nested `.git`
- it contains a `*-keypair.json` file
- it changed in the last 7 days

The repo's `bin/` is a target name, but git tracks it, so it's safe.

## Hazards

1. **Agent shells delete without asking.**
   - In a non-TTY shell, `mo clean` prints "User-level cleanup will proceed automatically" and deletes (`bin/clean.sh`).
   - Only `--dry-run` previews.
   - `mo optimize` runs its tasks the same way.
   - Ask an agent for dry-runs only. Run real cleanups yourself in a terminal.
2. **Purge can't protect a project that isn't a git repo.**
   - Electron and other build tools can keep source files (icons, entitlements) in a `build/` folder.
   - In a project without git, the git-tracked protection can't apply, and purge lists the folder.
   - A non-TTY `mo purge --yes` selects every non-recent row and deletes with no prompt (`lib/clean/project.sh`).
   - Before purging, look for any `build/`, `dist/` or `bin/` folder in a non-git project. Protect it with a line in `mole/whitelist.local`, or put the project under git.
3. **Big caches run under a 20-second limit.**
   - Mole runs commands like `go clean -cache` with a 20 s timeout (`MOLE_TIMEOUT_PKG_CLEANUP_SEC`, `lib/core/timeouts.sh`).
   - On timeout it prints "stopped (timed out)" and moves on. Go may have deleted part of the cache by then (`lib/clean/dev.sh`).
   - Run `go clean -cache` yourself, or raise the timeout for one run. Raising it applies to every owner command, `brew cleanup` included.
4. **The space estimate undercounts.**
   - Caches cleaned through their owner tool (npm, pnpm, uv, Go, mise, bun, pip) show "would clean" with no size.
   - Docker and OrbStack show as "review" rows.
   - Check the big ones with `du` before trusting the total.
5. **Memory pressure is out of scope.** `mo optimize` diagnostics report swap and busy processes, but no task frees memory. Restart the process that holds it.
6. **First-run prompts and network use.**
   - The first `mo clean` can trigger macOS privacy (TCC) dialogs (`lib/clean/caches.sh`).
   - Bare `mo` (the menu) checks api.github.com for updates (`mole`, `lib/manage/update.sh`), with no opt-out. The subcommands below don't call it.

## Routine

Run these in a terminal, not with `sudo`. Mole asks for admin rights, with Touch ID, only when a step needs them.

### Once on each Mac

`setup/symlinks.sh` (run by `setup.sh`) links the whitelists. For a Mac that needs its own lines, create the `.local` first:

```bash
cp mole/whitelist mole/whitelist.local # then add this Mac's lines
./setup/symlinks.sh
```

Then the largest caches Mole won't fully take, where present:

```bash
du -sh ~/Library/Caches/go-build
go clean -cache
docker system df     # what Docker or OrbStack holds
docker builder prune # build cache only; asks first
docker image prune   # dangling images only; asks first
```

`docker image prune -a` would also delete every image no container uses. Use it only if re-pulling is acceptable.

### Monthly cleanup

Quit Chrome, Comet, Firefox, Safari, Mail and Messages first, because Mole skips the caches and databases of running apps.

```bash
sudo -v && mo clean --dry-run # preview, including the System section
less ~/.config/mole/clean-list.txt
mo clean

mo optimize --dry-run
mo optimize

mo purge --dry-run # preview candidates
mo purge           # interactive: deselect anything to keep

mo installer --dry-run && mo installer
mo history # what was removed
```

If clean reports the Go build cache as "stopped (timed out)", give owner commands more time:

```bash
MOLE_TIMEOUT_PKG_CLEANUP_SEC=900 mo clean
```

### Ad hoc

```bash
mo analyze                 # find big folders clean doesn't cover
mo analyze /private/tmp    # review temp files
mo status                  # live health; `mo status --json | jq .health_score`
mo clean --dry-run --debug # explain why an item was skipped
```

### Never

- `sudo mo ...`. Mole refuses to run as root (`bin/clean.sh`).
- `mo clean`, `mo optimize` or `mo purge --yes` without `--dry-run` from an agent shell, script or cron job.
- `mo completion`, `mo touchid` or `mo update`, for the reasons in the command table.
- `MO_NO_OPLOG=1` on a real clean or purge. Nothing else records what they delete.

## Logs and recovery

Clean and purge delete permanently. There is no undo.

- `~/Library/Logs/mole/operations.log` is the only record of what clean and purge removed. It rotates at 5 MB. Review it with `mo history` or `mo history --json`.
- `~/Library/Logs/mole/deletions.log` covers uninstall and installer only. It's written by `mole_delete`, which only `lib/uninstall/batch.sh` and `bin/installer.sh` call.
- `MOLE_DELETE_MODE=trash` affects that same helper only. It has no effect on clean or purge (`lib/core/file_ops.sh`). Uninstall already defaults to Trash.
