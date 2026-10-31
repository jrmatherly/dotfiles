# claude-config

`bin/claude-config` keeps this machine's Claude Code setup in the repo: which plugins are installed, the base `settings.json`, and which user skills are installed for which agents. `save` records the machine into three tracked files under `agents/`; `restore` brings a new Mac up to that state. `setup/misc.sh` runs `restore` last, and `upup` runs `restore skills --update` and then `save`.

## Summary

- Run `claude-config save` after installing or removing a plugin or skill, or changing a setting, then review `git diff agents/` and commit. `save` records what this machine has now.
- `save` never shrinks a tracked file whose source is missing on this machine (a Mac that is not set up yet). It warns and keeps the tracked file. Writes go through a temp file and `mv`.
- `restore` adds. Settings already on the machine win, permission lists are unioned, and nothing is rewritten when nothing is missing. The one removal: allow rules listed in `agents/claude-permissions-retired.txt` are dropped by `restore`, `save` and `retire`. Add a rule there when you remove it from `agents/claude-settings.json`, or another Mac keeps it and its next `save` brings it back. `upup` runs `retire`, which only removes, so a pull can't grant anything: new rules wait for a `restore` you run yourself.
- Secrets never land in the tracked settings: credential helpers are dropped, and of `env` only Claude Code's own switches and the variables plugin hooks read (`AZURE_MCP_COLLECT_TELEMETRY`, `HINDSIGHT_API_LLM_PROVIDER` and the `HINDSIGHT_API_*LLM_MODEL` pins) survive.

## Commands

| Command | What it does |
| --- | --- |
| `claude-config save` | Write `agents/claude-plugins.txt`, `agents/claude-settings.json` and `agents/claude-skills.txt` from this machine |
| `claude-config restore` | Add missing marketplaces and plugins, merge the base settings, install missing skills |
| `claude-config restore plugins` / `settings` / `skills` | One part only |
| `claude-config retire` | Drop retired allow rules from this Mac's settings and change nothing else |
| `claude-config restore ... --dry-run` | Print what that part would do |
| `claude-config restore skills --update` | Reinstall each tracked skill whose source changed since install (on GitHub its folder's git tree SHA against `skillFolderHash` in `~/.agents/.skill-lock.json`, one `gh api` call per repository; for a well-known source such as `siderolabs`, the `digest` in the site's `/.well-known/agent-skills/index.json` against `wellKnownDigest`), plus any it can't check, for its listed agents; prints `skill same\|changed\|unknown <name>` per skill (`upup` does this) |

## The three tracked files

| File | Contents | On restore |
| --- | --- | --- |
| `agents/claude-plugins.txt` | `marketplace <name> <source>` lines and `plugin <id>[ disabled]` lines for user-scope plugins | Missing marketplaces are added; missing plugins installed (after a `claude plugin marketplace update <name>` for a marketplace already on the machine, which may predate the plugin); recorded-disabled plugins are disabled only on a fresh install |
| `agents/claude-settings.json` | `~/.claude/settings.json` minus the keys tools own (`enabledPlugins`, `extraKnownMarketplaces`, `hooks`), with `$HOME` written as `~` where it starts a path and permission lists sorted. Never saved: `apiKeyHelper`, `awsCredentialExport`, `awsAuthRefresh`, `otelHeadersHelper`, and any `env` entry other than `CLAUDE_CODE_*` (minus the LLM Router's `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` and `CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT`), `DISABLE_*`, `MAX_*`, `AZURE_MCP_COLLECT_TELEMETRY`, `HINDSIGHT_API_LLM_PROVIDER` and the `HINDSIGHT_API_*LLM_MODEL` pins | Merged into the live file: existing values win, permission lists are unioned, no rewrite when nothing is missing. An invalid merge warns instead of aborting |
| `agents/claude-skills.txt` | `skill <name> <source> <agents>` from `~/.agents/.skill-lock.json`. A `well-known` source is saved as the URL the CLI stored, since its bare host fails as a git clone | `npx skills add <source> -g -s <name> -a <agents> -y` for the agents that lack it, with telemetry off and stdin from `/dev/null` |

Agents map to folders: `claude-code` is `~/.claude/skills`, `codex` is `~/.agents/skills`.

## On a fresh Mac

`setup/misc.sh` runs `claude-config restore` after Claude Code, npm config and PowerShell are in place, then `claude-catalog`. Both steps warn on failure and never abort setup.

## Why not the CLI's own update

`npx skills update` reinstalls every skill with no agent list, so a skill tracked for one agent spreads to all of them. `restore skills --update` reinstalls each skill for exactly the agents the tracked file lists.

## Dependencies

`jq` from Homebrew; `npx` with Node from mise for skills. Reads `~/.claude` (or `$CLAUDE_CONFIG_DIR`) and `~/.agents`.

See also `help claude-catalog` and [`agents/README.md`](../agents/README.md).
