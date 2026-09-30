# Raycast

> Launcher, clipboard history and window management — replaces Spotlight on ⌘Space.

Installed by `setup/Brewfile` (`cask "raycast"`).

## Setup

- `set-defaults` (`setup/macos.sh`) turns off macOS's Spotlight shortcuts, freeing ⌘Space — Raycast doesn't take it by itself
- Raycast → **Settings (Cmd+,) → General → Raycast Hotkey:** click the field and press ⌘Space
- **General → Open at Login:** keep it on
- If ⌘Space still doesn't register, check **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**, and the Siri shortcut in **System Settings → Apple Intelligence & Siri**
- Window management needs Accessibility access: **System Settings → Privacy & Security → Accessibility**

## Window management

Raycast handles window management here (the repo's Rectangle config is optional and unused).

- Search for commands such as **Left Half** in Root Search (halves, fullscreen, exact size/position)
- Give the ones you use often a hotkey (see below); **Settings → Window Management** has gaps, cycling behaviour and keyboard shortcut presets

## Aliases and hotkeys

- **Settings → Shortcuts:** set an alias ("Add Alias") or **Record Hotkey** for any command
- Or select a command in Root Search, press **Cmd+,** (Configure Command) → **Set Alias** / **Set Hotkey**
- Clipboard History has no default hotkey — assign one the same way

## Everywhere

- **Cmd+Space:** open / close Raycast (once set as above)
- **Enter:** primary action; **Cmd+Enter:** secondary; **Option+Enter:** tertiary
- **Cmd+K:** Action Panel (every available action for the selection)
- **Esc:** back; **Cmd+Esc:** back to Root Search; **Cmd+W:** close window
- **Cmd+F:** add the selected item to Favorites
- **Cmd+Shift+D:** disable the selected command
- **Cmd+Y:** Quick Look; **Cmd+Shift+O:** reveal in Finder
- **Ctrl+N / Ctrl+P:** move down / up (Emacs-style)
- **Cmd+Shift+/:** open the manual

## Clipboard History

- **Enter:** paste the entry; **Cmd+Enter:** copy it
- **Cmd+P:** filter by type (text, images, files, links, …)
- **Cmd+.:** pin; **Cmd+E:** rename

## Sources

- https://manual.raycast.com/settings
- https://manual.raycast.com/keyboard-shortcuts
- https://manual.raycast.com/command-aliases-and-hotkeys
- https://manual.raycast.com/window-management
- https://manual.raycast.com/clipboard-history
