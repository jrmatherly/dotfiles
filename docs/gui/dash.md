# Dash

> Offline API documentation browser (Setapp edition, `com.kapeli.dash-setapp`). Not installed by setup: install it from Setapp.

## Sync folder

Dash's settings sync to the repo's `dash/` folder (`dash/Dash.dashsync`).

- **Dash → Settings → General → Syncing: Set Up Syncing…** opens the sync sheet; **Set Sync Folder…** → the repo's `dash/` folder (`$DOTFILES/dash`, e.g. `~/dev/dotfiles/dash`). **Stop Syncing** on the same sheet turns it off
- Under **What to sync**, tick: **General settings**, **View options**, **Docsets, search profiles and docset keywords**, **Bookmarks and web searches**
- Do **not** use **Sync Snippets** — it moves the snippet database into the folder, which doesn't belong in git
- Docsets live in `~/Library/Application Support/Dash/DocSets`; sync only records which ones you installed from Settings → Downloads, and Dash re-downloads them on other Macs. Docset order and disabled docsets stay per-Mac
- Quit Dash before editing `dash/Dash.dashsync` by hand so it doesn't overwrite your change

## Generated docsets (`setup/dash.sh`)

- `setup/dash.sh` (or `./setup.sh --dash`) only adds **Docset Generator** entries for local folders of HTML docs; `setup/dash.sh add <folder> [name] [keyword]` adds one non-interactively. Set the sync folder (above) first, and quit Dash before running it
- Build them in **Settings → Downloads → Docset Generator** (HTML only, not Markdown)

## Searching

- **`keyword:query`:** search one docset, e.g. `php:printf` — works even if the docset is disabled
- Edit docset keywords in **Settings → Docsets** (drag to reorder results too); one keyword can cover several docsets
- **Search profiles:** collections of docsets, set up from the icon in the main search field. A profile can be activated by a typed keyword (e.g. `web:`), when an app becomes active, or by its own global shortcut; profiles persist between searches
- **Option+↓ / Option+↑:** move through the table of contents (left pane)
- `dash://?query=php:printf` searches from anywhere (`open 'dash://?query=…'` in a terminal)

## Global shortcuts

- **Settings → General:** three recorders, **Show Dash**, **Show Dash and focus search field** and **Search using selected text**, all unset here
- **Settings → Integration:** plugins for third-party apps (Raycast, VS Code, JetBrains, Terminal, …), the optional **Dash API Server**, and **AI Agents Integration → Set Up MCP Server…** for agents that speak MCP

## Snippets

- Type a snippet's abbreviation in any app to expand it; a symbol prefix (e.g. a backtick) avoids accidental expansion
- `__name__` is a placeholder; `@clipboard`, `@date`, `@time` are special placeholders

## Sources

- https://kapeli.com/dash_guide
- https://kapeli.com/docsets
- Local: Dash 8.2.0 settings window (General, Docsets, Integration and the sync sheet)
