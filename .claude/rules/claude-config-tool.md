---
paths:
  - 'bin/claude-config'
  - 'bin/lib/test-claude-config'
  - 'agents/claude-*'
---

# claude-config

`docs/claude-config.md` is the user guide and `bin/claude-config` the source. These are the constraints the code doesn't show.

- `save` never shrinks a tracked file: a missing or unparsable source warns and keeps it, and writes go through `.tmp` + `mv`.
- `save` drops the keys other tools own and the credential helpers, and of `env` keeps only the allowlist in `settings_filter`, because `env` is where API keys go and the saved file is committed. `MAX_THINKING_TOKENS` is kept and `CLAUDE_CODE_OAUTH_TOKEN` is not.
- Two `CLAUDE_CODE_*` switches stay out: the LLM Router adds them whenever a provider exists and never removes them from a real settings file, and `restore` never deletes a key, so tracking them would hand a gateway profile to a Mac with no router.
- `$HOME` becomes `~` only where it starts a path, and `//$HOME/` (Claude's absolute-path rule syntax) becomes `~/`.
- A `well-known` skill source is written as the URL the CLI stored (`sourceBaseUrl`), since its bare-host `source` fails as a git clone.
- `restore` merges with existing values winning and permission lists unioned, so it never deletes a local rule. To remove a rule from every Mac, add it to `agents/claude-permissions-retired.txt` in the same commit that removes it from `agents/claude-settings.json`. `save`, `restore` and `retire` drop those from `permissions.allow`. `upup` runs only `retire`, so a pull can't add a grant.
- A marketplace already on the machine may predate a plugin, so `restore` refreshes it once before the first install from it.
- `restore skills --update` exists because the CLI's own `skills update` reinstalls with no agent list, so a skill tracked for one agent would spread to all.
- `setup/misc.sh` runs `restore` last, so `npx skills` runs with the npm settings. The `jrmatherly/skills` marketplace is public, so no credential is needed.
