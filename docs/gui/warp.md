# Warp

> Agentic terminal: command output grouped into blocks, a built-in AI agent, Warp Drive for saved workflows

## Repo setup

- **Install:** `cask "warp"` in `setup/Brewfile`. The repo doesn't track any Warp settings
- **Shell config:** Warp runs your normal zsh, so `zsh/` and the Starship prompt (`tilde/.starship.toml`, loaded in `zsh/init.zsh`) apply here too

## Using the Starship prompt

Warp shows its own prompt by default. To use Starship:

- **Settings > Appearance > Input > Input type:** set to **Shell (PS1)**
- Warp lists Starship as working on zsh, with caveats. The repo's `.starship.toml` avoids the settings Warp documents as problems: it has no `[custom]` `disabled = false` block and no schema line, and it already sets `command_timeout`
- The prompt's `$line_break` (two-line prompt) works on zsh, so you don't need to disable it

## Essentials

- **Cmd+P:** command palette
- **Cmd+,:** settings; **Ctrl+Cmd+K:** keybindings editor
- **Cmd+T:** new tab; **Cmd+Shift+T:** reopen closed tab
- **Cmd+O:** file search
- **Ctrl+R:** command search (history); **Ctrl+Shift+R:** workflows
- **Cmd+\:** Warp Drive
- **Cmd+L:** focus terminal input
- **Ctrl+Cmd+T:** theme picker

## Panes

- **Cmd+D / Cmd+Shift+D:** split pane right/down
- **Cmd+Alt+Arrows:** switch pane in that direction; **Cmd+[,]:** previous/next pane
- **Ctrl+Cmd+Arrows:** resize pane
- **Cmd+Shift+Enter:** maximize the active pane

## Blocks

- **Cmd+Up/Down:** select the previous/next block
- **Cmd+Alt+Shift+C:** copy command output
- **Cmd+B:** bookmark the selected block; **Alt+Up/Down:** jump between bookmarks
- **Cmd+K:** clear blocks
- **Cmd+F:** find; **Cmd+G / Cmd+Shift+G:** next/previous match

## Agent

- **Cmd+Enter:** start a new agent conversation (same as typing `/agent`)
- **Cmd+I:** switch between command mode and Agent Mode
- **Esc:** leave the conversation and return to terminal mode
- **Cmd+Y:** open the conversation selector
- **Cmd+Alt+Enter:** start a cloud agent conversation
- **`!` prefix:** in the agent view, run the input as a shell command (e.g. `!git status`)

## Sources

- https://docs.warp.dev/getting-started/keyboard-shortcuts
- https://docs.warp.dev/terminal/appearance/prompt
- https://docs.warp.dev/agents/local-agents/interacting-with-agents/terminal-and-agent-modes/
