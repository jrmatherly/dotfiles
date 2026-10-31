---
paths:
  - 'bin/hindsight-memory'
  - 'bin/lib/test-hindsight-memory'
---

# hindsight-memory

Runtime behavior is in the global rule `tilde/.claude/rules/hindsight.md`. Design, privacy and measured costs: `docs/superpowers/specs/completed/2026-10-24-hindsight-memory.md`. These are the constraints the code doesn't show.

- The two pins at the top of the script, `CODING_AGENTS_VERSION` and `EMBED_VERSION`, are the only places versions appear.
- `merge_defaults` is additive and the file is never tracked. Existing keys win, except `embedVersion`, which follows the pin, and a `pageTriggerCron` still at the old default `0 6 * * *`.
- The newer-release check uses `npm pack --dry-run --json`, because `npm view` ignores `min-release-age` and named 0.8.3 a week before the pin could install it (checked 2026-10-29).
- Paths are stored as typed, with `$HOME` written as `~` and no `realpath`, because the plugin expands only `~` and tests a literal prefix. `"~${p#"$HOME"}"` is deliberate: bash 3.2 prints a literal backslash for `${p/#$HOME/\~}`.
- `uninstall` moves the config to `coding-agent.json.uninstalled`, which `init` restores, because `upup` keys the step on the config's presence and a kept config would reinstall the hooks.
- The provider is pinned where the hooks read it, in `tilde/.zshenv` (terminals) and `env` of `agents/claude-settings.json` (app-launched Claude Code), because the daemon starter re-detects it from the hook's environment and rewrites the profile on every cold start.
- The models are pinned the same way, because the provider's own default (`claude-sonnet-4-5-20250929`) retires on 2026-11-30 and the starter forwards every `HINDSIGHT_API_*` variable.
