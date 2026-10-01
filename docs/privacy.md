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

- `zsh/env.zsh` exports opt-outs for Next.js, Strapi, Gatsby, Astro, Storybook, Vercel, AWS CDK, GitHub CLI, Azure Developer CLI, CodeGraph, Azure Functions Core Tools, the .NET CLI, PowerShell, the Azure CLI and Aspire (CLI and dashboard), plus `HOMEBREW_NO_ANALYTICS` and `DO_NOT_TRACK` (the Console Do Not Track convention, honoured by the `skills` CLI among others).
- `setup.sh` exports the Microsoft ones and `CODEGRAPH_TELEMETRY` for the install run, before `zsh/env.zsh` is ever sourced. `setup/misc.sh` also runs `codegraph telemetry off`, so agents launched outside a shell stay opted out.
- Firefox Developer Edition telemetry is turned off in [`firefox/user.js`](../firefox/user.js).
