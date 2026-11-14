# Make it yours

Setup already asks for your git identity and commit signing. These values are hard-coded to me, so change them in your fork:

| File | What to change |
| --- | --- |
| [`README.md`](../README.md), [`docs/installation.md`](installation.md), [`docs/macos tips & tricks.md`](macos%20tips%20%26%20tricks.md) | Title, intro and the `jrmatherly/returnofthemac` clone URL and link |
| [`agents/README.md`](../agents/README.md) | The `jrmatherly/skills` links point to my skills repo. Use it, your own, or the [skills CLI](https://github.com/vercel-labs/skills) alone |
| [`tilde/.config/fastfetch/config.jsonc`](../tilde/.config/fastfetch/config.jsonc) | Name, URL and weather `location` |
| [`lazygit/config.yml`](../lazygit/config.yml) | The author name under `authorColors` |
| [`agents/claude-*`](../agents/) | My Claude Code plugins, settings and skills, including the `jrmatherly-skills` marketplace (`jstack`, `resume`) and the `coding-standards` and `supabase-prompts` skills from my public skills repo. Keep them or drop those lines. Run `claude-config save` once yours are installed and commit the result |
| [`agents/catalog/curated.toml`](../agents/catalog/curated.toml) | Notes on my tools. `claude-catalog` still builds but exits 1 (a warning in setup) for each skill, command or agent you don't have installed. Delete those. An `[mcp.*]` entry you lack, like my `coolify` and `reactive-resume` servers (both on my own domain, so point them at your own hosts or delete them), only prints a `lint:` note, because MCP registration is per machine |
| [`30-packages.toml`](../tilde/.config/mise/conf.d/30-packages.toml), the [modules](modules.md) (`conf.d/60-rotm-*.toml`), and the tools in [`config.toml`](../tilde/.config/mise/config.toml) | My formulae, apps and VS Code extensions. Trim the modules or turn them off before the first run. The `jrmatherly/tap` entries (`claude-multipass` and its app) are my own projects |
| [`settings/registry.toml`](../settings/registry.toml) | `macos.disable_time_machine` and `macos.firewall` default to on, my choice. **If you use Time Machine, run `dotfiles-settings set macos.disable_time_machine off` before `set-defaults`, which otherwise stops all backups.** |
| [`package.json`](../package.json) | The `author` field |
| [`settings/README.md`](../settings/README.md) | The `uv tool install` line names `jrmatherly/returnofthemac` |
| [`setup/README.md`](../setup/README.md) | The `misc` section links my `jrmatherly/skills` repo and names its `jrmatherly-skills` marketplace |
| [`setup/bootstrap-runtime.archify.json`](../setup/bootstrap-runtime.archify.json) | The `meta.repository.url` clone URL (Archify's source for the setup diagram; the exported SVG doesn't show it) |
| [`app/scripts/build-app.sh`](../app/scripts/build-app.sh) | The menu bar app's bundle id, `net.matherly.returnofthemac` (the `APP_BUNDLE_ID` default). Use a reverse-DNS id of your own |
| [`.github/workflows/app-release.yml`](../.github/workflows/app-release.yml) | A pushed `app-v<version>` tag signs the app with my Developer ID (team `7BSA2L4Z5L`) and notarizes it through five repository secrets: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` and `APPLE_API_KEY_P8`. Set your own, or push no `app-v` tags. The DMG goes to the release of that tag on the repository the workflow runs in (`https://github.com/<owner>/<repo>/releases/tag/app-v<version>`), so a fork publishes to its own |
| [`app/Sources/RotmCore/AppUpdate.swift`](../app/Sources/RotmCore/AppUpdate.swift) | Where the menu bar app looks for its own update: the cask `brew-cask:jrmatherly/tap/returnofthemac-app`, that cask's file in my tap (`caskURL`) and my releases page (`releasesURL`). Point all three at your tap and repository, or the app tells your users about my releases |
| [`LICENSE`](../LICENSE) | Add your copyright line; keep the existing ones (MIT requires it) |

[`docs/jstack.md`](jstack.md) and [`docs/gui/raycast.md`](gui/raycast.md) also link my own projects (`jrmatherly/skills`, `jrmatherly/claude-multipass`); they describe tools this setup installs, so keep them unless you drop those tools.
