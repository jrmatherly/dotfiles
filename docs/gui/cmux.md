# cmux

> Open-source terminal built on Ghostty for AI coding agents: vertical workspace tabs, notifications, an embedded browser

## Repo setup

- **Install:** `cask "cmux"` in `setup/Brewfile`
- **Config:** `tilde/.config/cmux/cmux.json`, symlinked to `~/.config/cmux` by `setup/symlinks.sh`. cmux watches the file and applies changes on save, with no restart
- **Terminal look:** cmux renders terminals with your Ghostty config, so the theme, Hack Nerd Font Mono font and cursor from `tilde/.config/ghostty/config` carry over. After editing the Ghostty config, run `cmux reload-config` from a terminal inside cmux (or just reopen cmux); edits to `cmux.json` apply on save

## Notable settings (cmux.json)

- **`app.minimalMode: true`:** hides the workspace title bar and moves its controls into the sidebar
- **`app.preferredEditor: "code"`:** opens files in VS Code when cmux can't preview them
- **`app.openMarkdownInCmuxViewer: true`:** Cmd-clicking a `.md` file opens cmux's rendered Markdown viewer, which reloads live
- **`app.keepWorkspaceOpenWhenClosingLastSurface: true`:** closing the last surface keeps the workspace open
- **`app.sendAnonymousTelemetry: false`:** telemetry off
- **`automation.ripgrepBinaryPath: "/opt/homebrew/bin/rg"`:** the Homebrew `rg` used for project search
- **`automation.cursorIntegration: true`, `claudeCodeIntegration: false`:** installs cmux's integration hooks for Cursor but not for Claude Code
- **`automation.socketControlMode: "cmuxOnly"`:** the default socket control mode
- **`terminal.copyOnSelect: true`:** selecting text copies it to the system clipboard
- **`notifications.sound: "none"`:** silent notifications, with an unread badge on the Dock icon
- **`markdown`:** Hack Nerd Font Mono at 17pt, matching Ghostty
- **`shortcuts.bindings`:** every shortcut is written out explicitly. Rebind an action by its ID; an empty string unbinds it. Keys that appear twice are cmux's own defaults, not mistakes; each action applies where it makes sense: `cmd+[`/`cmd+]` are browser Back/Forward inside a browser pane and Focus Back/Forward everywhere else; `cmd+r` is browser Reload and Rename Tab; `cmd+=`/`cmd+-`/`cmd+0` zoom the browser or the Markdown viewer; and `cmd+shift+g` is both Group Selected Workspaces and Toggle React Grab, which applies to the focused browser, or to the only browser pane when a terminal is focused ([shortcut reference](https://cmux.com/docs/keyboard-shortcuts))

## Shortcuts (as set in cmux.json)

- **Cmd+Shift+P:** command palette; **Cmd+P:** go to a workspace
- **Cmd+N:** new workspace; **Cmd+Shift+W:** close workspace
- **Cmd+1…:** select workspace by number; **Ctrl+1…:** select surface by number
- **Cmd+T:** new surface (tab); **Cmd+W:** close tab
- **Cmd+Shift+[,]:** previous/next surface
- **Cmd+D / Cmd+Shift+D:** split right/down
- **Cmd+Alt+Arrows:** focus the pane in that direction
- **Cmd+Ctrl+=:** make all splits equal; **Cmd+Shift+Enter:** zoom the current split
- **Cmd+B:** toggle sidebar; **Cmd+Alt+B:** toggle file explorer
- **Cmd+I:** notifications panel; **Cmd+Shift+U:** jump to the latest unread
- **Cmd+Shift+L:** open the browser in a split; **Cmd+L:** focus the address bar
- **Cmd+Shift+Ctrl+D:** diff viewer
- **Cmd+F:** find; **Cmd+Shift+F:** find in directory
- **Cmd+Shift+M:** terminal copy mode
- **Cmd+Shift+O:** reopen the previous session
- **Cmd+,:** settings; **Cmd+Shift+,:** reload configuration

## CLI

The `cmux` CLI (linked into `/opt/homebrew/bin` by the cask) talks to the app over a Unix socket (`~/.local/state/cmux/cmux.sock`). Some commands start the app if it isn't running — `cmux <path>` opens a directory in a new workspace, launching cmux if needed, and `cmux shortcuts` does too — so don't run them expecting a headless answer.

- **`cmux config validate`:** check `cmux.json` syntax without the app
- **`cmux reload-config`:** reload both the Ghostty config and `cmux.json`, refreshing terminals in place. cmux must be running, and with the default `socketControlMode: "cmuxOnly"` the command only works from a terminal inside cmux (elsewhere it reports "No live cmux socket found")
- **`cmux notify`:** send a notification, e.g. from an agent hook
- **`cmux ssh`:** create a remote workspace
- **`cmux restore-session`:** restore the previous session by hand

## Sources

- https://github.com/manaflow-ai/cmux (README)
- https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-settings/SKILL.md
- https://github.com/manaflow-ai/cmux/blob/main/skills/cmux-settings/references/all-keys.md
- Repo: `tilde/.config/cmux/cmux.json`
