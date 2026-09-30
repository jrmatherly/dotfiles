# Squirrelsong Color Theme

This setup uses the [Squirrelsong](https://sapegin.me/squirrelsong/) theme where one exists. Terminal tools use the **Dark Deep Purple** variant. Visual Studio Code is the exception: it uses the SpaceBox theme (`workbench.colorTheme` in [vscode/User/settings.json](../vscode/User/settings.json)).

## Files in this folder

- [fzf-squirrelsong-dark-dp.sh](fzf-squirrelsong-dark-dp.sh) — fzf colors (Dark Deep Purple), sourced by [zsh/fzf.zsh](../zsh/fzf.zsh)
- [fast-syntax-highlighting.ini](fast-syntax-highlighting.ini) — command-line highlighting theme for zsh-fast-syntax-highlighting, loaded with `fast-theme` in [zsh/init.zsh](../zsh/init.zsh)

## Theme files (owned by this repo)

Every theme file lives in this repo and is maintained here — nothing is pulled from upstream. To change a theme, edit its file and commit it. [`install-color-themes`](../bin/install-color-themes) applies them where an app needs a step (bat's cache, an Obsidian vault) and prints where to import the rest. Setup doesn't run it: run it yourself, or through `sync-all`. `setup/symlinks.sh` only rebuilds bat's cache.

| App | Theme file(s) | How it's applied |
| --- | --- | --- |
| bat | `tilde/.config/bat/themes` | Linked into `~/.config`; `BAT_THEME` (zsh/env.zsh) selects Dark Deep Purple. `setup/symlinks.sh` and `install-color-themes` rebuild bat's cache |
| btop | `tilde/.config/btop/themes` | Linked into `~/.config`; `btop.conf` selects Dark Deep Purple |
| Ghostty (and cmux) | `tilde/.config/ghostty/themes` | Linked into `~/.config`; Dark Deep Purple in dark mode, Light in light mode |
| Obsidian | `obsidian/.obsidian/themes/Squirrelsong` | `obsidian-vault install` (and `install-color-themes`) copy it into the vault; `obsidian/.obsidian/appearance.json` selects it |
| Nimble Commander | `nimble-commander/themes/Squirrelsong Light.json` | Import in Nimble Commander → Settings → Themes (fonts set to Hack Nerd Font Mono) |
| Syntax Highlight | `syntax-highlight/themes/Squirrelsong Light.theme` | Import in the app's color scheme settings, see [syntax-highlight](../syntax-highlight/README.md) |
| CotEditor | `coteditor/themes/Squirrelsong Light.cottheme` | Import in CotEditor → Settings → Appearance |

The terminal tools get Dark Deep Purple (Ghostty and Obsidian follow the system appearance). Nimble Commander, Syntax Highlight and CotEditor only have the Light variant here.

The files originally came from [Squirrelsong](https://github.com/sapegin/squirrelsong) by Artem Sapegin. The Dark Deep Purple variant is no longer published there, which is one more reason the repo keeps its own copies.

Optional, not tracked here: Squirrelsong for [Firefox](https://github.com/sapegin/squirrelsong/tree/master/themes/Firefox) (Developer Edition isn't installed by setup; see [firefox](../firefox/README.md)) and its [macOS color tweaks](https://github.com/sapegin/squirrelsong/tree/master/themes/macOS).

## Other themes

[`sidenotes/themes`](../sidenotes/themes) holds three themes for the SideNotes app (City Lights, Dark and Smooth, Nord). They aren't Squirrelsong, and nothing in setup installs SideNotes or imports them; import a `.sntheme` file in SideNotes yourself if you use it.

## Hand-tuned Squirrelsong colors elsewhere

Edit them in place: Amp (`tilde/.config/amp/themes/squirrelsong-dark-dp`), hunk (`tilde/.config/hunk/config.toml`), lazygit (`lazygit/config.yml`) and ripgrep match colors (`tilde/.ripgreprc`).
