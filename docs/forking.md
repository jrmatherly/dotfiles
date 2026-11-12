# Make it yours

Setup already asks for your git identity and commit signing. These values are hard-coded to me, so change them in your fork:

| File | What to change |
| --- | --- |
| [`README.md`](../README.md), [`docs/installation.md`](installation.md), [`docs/macos tips & tricks.md`](macos%20tips%20%26%20tricks.md) | Title, intro and the `jrmatherly/returnofthemac` clone URL and link |
| [`agents/README.md`](../agents/README.md) | The `jrmatherly/skills` links point to my skills repo. Use it, your own, or the [skills CLI](https://github.com/vercel-labs/skills) alone |
| [`tilde/.config/fastfetch/config.jsonc`](../tilde/.config/fastfetch/config.jsonc) | Name, URL and weather `location` |
| [`lazygit/config.yml`](../lazygit/config.yml) | The author name under `authorColors` |
| [`agents/claude-*`](../agents/) | My Claude Code plugins, settings and skills, including the `jrmatherly-skills` marketplace (`jstack`, `resume`) and the `coding-standards` and `supabase-prompts` skills from my public skills repo. Keep them or drop those lines. Run `claude-config save` once yours are installed and commit the result |
| [`agents/catalog/curated.toml`](../agents/catalog/curated.toml) | Notes on my tools. `claude-catalog` still builds but exits 1 (a warning in setup) for each skill, command or agent you don't have installed. Delete those. An `[mcp.*]` entry you lack, like my `coolify` server, only prints a `lint:` note, because MCP registration is per machine |
| [`30-packages.toml`](../tilde/.config/mise/conf.d/30-packages.toml), the [modules](modules.md) (`conf.d/60-rotm-*.toml`), and the tools in [`config.toml`](../tilde/.config/mise/config.toml) | My formulae, apps and VS Code extensions. Trim the modules or turn them off before the first run. The `jrmatherly/tap` entries (`claude-multipass` and its app) are my own projects |
| [`settings/registry.toml`](../settings/registry.toml) | `macos.disable_time_machine` and `macos.firewall` default to on, my choice. **If you use Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before `set-defaults`, which otherwise stops all backups.** |
| [`package.json`](../package.json) | The `author` field |
| [`settings/README.md`](../settings/README.md) | The `uv tool install` line names `jrmatherly/returnofthemac` |
| [`setup/README.md`](../setup/README.md) | The `misc` section links my `jrmatherly/skills` repo and names its `jrmatherly-skills` marketplace |
| [`setup/bootstrap-runtime.archify.json`](../setup/bootstrap-runtime.archify.json) | The `meta.repository.url` clone URL (Archify's source for the setup diagram; the exported SVG doesn't show it) |
| [`LICENSE`](../LICENSE) | Add your copyright line; keep the existing ones (MIT requires it) |

[`docs/jstack.md`](jstack.md) and [`docs/gui/raycast.md`](gui/raycast.md) also link my own projects (`jrmatherly/skills`, `jrmatherly/claude-multipass`); they describe tools this setup installs, so keep them unless you drop those tools.
