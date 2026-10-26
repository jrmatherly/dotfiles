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
- Give the ones you use often a hotkey (see below); **Settings → Window Management** (in the extension list of the settings sidebar) has gaps, cycling behaviour and keyboard shortcut presets

## Aliases and hotkeys

- **Settings → Shortcuts:** every command in one table; click its **Alias** cell to type one, or **Add Hotkey** to record one (Raycast 2.9)
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

## Claude account script commands

[claude-multipass](https://github.com/jrmatherly/claude-multipass) (installed from the Brewfile) ships three script commands, **Claude Account**, **Claude Account Usage** (opt-in: it decrypts the saved token through the Keychain; click **Always Allow** once on the "Claude Safe Storage" dialog) and **Switch Claude Account**. Copy them once to a folder you own, `cp -R "$(brew --prefix)/share/claude-multipass/raycast" ~/.config/claude-multipass/raycast` (the Homebrew path is a symlink into the versioned Cellar folder and changes on upgrade; the picker also hides `/opt`), then Raycast → **Settings → Script Commands → Add Script Directory**, Cmd+Shift+G, `~/.config/claude-multipass/raycast`. Do not use **Developer → Import Extension**: that imports a packaged extension, not a script directory. Its docs: `$(brew --prefix)/share/doc/claude-multipass`.

## Sources

- https://manual.raycast.com/settings
- https://manual.raycast.com/keyboard-shortcuts
- https://manual.raycast.com/command-aliases-and-hotkeys
- https://manual.raycast.com/window-management
- https://manual.raycast.com/clipboard-history
- https://manual.raycast.com/script-commands
- https://github.com/raycast/script-commands
- Local: Raycast 2.9.0 settings window
