# Obsidian

The repo is the source of truth for the vault's setup; your notes live in the
vault itself.

- [`.obsidian/`](.obsidian) — settings, hotkeys, bookmarks, community plugins,
  the `custom.css` snippet and the [Squirrelsong](../colors/README.md) theme
  (selected in `appearance.json`; text font Iosevka Code, installed by
  [`bin/install-iosevka-code`](../bin/install-iosevka-code); monospace font
  Hack Nerd Font Mono)
- [`Meta/Templates`](Meta/Templates) — note templates (Daily Note, Project,
  Post, Recipe, Trip) and web-clipper templates
- [`Meta/Bases`](Meta/Bases) — Bases views (recent logs, active projects,
  recipes, "on this day", …)

The vault is **iCloud Drive → Notes**
(`~/Library/Mobile Documents/com~apple~CloudDocs/Notes`), set as
`OBSIDIAN_VAULT` in [`zsh/env.zsh`](../zsh/env.zsh), so iCloud keeps a copy of
your notes.

## Vault layout

The templates, Bases views and daily notes expect these folders, which
`obsidian-vault install` creates:

| Folder | For |
| --- | --- |
| `Inbox` | New notes (`app.json`) and quick captures (`Inbox/Quickies.md`) |
| `Projects` | Project notes (the "Active projects" view) |
| `Resources` | Reference material: `Food` (recipes), `Books`, `Movies`, `Places`, `Videos`, `Clippings` (web clipper) |
| `Logbook` | Daily notes, created from `Meta/Templates/Daily Note` |
| `Meta` | Templates and Bases views, installed from this repo |

Pasted or dropped files go to `attachments/` (set in `app.json`), which
Obsidian creates the first time you add one.

## Commands

```shell
obsidian-vault install   # repo → vault (quit Obsidian first)
obsidian-vault capture   # vault → repo, then review with git
```

Neither command deletes anything. `install` copies the repo's `.obsidian` and
`Meta` into the vault, creates the folders above, and adds empty
`Dashboard.md`, `Inbox/Quickies.md` and `Resources/Food/Recipes.md` (the
bookmarked notes) only if they're missing. `capture` copies settings and
templates you changed in Obsidian back into the repo; check the diff before
committing — plugin data can contain tokens. Obsidian's per-machine window
layout (`workspace.json`) is never copied either way.

## First-time setup

1. Quit Obsidian if it's open.
2. Run `obsidian-vault install`. This creates iCloud Drive → Notes with the
   folders, settings, theme and templates.
3. In Finder, click **iCloud Drive** in the sidebar to open it, then right-click
   the **Notes** folder in the file list (not the sidebar entry) and choose
   **Keep Downloaded**, so notes are always available offline.
4. Open Obsidian. On the vault screen (or **Vault profile** icon at the bottom
   left → **Manage Vaults…**), click **Open** next to **Open folder as vault**
   and choose iCloud Drive → **Notes**.
5. When asked about the vault's community plugins, choose **Trust author and
   enable plugins** — they come from this repo (Hider, File Explorer Note Count,
   Auto h1 heading, Simple gallery, Typezen). Or browse in restricted mode and
   enable them later in Settings → Community plugins.
6. Check it worked: the Squirrelsong theme is active, and **Cmd+Shift+D** (or
   **Cmd+P** → "Daily notes: Open today's daily note") creates a note in
   `Logbook/<year>` from the Daily Note template. There's no ribbon button
   for it: the ribbon is turned off (`showRibbon` in `appearance.json`).

Update the plugins from Settings → Community plugins, then run
`obsidian-vault capture` to bring the new versions into the repo.
