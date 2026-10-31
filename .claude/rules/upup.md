---
paths:
  - 'bin/upup'
  - 'bin/lib/test-upup'
---

# upup

`bin/upup` is the source for the step list and line formats. Self-check: `bin/lib/test-upup` stubs every external command on PATH. These are the constraints the code doesn't show.

- **Report contract**: every step ends in one status line (`ok`, `changed`, `notice`, `fail`; `test-upup` asserts it). A failed step after the opening `sudo -v` never aborts the run. Full output goes to the log. A `changed` line only appears when the step really changed something, so steps compare before and after instead of parsing messages.
- **macOS**: an update whose list entry says `Action: restart` is only downloaded by `-ia` without `--restart`, and a plain restart doesn't install it (checked 2026-10-27), so the summary names Software Update's Restart Now or `softwareupdate -ia --restart`. upup never restarts. Only those updates need the owner password (Apple Silicon owner authorization; sudo and Touch ID don't count). It comes from `op read` when `DOTFILES_MAC_PASSWORD_OP` is set in `~/.zsh.local` and `op` is on PATH, else from upup's own hidden prompt, and goes in through `--stdinpass`. softwareupdate must never prompt itself: with its output piped to the log, its prompt echoed the password. A rejected password is a `fail` line with no retry.
- **Rust**: `rustup` runs through `$HOMEBREW_PREFIX/opt/rustup/bin/rustup` when it exists, because a mise shim earlier on an activated PATH would otherwise win. A shim left by a rust toolchain no config pins gets a notice to remove the install dir and `mise reshim`, not `mise prune`, which runs that shim and hangs. So prune is skipped while that dir exists and is bounded by `timeout 600`. `cargo --version` is the same probe Hindsight's daemon preflight runs, and a shell older than the rustup PATH entry fails it, which is why it is a notice.
- **mise**: `mise prune --yes` runs before `mise upgrade`, deleting what the previous run replaced and keeping what this run replaces, so an upgrade can be rolled back until the next run.
- **Claude Code**: `claude update` is read through two `claude --version` calls because its message isn't parsed. `claude plugin update -y` accepts a marketplace-declared install command unseen, a trust the tracked marketplaces have earned. Plugins blocked by a managed policy collapse into one notice. `claude-config retire` runs before `claude-config save`, or save would undo a pull's cleanup on this Mac. It only removes: upup must not run `restore settings`, which would apply newly pulled permission grants unreviewed and bring back a rule revoked on this Mac.
- **mise MCP check**: a user-scope entry whose command isn't `$(command -v mise) mcp` is re-registered. `tools fetch failed` is a notice because re-registering can't fix anthropics/claude-code#88128; anything else is a `fail` line with the commands. A missing entry stays silent.
- **Hindsight**: the newer-release notice only fires once npm's `min-release-age` would let it install, and the installer's `▲` warning lines become notices, since each means the daemon can't cold-start from that shell.
- **CA roots**: with `DOTFILES_TRIM_CA_ROOTS` set in `~/.zsh.local`, `ca-roots trim` runs before `brew doctor` and renews sudo first, because brew upgrade can outlast sudo's timeout. Without it, doctor's root-certificate warning becomes a notice naming the opt-in.
- **Docker Compose**: `upup` won't notice the fix `bin/docker-devcontainer` waits for, because the compose plugin in use is OrbStack's, not Homebrew's.
