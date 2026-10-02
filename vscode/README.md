# Visual Studio Code

## How it works

- `setup/symlinks.sh` links `~/Library/Application Support/Code/User` → `vscode/User`, so settings, keybindings, snippets, tasks and chat model config come straight from this repo. If a `User` folder already exists, the script asks before replacing it.
- The repo is the source of truth: keep VS Code **Settings Sync off**, otherwise it would write its own state over the linked files.
- Machine-local state that VS Code writes into that folder is gitignored (see [.gitignore](../.gitignore)): `vscode/**/sync/`, `profiles/`, `globalStorage/`, `History/`, `workspaceStorage/` and `syncLocalSettings.json`.

## Settings and keybindings

- `User/settings.json` holds the day-to-day preferences: the editor and terminal fonts, the SpaceBox color theme, formatter and linter config, etc. It's **generated and gitignored**: `bin/vscode-settings` renders it from the tracked template `User/settings.json.j2` with [minijinja-cli](https://github.com/mitsuhiko/minijinja) (Brewfile), filling in the font preset and `$HOME` (for `notes.notesLocation`). See [Fonts and the settings template](#fonts-and-the-settings-template).
- `User/keybindings.json` is intentionally empty (`[]`), so VS Code uses its stock shortcuts — see `help gui/visual-studio-code`. Add bindings there if you want to customize.
- `.vscode/settings.json` at the repo root is a different file: workspace settings that apply only while this repo is open (the Brewfile as Ruby, ShellCheck skipping the zsh completion functions, spell-check words). `vscode/User` applies to every project.

Settings in the template that are there for a non-obvious reason (each has a comment next to it):

