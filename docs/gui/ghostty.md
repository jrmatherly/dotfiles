# Ghostty

> Fast, native GPU-accelerated terminal; config tracked in `tilde/.config/ghostty/config`

## Repo setup

- **Install:** `cask "ghostty"` in `setup/Brewfile`
- **Config:** `tilde/.config/ghostty/config`, symlinked to `~/.config/ghostty` by `setup/symlinks.sh` (Ghostty reads the XDG path `~/.config/ghostty/config` on macOS)
- **Theme:** `dark:Squirrelsong Dark Deep Purple,light:Squirrelsong Light`, switching automatically with the system appearance
- **Theme files:** `tilde/.config/ghostty/themes` (Ghostty looks up theme names in `~/.config/ghostty/themes`). The theme files are owned by this repo (nothing is downloaded); edit them here and commit
- **Font:** Hack Nerd Font Mono 17pt, installed by the Brewfile (`font-hack-nerd-font`). Ligatures are off (`-liga`, `-clig`), with slashed zero (`zero`) on

## Notable settings

- **`palette-generate` + `palette-harmonious`:** build the extended 256-color palette from the theme's 16 colors, ordered so it reads well in light and dark mode
- **`macos-titlebar-style = tabs`:** tab bar merged into the titlebar
- **`macos-icon = custom-style`, `macos-icon-frame = beige`:** retro beige Dock icon; its ghost and screen colors come from the active Squirrelsong theme file, so the icon follows light/dark mode
- **`cursor-style = bar`, no blink:** plus `shell-integration-features = no-cursor` so zsh doesn't change the cursor shape
- **`window-save-state = always`:** windows, tabs and splits are restored on relaunch
- **`copy-on-select = clipboard`:** selecting text copies it to the system clipboard; `clipboard-trim-trailing-spaces` strips trailing whitespace
- **`macos-auto-secure-input = false`:** stops Secure Input from switching on at password prompts, because it interferes with accessibility features such as Touch ID

## Custom keybinds (repo)

- **Cmd+Esc:** toggle the quick terminal from any app (a `global:` keybind, so Ghostty needs Accessibility permission)
- **Cmd+Shift+Left/Right:** previous/next split
- **Cmd+Enter:** sends a newline (submits a prompt) instead of the default full-screen toggle. Use **Cmd+Ctrl+F** for full screen

## Default shortcuts

- **Cmd+,:** open config file
- **Cmd+Shift+,:** reload config (some options only apply to new windows or terminals)
- **Cmd+Shift+P:** command palette
- **Cmd+T / Cmd+N:** new tab/window
- **Cmd+W:** close split or tab
- **Cmd+1…8, Cmd+9:** go to a tab, go to the last tab
- **Cmd+Shift+[,]:** previous/next tab
- **Cmd+D / Cmd+Shift+D:** split right/down
- **Cmd+[,]:** previous/next split
- **Cmd+Alt+Arrows:** focus a split by direction
- **Cmd+Ctrl+Arrows:** resize a split; **Cmd+Ctrl+=** makes all splits equal
- **Cmd+Shift+Enter:** zoom the current split
- **Cmd+Up/Down:** jump to the previous/next prompt
- **Cmd+K:** clear screen
- **Cmd+F:** search; **Cmd+G / Cmd+Shift+G:** next/previous match
- **Cmd+= / Cmd+- / Cmd+0:** font size bigger/smaller/reset
- **Cmd+Alt+I:** terminal inspector

## CLI

The CLI binary isn't on `PATH`. Run it as `/Applications/Ghostty.app/Contents/MacOS/ghostty`:

- **`+list-keybinds --default`:** show all default keybinds
- **`+list-themes`:** browse the available themes
- **`+show-config --default --docs`:** print every option with its documentation
- **`+validate-config`:** check the config for errors

## Sources

- https://ghostty.org/docs/config
- https://ghostty.org/docs/config/reference
- https://ghostty.org/docs/config/keybind
- https://ghostty.org/docs/features/theme
- Installed Ghostty 1.3.1: `ghostty +list-keybinds --default` and `+show-config --default --docs`
