---
paths:
  - 'tilde/.config/mise/conf.d/20-macos.toml'
  - 'setup/macos-extras.sh'
---

# macOS defaults

- Preferences are declared in `conf.d/20-macos.toml` and applied by `bin/set-defaults` only. `setup.sh` never applies them. A plain `mise bootstrap` run by hand does. `setup/macos-extras.sh` holds only what TOML cannot express: sudo, `$HOME` paths, `pmset`, file flags, sandboxed apps (TextEdit, Preview, Help Viewer), the groups a user can switch off, and the app restarts.
- Security-sensitive and per-machine settings are never declared in the tracked fragment (`setup/tests/macos-defaults.py` fails on two of them). They are an `env` setting the extras script reads, or a table in the git-ignored `config.local.toml`. The firewall and turning Time Machine off are on unless set to the empty string (`${VAR-1}`, `default = "1"`); HiDPI is off unless set (`${VAR:-}`) and the computer name is empty unless set. A setting that needs sudo reads the Mac's state first and calls sudo only when it differs. Turning one off changes nothing. The Time Machine default stops all backups, so every doc that describes `set-defaults` says to switch `macos.disable_time_machine` off first on a Mac that uses Time Machine.
- `config.local.toml` can pin another value but cannot say "leave it as it is", and mise applies every declared key. So a preference group a user may want left alone (screenshots, Time Machine's new-disk prompt, TextEdit, Software Update) is written by the extras script behind a switch that is on unless set to the empty string (`${VAR-1}`, no colon: the settings UI writes `""` for off). Never move such a group back into the fragment.
- Every `DOTFILES_MACOS_*` variable the extras script reads has an `env` entry in `settings/registry.toml`, section "macOS (this Mac)". Add both together.
- Types matter: mise treats `1` and `true` as different values. Before adding a key, run `defaults read-type <domain> <key>` on a Mac where the setting is already on, and verify the domain and key against the current macOS release. Prefer leaving a value at the macOS default over pinning it.
- mise never deletes a preference, never uses sudo and never restarts an app. Removing a line leaves the value in place until `defaults delete <domain> <key>`.
- Values are not templated, and `{{ config_root }}` in a hook is `$HOME`. The `pre-defaults` and `post-defaults` hooks run under `mise bootstrap` when its `macos-defaults` part runs, and not under `mise bootstrap macos defaults apply`, so `bin/set-defaults` calls the extras script itself.
- The extras script force-quits Finder, Dock, Activity Monitor, Notification Center, SystemUIServer and Terminal when the apply wrote something, and always under `set-defaults`. Drift alone restarts nothing. Keep that list and `README.md`'s description of it in sync.
- The settings UI edits the fragment's text in place and writes that one key with `defaults write`. It never applies the whole fragment. Keep one `key = value` per line for scalar keys so that edit stays possible.
- Every `setup/*.sh` is committed executable (`bin/lib/test-conventions` checks the mode). Hooks run the script directly.
