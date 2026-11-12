# Updating

```shell
sysup
```

[`sysup`](../bin/sysup) is the routine update command, and it works from any directory. It prints one status line per step (green ✔ up to date, cyan ↻ changed with what changed, yellow ● a notice such as a release held back, red ✖ a failed step with the command to rerun) and ends with a summary: a `Done in <time> · <n> changed · …` headline, then what changed, notices and failures in aligned columns, the actions you still have to take (restart Claude Code after plugin updates, review the tracked config, open a new terminal) under a highlighted `▶ ACTION NEEDED` banner, and clickable links to the rebuilt catalog and the log (shown as `~/…` paths). A list such as the upgraded packages or mise tools, the versions `mise prune` removed or the plugins updated prints as a two-column table under its step, and long lines wrap under the detail column. Each run's full tool output goes to `logs/sysup-<timestamp>.log` (git-ignored); only a step that changed something or failed shows its output on screen. On a terminal, the step in progress shows as a `…` line, and a step that took 10 seconds or more names its time. It:

- pulls the latest dotfiles (`git pull` in the clone)
- installs macOS software updates (a macOS update asks for your login password: see [below](#macos-update-password-from-1password-optional)); one that needs a restart, such as a new macOS version, is only downloaded, and the summary tells you to install it from System Settings → General → Software Update → Restart Now or with `sudo softwareupdate -ia --restart`, since a plain restart doesn't install it
- updates mise itself (`mise self-update`)
- upgrades the formulae and casks in [`30-packages.toml`](../tilde/.config/mise/conf.d/30-packages.toml) and the [modules](modules.md) that are on, VS Code included, without asking for confirmation (`mise bootstrap packages upgrade --yes`; the pairs whose installed version moved go to the screen). VS Code updates its own extensions
- lists any declared package that is still not installed
- reports, as one notice, the formulae and casks installed on this Mac that no mise config declares (`mise bootstrap packages prune --dry-run`, and again with `-m brew-cask`). It never removes them; review the list and run `mise bootstrap packages prune` yourself to remove every one
- runs `mise prune`, which deletes the tool versions the previous run replaced that no project's mise config still uses, and reports how much it freed. The versions this run replaces stay until the next run, so you can go back to one. The prune is skipped, with a notice, while a leftover mise rust install would make it hang
- upgrades mise tools (Node/Python patch releases, CodeGraph, the npm CLIs, the Aspire CLI and flate); a tool mise could not reinstall is a notice
- updates the stable Rust toolchain (`rustup update`). rustup is the `brew:rustup` package, called by path because it keeps its proxies in `/opt/homebrew/opt/rustup/bin`. A notice follows when `cargo --version` fails in that shell, or when a mise rust toolchain that no config pins shadows it
- upgrades the uv tools (Serena and Scrapling), then re-runs `scrapling install` so its Chromium matches
- reinstalls the Iosevka Code font if its upstream zip changed
- updates Claude Code itself (`claude update`) and reports its version, before the steps below so they run on the new binary
- reinstalls each tracked agent skill whose source changed since it was installed, for the agents it is listed for (`claude-config restore skills --update`); the skills CLI records a GitHub folder's git SHA or a well-known site's digest, so unchanged skills are left alone, and a skill it can't check is reinstalled every time
- reinstalls REA's bundled `reverse-engineer-anything` skill when it differs from the installed `rea-agents` (`rea setup --skill`), so the skill matches the server
- re-runs the pinned Hindsight memory installer (`hindsight-memory upgrade`, only when `~/.hindsight/coding-agent.json` exists) and reports a newer release as a notice once npm's `min-release-age` lets it install, since the version pin in `bin/hindsight-memory` is bumped by hand; the installer's own `▲` warnings (no `uv`, no `cargo`, no model) become a notice too, because each means the memory daemon can't cold-start from that shell
- refreshes the SnippetsLab skill from the app when SnippetsLab is installed (`install-snippetslab-skill`)
- refreshes the Claude Code marketplaces and updates every installed plugin (`claude plugin marketplace update`, then `claude plugin update` per plugin; Claude Code applies them on its next start; `-y` accepts a marketplace-declared install command without showing it, since the tracked marketplaces are vetted ones)
- drops retired Claude Code permission rules from this Mac (`claude-config retire`, which only removes), then records the plugins, base settings and user skills in the repo (`claude-config save`, review with `git diff`; skipped with an action when the repo has plugins or settings this Mac lacks) and rebuilds the catalog (`claude-catalog`), then checks mise's MCP server: if its user-scope entry isn't `✔ Connected` and runs a different command from what setup writes (a moved binary, an old wrapper), it's re-registered; otherwise it warns, naming anthropics/claude-code#88128 when the server lists no tools. A missing registration is left alone
- asks Raycast to check for app and extension updates
- updates Amp, if it's installed

A step that belongs to a [module](modules.md) you switched off (`rotm settings set modules.<module> off`) prints `the <module> module is off` and does nothing: the font with `fonts`, Raycast with `apps`, the Claude Code steps with `claude`, and the REA, Hindsight, SnippetsLab, Scrapling and mise MCP steps with `agents`. The package steps need no switch, because mise no longer reads that module's file. The packages it installed stay, so the notice that counts packages no config declares names the modules that are off. A package you declared `{ state = "absent" }` in `config.local.toml` is not reported as missing.

It doesn't re-apply the dotfiles. When a pull brings new symlinks, tools or config, run setup again:

```shell
"$DOTFILES/setup.sh" # add `-- --skip packages` to leave the packages alone
```

`setup.sh` installs what's missing but doesn't upgrade what's already there, except PowerShell (`dotnet tool update`) and the Iosevka Code font. There are two ways to upgrade. `./setup.sh -- --upgrade` upgrades what the mise config declares: the packages, one manager at a time with a warning on failure, and the tools. `sysup` upgrades everything: macOS, mise itself, the packages, the tools, Rust, the uv tools and the agent tooling.

The repo's own pins get update PRs from [Renovate](https://docs.renovatebot.com/) (config in [`renovate.json`](../renovate.json)): `package.json` and its `packageManager` pnpm, the single-version tools in the global mise config, and the action pins and `setup-python` version in `.github/workflows/`. It waits 7 days after a release, like `pnpm-workspace.yaml`'s `minimumReleaseAge`, opens or refreshes the daily `@ampcode/plugin` snapshots only early on Monday (New York time), and keeps mise's `npm:typescript` below 7 and `azure-functions-core-tools` below 5. It skips mise's `node` and `python`: its mise manager reads only the first entry of a version list, so it would rewrite the default and leave the rest. Those, like `.nvmrc`'s `lts/*`, stay manual. The `check` workflow ([`.github/workflows/check.yml`](../.github/workflows/check.yml)) runs `pnpm check` on macOS for every PR, its PRs included, and every push to `main`. Its Dependency Dashboard issue lists held and pending updates; tick a PR's rebase box there to re-run the check on a PR opened before a workflow change. The packages in `30-packages.toml` and mise's `latest` entries stay with `sysup`; VS Code updates its own extensions.

An update of VS Code replaces the files the SpaceBox UI Enhancer patched, so run **SpaceBox Enable UI Enhancer** again afterwards (see [vscode](../vscode/README.md#spacebox-ui-enhancer)).

## macOS update password from 1Password (optional)

`sysup` starts with a fingerprint for `sudo`, but a macOS update still stops at `Password:`. That prompt comes from `softwareupdate` itself: on Apple Silicon only the account password authorizes an OS update, and neither `sudo` nor Touch ID counts. If you keep that password in 1Password, `sysup` can fetch it with a fingerprint instead. Without this setup nothing changes and you type the password as before.

1. In 1Password, save your Mac login password as an item (a Login or Password item; any vault).
1. Turn on **Settings → Developer → Integrate with 1Password CLI**. The `op` command is the `brew-cask:1password-cli` package.
1. Copy the field's secret reference: open the item, click the arrow next to the password field → **Copy Secret Reference**. It looks like `op://Private/Mac login/password`.
1. Store it with [`dotfiles-settings`](../settings/README.md), which keeps it in a git-ignored file inside the clone:

   ```shell
   dotfiles-settings set updates.mac_password_op 'op://Private/Mac login/password'
   ```

   An `export DOTFILES_MAC_PASSWORD_OP=…` in [`~/.zsh.local`](local-customizations.md#zshlocal) still works. It is the seed that the setting beats.

1. Open a new terminal and check that it resolves (this prints nothing but `ok`):

   ```shell
   op read "$DOTFILES_MAC_PASSWORD_OP" > /dev/null && echo ok
   ```

`sysup` only asks 1Password when a macOS update is actually pending. If `op` is missing or the variable is unset, it asks for the password at its own `Password:` prompt, which hides what you type, and passes it to `softwareupdate` the same way. A password `softwareupdate` rejects fails the macOS step; there is no retry. Update the 1Password item when you change your login password.
