# Online Privacy

1. Install a trustworthy and non-logging [VPN client](https://www.privacyguides.org/en/vpn/#recommended-providers).
1. Use a secure [password manager](https://www.privacyguides.org/en/passwords/#cloud-based). This setup installs 1Password (`1password` and `1password-cli` casks in the Brewfile); see `help gui/1password`.
1. Install a privacy focused [browser](https://www.privacyguides.org/en/desktop-browsers/). (The Brewfile's default browser is Comet, Perplexity's AI browser, which is a convenience choice rather than a privacy one; the settings below apply to whichever browser you use.)
   - Use **HTTPS-only mode**.
   - Use encrypted DNS — **DNS over HTTPS** (Firefox) / **Secure DNS** (Chrome) — only when you're **not** connected to a VPN:
     - Without a VPN, turn it on and choose a trusted [DNS provider](https://www.privacyguides.org/en/dns/#recommended-providers).
     - With a VPN, turn it off. When DNS goes through the VPN tunnel it is already encrypted, so the extra security benefit is negligible, and it's slower than the VPN server's own DNS resolver.
   - Install [ads and trackers blockers](https://www.privacyguides.org/en/browser-extensions/#content-blockers).
   - Change your default search engine to a privacy-friendly [alternative](https://www.privacyguides.org/en/search-engines/#recommended-providers).
1. Install a privacy-focused [messaging app](https://www.privacyguides.org/en/real-time-communication/).
1. Perform a connection check for IP/WebRTC/DNS leaks
   - <https://ipleak.net>
   - <https://browserleaks.com/dns>
   - <https://speed.cloudflare.com>
1. Perform a browser security check against tracking and fingerprinting:
   - <https://coveryourtracks.eff.org>
   - <https://privacytests.org/me.html>

## Telemetry opt-outs (automatic)

- `zsh/env.zsh` exports opt-outs for Next.js, Strapi, Gatsby, Astro, Storybook, Vercel, AWS CDK, GitHub CLI, Azure Developer CLI, CodeGraph, rtk, Azure Functions Core Tools, the .NET CLI, PowerShell, the Azure CLI, the Azure MCP server and Aspire (CLI and dashboard), plus `HOMEBREW_NO_ANALYTICS` and `DO_NOT_TRACK` (the Console Do Not Track convention, honoured by the `skills` CLI, the Sentry CLI, the Supabase CLI, Bun (crash reports) and the impeccable engine (its design-roll choice pings) among others).
- `setup.sh` exports the Microsoft ones, `CODEGRAPH_TELEMETRY` and `RTK_TELEMETRY_DISABLED` for the install run, before `zsh/env.zsh` is ever sourced. `setup/misc.sh` also runs `codegraph telemetry off` and `supabase telemetry disable`, so agents and tools launched outside a shell stay opted out. The live Claude Code settings also carry `AZURE_MCP_COLLECT_TELEMETRY` in `env` (restored from `agents/claude-settings.json`), so the Azure plugin's hooks see it when Claude Code is launched from an app that didn't source the shell.
- Firefox Developer Edition telemetry is turned off in [`firefox/user.js`](../firefox/user.js).
- SnippetsLab (Mac App Store, set up by `setup/misc.sh` when present) collects anonymous usage statistics and crash reports with no opt-out, per its [privacy policy](https://www.renfei.org/snippets-lab/privacy-policy.html); its `lab` CLI and MCP server are local, but snippets an agent reads are sent to that agent's model provider.
- Hindsight coding-agent memory (`bin/hindsight-memory`, installed by `setup/misc.sh`, see `docs/superpowers/specs/completed/2026-10-24-hindsight-memory.md`) is on only in the opt-in paths. Its Stop hook stores each turn's user text, assistant text and one line per tool call (the tool name and the first line of its main input, for Bash the command), never tool results, in a local Postgres under `~/.pg0`. Memory extraction calls go to Anthropic through the `claude` CLI on the subscription (`HINDSIGHT_API_LLM_PROVIDER=claude-code` in `tilde/.zshenv` and in the Claude Code settings `env`), the same place the conversation already went. The `sensitive_data` redact rule matches 46 bundled patterns (API keys, database URLs, PEM private keys, JWTs, card and US SSN shapes), not passwords or opaque tokens, and never rescans stored memories. The codebase survey is off by default because it runs a `claude -p` agent with Read over the repo, untracked `.env` files included (it samples rather than reads everything); `hindsight-memory survey on` enables it per machine. The vendor docs name no telemetry. Each `hindsight-api` build the daemon runs holds about 1.9 GB in the uv cache (`du -sh ~/.cache/uv/archive-v0/*`; 1.1.0 has four builds there today).
- No shell exports the GitHub CLI token (`GITHUB_TOKEN`, `GIGET_AUTH`): every child process, agents included, would inherit a `repo` + `workflow` token. A tool that needs it gets it per command, e.g. `GIGET_AUTH=$(gh auth token) giget …`.
