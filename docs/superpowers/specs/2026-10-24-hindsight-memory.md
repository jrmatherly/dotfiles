# Hindsight memory for the coding assistants

Findings and the recommended design for giving Claude Code and Codex long-term, per-repo memory through [Hindsight](https://github.com/vectorize-io/hindsight), run locally on this Mac. The plan that implements it is `docs/superpowers/plans/2026-10-24-hindsight-memory.md`.

## Decisions taken on 2026-10-24

Asked and answered in the session that produced this spec.

| Question | Decision |
| --- | --- |
| Integration route | The vendor's hook package `@vectorize-io/hindsight-coding-agents` (0.8.2). Automatic recall at session start and retain on every reply. The vendor retired its per-agent plugins in favour of it. |
| Where memory lives | A local `hindsight-embed` daemon on `127.0.0.1:9077`, embedded Postgres under `~/.pg0`. Nothing leaves the machine. |
| Extraction LLM | The `claude-code` provider, which drives the `claude` CLI on the Claude Pro/Max subscription. No API key. The terms-of-service caveat below was read before choosing. |
| Scope | Opt-in paths only (`optInOnly`), both Claude Code and Codex, with a command to add and remove paths. |

## What was verified

- **The installer is real and scripted.** `npx -y @vectorize-io/hindsight-coding-agents --help` prints `install <all|harness...> [--server cloud|self-hosted|daemon]`, lists `claude-code` and `codex` as harnesses, and aborts without a target. Published version 0.8.2 on 2026-10-19. Running `install --help` already stages the runtime at `~/.hindsight/coding-agents` (16 MB), so that directory now exists here.
- **The daemon runs on this Mac with the subscription provider.** `HINDSIGHT_API_LLM_PROVIDER=claude-code uvx hindsight-embed@latest daemon start` started `hindsight-api 1.1.0` on port 8888 in 19 s with packages cached. One `memory retain` took 20 s and extracted the fact "User's dotfiles repository gate is pnpm check, and commits go straight to main under standing approval". `memory recall` returned it in under a second. `daemon stop` waited for the in-flight extraction and then exited. The log line is `Claude Code: Using Claude Agent SDK (authentication via claude auth login)`, followed by the vendor's warning about automated calls on a subscription.
- **No Rust build happened.** The docs say macOS compiles `litellm` from source and needs `rustc`. On Python 3.13 and arm64, uv downloaded `litellm` as a wheel. The staged uv environment is the vendor's stated 1.5 GB per version. `~/.pg0` is 85 MB after one memory.
- **The `hindsight` CLI got installed as a side effect.** The first `hindsight-embed` run fetched `https://hindsight.vectorize.io/get-cli` and wrote `~/.local/bin/hindsight` (1.1.0, arm64 Mach-O). The hook package does not need it. It stays because `hindsight-embed memory …` forwards to it.
- **Hook shape.** The runtime's `hooks/hooks.json` registers `SessionStart` (30 s), `UserPromptSubmit` (30 s) and `Stop` (60 s), each `node dist/<harness>-…-hook.js`. The companion skill `hindsight-coding-agent` is 80 KB and model-invoked. The package also registers an MCP server `hindsight` (`node dist/mcp-server.js`) at user scope.
- **Existing hooks it will sit beside.** `~/.claude/settings.json` already has NotchBar's hook on every event plus `rtk hook claude` on PreToolUse and `codegraph prompt-hook` on UserPromptSubmit. `~/.codex/config.toml` already has `codex_hooks = true` (NotchBar wrote it, and the tracked copy has it too), which the Codex install needs.
- **This machine today.** uv 0.13.5 and node through mise, Codex CLI, OrbStack, the 1Password CLI. No Ollama, no Amp, no LLM API key in the environment or `~/.zsh.local`. rustup 1.99 lives in `~/.cargo/bin`, but the mise `rust` shim has no version set, so `rustc` is not on PATH.

## How the hook package behaves

From `sdks/integrations/coding-agents.md` in the installed `hindsight-docs` skill.

- **One bank per repository**, named `coding-agent::{gitProject}`, shared by Claude Code and Codex and by every worktree of the repo. Outside a git repo the bank is the basename of the directory the session started in.
- **Session start** picks the bank, seeds it in the background from the agent's past transcripts in that repo and the last 300 commit messages, and on a cold repo runs a headless codebase survey with `claude -p --model haiku --max-budget-usd 2`, repeated every 20 commits.
- **First prompt** injects one low-budget reflect over the bank, once per session, within a 20 s budget with a fallback to page search and then recall.
- **Every reply** appends the new turns to a per-session document, extracted server-side in `concise` mode. Facts consolidate into one set of beliefs per repo and feed five seeded knowledge pages that refresh hourly when something changed.
- **Mid-task** the agent has MCP tools `hindsight_search_knowledge_pages`, `hindsight_read_knowledge_page`, `hindsight_reflect`, `capture_initiative` and `hindsight_sync_status`.
- **Configuration is one file**, `~/.hindsight/coding-agent.json`. `optInOnly: true` plus `optInPaths` makes every repo outside the listed prefixes inert, with no bank created. `banks.<id>.disabled` blacklists one repo. `defaultBankConfig` carries bank-config fields into every bank the plugin creates, which is where memory defence goes.
- **Daemon mode** starts `hindsight-embed` on demand, adopts a server already on the port, never stops it on exit, and picks the extraction LLM as `HINDSIGHT_API_LLM_PROVIDER` if set, else the first of `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, else the Claude Code CLI.
- **Updates.** `autoUpdate` is on by default and re-stages the runtime from npm once a day. Re-running `install` is the documented update that also rewires new hooks. `uninstall` removes exactly what it added, and `install` backs up each touched file as `<file>.hindsight-backup`.
- **Logs** in `~/.hindsight/coding-agents-logs/` (`plugin.log`, `diag.jsonl`, `usage.jsonl`). `npx @vectorize-io/hindsight-coding-agents stats` summarises tool use per agent.

## Design

- **Install through the vendor's installer, from `setup/misc.sh`, guarded like the other optional tools.** `npx -y @vectorize-io/hindsight-coding-agents install claude-code codex --server daemon` when `~/.hindsight/coding-agent.json` is missing. The installer owns the hooks in `~/.claude/settings.json`, the `[mcp_servers]` entry in `~/.codex/config.toml` and the user-scope MCP registration. `claude-config save` already drops `hooks` and never tracks `~/.claude.json`, so nothing of it lands in the repo by accident.
- **One tracked default config, merged additively.** A `bin/hindsight-memory init` subcommand writes the defaults below into `coding-agent.json` only where a key is missing, so a hand edit survives a re-run, the same rule `claude-config restore settings` follows.

  ```json
  {
    "serverMode": "daemon",
    "optInOnly": true,
    "optInPaths": ["~/dev"],
    "autoUpdate": false,
    "defaultBankConfig": {
      "memory_defense": {
        "enabled": true,
        "rules": [{ "on": "sensitive_data", "action": "redact" }]
      }
    }
  }
  ```

  `autoUpdate` is off because `upup` is this repo's one upgrade path. Memory defence is the server's 45-pattern secret and PII scrubber, off by default, and `redact` keeps the memory while dropping the secret.

- **Path management is a `bin/` script.** `hindsight-memory paths list|add <dir>|remove <dir>` edits `optInPaths` with jq, writing through a temp file. Paths are stored as typed, with `$HOME` collapsed to `~`, because the plugin expands `~` itself. `hindsight-memory status` wraps `daemon status`, the sync status and the tail of `plugin.log`. The script has a self-check against a fixture `HOME`, like `bin/lib/test-claude-desktop-account`.
- **The provider is explicit.** `zsh/env.zsh` exports `HINDSIGHT_API_LLM_PROVIDER=claude-code`, so a future API key in the environment cannot silently switch the daemon to metered billing. The daemon falls back to the same provider when the variable is absent, which covers hooks started from a GUI-launched Claude Code.
- **Upgrades in `upup`.** A `Hindsight memory` step re-runs the same `install` command (the vendor's update path, which also re-wires new hook entry points), skipped when the config file is absent.
- **The memory skills go.** `hindsight-local` and `hindsight-self-hosted` are removed from `agents/claude-skills.txt` and uninstalled. Both describe themselves as "use to remember", so the model would pick one at random, and both write to a different daemon profile (port 8888, bank `default`) than the hooks (port 9077, bank per repo), splitting memory in two. The package's own `hindsight-coding-agent` skill covers "remember this in hindsight". `hindsight-docs` and `hindsight-architect` stay.
- **Nothing for Amp or Claude Desktop.** Amp is not installed and has no documented integration. Claude Desktop only has a raw MCP route and it is not needed for coding memory.

## Risks and what to watch

- **Terms of service.** The vendor's docs and the daemon's own startup log say the `claude-code` provider runs automated model calls on a personal subscription, for local personal use only, and that Anthropic's terms may change. Every retain, consolidation, page refresh and codebase survey spends subscription quota. If that becomes a problem, the switch is `HINDSIGHT_API_LLM_PROVIDER=anthropic` plus a key in `~/.zsh.local` through a 1Password reference, the pattern `upup` already uses for `DOTFILES_MAC_PASSWORD_OP`.
- **Latency.** One retain took 20 s through the CLI. The `Stop` hook has a 60 s window and the retain itself is server-side, so the hook returns early, but a slow extraction queue delays what the next session sees. The first-prompt reflect has a 20 s budget and falls back to retrieval.
- **Disk.** 1.5 GB of uv cache per `hindsight-embed` version. `uv cache prune` reclaims old ones. The embedded Postgres grows with memories.
- **Transcript contents.** Every reply's turns are stored in the local database. The opt-in list is the privacy switch. Memory defence redacts secret-shaped strings on retain but does not rescan existing memories.
- **GUI-launched sessions.** Hooks need `node`, `npx` and `uv` on PATH. `tilde/.zprofile` puts mise shims on PATH for GUI apps, which should cover it. Verify from a Claude Desktop-launched Claude Code once.
- **Docs disagree with themselves** on the embed config path and on the daemon's idle timeout. The hook package's own table says the daemon never exits on its own, and that is what the prototype showed.

## Alternatives rejected

| Alternative | Why not |
| --- | --- |
| Skills only (`hindsight-local`) | Model-invoked, so nothing is stored unless the agent decides to. No git seeding, no knowledge pages, no sharing between agents. |
| Self-hosted in OrbStack | Avoids nothing the daemon needs (the Rust build did not happen) and adds a 3.7 GB image and a container to keep running. |
| Hindsight Cloud | Transcripts and git history leave the machine, and it costs credits. |
| Anthropic API key | The vendor's recommendation and the fallback if the subscription route stops working, but it meters every extraction. The user chose the subscription route knowing the caveat. |
| Tracking `coding-agent.json` as a symlink under `tilde/` | The installer writes it, and `optInPaths` is machine-local state. Defaults merged by a script keep the repo's intent without fighting the installer. |