- `workbench.colorCustomizations` and `python.languageServer` are pinned to the value an extension (Mintlify Doc Writer, Python) writes back on every startup. Removing them makes the repo show as modified after each launch.
- `dependi.decoration.incompatible.template` adds `\uFE0F` after the ❌. Iosevka Code has its own plain glyph for that character, so without it the "outdated" marker in `package.json` shows in the text color instead of as the red emoji.
- `files.associations` maps `LICENSE` to plain text. VS Code otherwise guesses Markdown, and markdownlint then complains about the first line.
- `spacebox-ui.*` and the `[SpaceBox]` colors: see [below](#spacebox-ui-enhancer).

## Fonts and the settings template

`vscode/presets.toml` defines the font presets; `vscode-settings --choose` (also offered during setup) picks one, saves it in `~/.config/dotfiles/vscode.env`, and renders:

| Preset | Editor | Terminal |
| --- | --- | --- |
| `iosevka` (default) | Iosevka Code 14 | Iosevka Code |
| `warp` | ProFont IIx Nerd Font Mono 13 | ProFont IIx 13 (matches Warp's terminal font) |
| `warp-terminal` | Iosevka Code 14 | ProFont IIx 13 |
| `fira` | FiraCode Nerd Font Mono 14 | FiraCode |

Each keeps FiraCode Nerd Font Mono as the fallback. Iosevka Code comes from `bin/install-iosevka-code` (see [fonts](../fonts/README.md)), ProFont and FiraCode from the Brewfile's font casks; the renderer warns when a preset's font isn't installed. `vscode-settings --preset warp` switches directly, `--check` compares without writing.

Edit **`User/settings.json.j2`**, never `settings.json`, then run `vscode-settings`. When you change a setting in VS Code's UI (or an extension writes one), it lands only in the generated file. The renderer remembers a hash of what it last wrote, so the next render refuses to overwrite such a change: it shows the diff, you copy the change into the template and re-run, or pass `--force` to drop it. `pnpm check` runs the renderer's tests and Prettier-checks every preset's render.

## Editing settings

VS Code rewrites `User/settings.json` itself, so the template has to render exactly what VS Code would write, or every save produces drift:

- No trailing commas. `User/.prettierrc.yaml` sets that for this folder, because VS Code opens these files through `~/Library/Application Support/Code/User`, where the repo's root Prettier config isn't found.
- Keep the existing key order and grouping, and don't add a setting that only repeats VS Code's default.
- Format-on-save runs Prettier on shell files too, and its shell plugin reads zsh as bash: saving a zsh file rewrote `${keys[Ctrl+K]}` as `${keys[Ctrl + K]}`, which still parses but breaks the key bindings. The zsh files are listed in [.prettierignore](../.prettierignore) for that reason; add any new zsh file that doesn't end in `.zsh` there as well.

## SpaceBox UI Enhancer

The `spacebox-ui.*` settings (blur for menus, hovers and the Command Palette) do nothing on their own: the [SpaceBox UI Enhancer](https://marketplace.visualstudio.com/items?itemName=SpaceBox.spacebox-ui) extension works by patching VS Code's own files inside the app, and only when told to. Setup can't do it, since the command exists only inside VS Code:

1. Run **SpaceBox Enable UI Enhancer** from the Command Palette, then quit VS Code (⌘Q) and open it again. A window reload isn't enough: VS Code then warns "Your Code installation appears to be corrupt", because it still holds the checksums it read at launch. The extension rewrites them in `product.json`, so the warning goes away after a full restart.
1. Repeat after a VS Code update (it replaces the patched files; `upup` upgrades VS Code, so expect it then) and after updating the extension (**SpaceBox Disable UI Enhancer** first, then enable again).

To undo it, run **SpaceBox Disable UI Enhancer** and restart: it restores VS Code's original files from the backups the extension made. Patching the app also invalidates its macOS code signature (`codesign --verify` fails), so disable it first if macOS or VS Code starts complaining about the app.

`spacebox-ui.stylesheet` carries one fix: with extension 0.1.5 the Command Palette stays on screen after Esc or a selection, because the extension's close animation clashes with the one VS Code has built in (seen on VS Code 1.139). The rule restores the normal hide; remove it once an extension update fixes this. Any change to a `spacebox-ui.*` setting needs the enable step again.

Blur only shows through see-through backgrounds, and the SpaceBox theme's are solid, so `settings.json` overrides two of them, the Command Palette and hovers, under `workbench.colorCustomizations` → `[SpaceBox]` (other themes are unaffected). Menus stay solid on purpose: extension panels such as Claude Code reuse `menu.background` for their own menus, and the blur can't reach inside a panel, so a see-through menu there is just unreadable text over text.

## `code` command line helper

No manual step needed: the `visual-studio-code` cask links `code` into `/opt/homebrew/bin`, and `setup/symlinks.sh` links `/usr/local/bin/code` as a fallback if `code` isn't found. (The equivalent manual step is **Shell Command: Install 'code' command in PATH** from the Command Palette.)

## Install extensions

The extensions are listed in the [Brewfile](../setup/Brewfile). VS Code keeps them up to date itself; `upup` upgrades VS Code through Homebrew. Install all of them with:

```shell
bin/brewpick --all
```

Or pick a subset interactively via fzf:

```shell
bin/brewpick
```

> [!WARNING]  
> Don't run `brew bundle --file setup/Brewfile` directly: it rejects the `manual "MonoLisa"` entry. `bin/brewpick --all` strips `manual` entries before calling `brew bundle`.

## Optional layout tweaks

These are UI state (not stored in `settings.json`), so apply them by hand if you like:

1. Hide `Open Editors` from Explorer.
1. Move `Search`, `Source Control`, `Outline` and `GitHub Pull Requests` from the **Activity Bar** to the Panel, and put the Panel at the bottom (**View** → **Appearance** → **Panel Position** → **Bottom**).
1. Stack panels in order: `Search`, `Terminal`, `Source Control`, `Problems`, `GitHub Pull Requests`, `Comments`, `Output`, `Outline`, and hide the rest.

`vscode/spellright.dict` is a leftover word list for the Spell Right extension (not in the Brewfile); nothing in setup links or references it.
