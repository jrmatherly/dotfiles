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
| Models (added 2026-10-24, afternoon) | `claude-haiku-5-5` for extraction and consolidation, `claude-sonnet-5-5` for reflect and the knowledge-page refresh. The provider's default `claude-sonnet-4-5-20250929` was deprecated on 2026-09-30 and retires on 2026-11-30 ([deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations)); Haiku 4.5 is past its retirement floor. Retain and consolidation were 184 of the first day's 187 slow calls, so they take the lightest model; reflect is the output a person reads. Both ids verified through `claude -p --model` on this subscription. Pinned as `HINDSIGHT_API_LLM_MODEL`, `HINDSIGHT_API_RETAIN_LLM_MODEL` and `HINDSIGHT_API_CONSOLIDATION_LLM_MODEL` in the same two places as the provider, since `daemonEnv()` forwards every `HINDSIGHT_API_*` variable. |
| Tool guide | `toolGuideExtra` carries one verify-first sentence, read by the Claude Code and Codex hooks and the MCP server, so the stance in `tilde/.claude/rules/hindsight.md` reaches Codex sessions too. |

## What was verified

- **The installer is real and scripted.** `npx -y @vectorize-io/hindsight-coding-agents --help` prints `install <all|harness...> [--server cloud|self-hosted|daemon]`, lists `claude-code` and `codex` as harnesses, and aborts without a target. Published version 0.8.2 on 2026-10-19. Running `install --help` already stages the runtime at `~/.hindsight/coding-agents` (16 MB), so that directory now exists here.
- **The daemon runs on this Mac with the subscription provider.** `HINDSIGHT_API_LLM_PROVIDER=claude-code uvx hindsight-embed@latest daemon start` started `hindsight-api 1.1.0` on port 8888 in 19 s with packages cached. One `memory retain` took 20 s and extracted the fact "User's dotfiles repository gate is pnpm check, and commits go straight to main under standing approval". `memory recall` returned it in under a second. `daemon stop` waited for the in-flight extraction and then exited. The log line is `Claude Code: Using Claude Agent SDK (authentication via claude auth login)`, followed by the vendor's warning about automated calls on a subscription.
- **No Rust build happened.** The docs say macOS compiles `litellm` from source and needs `rustc`. On Python 3.13 and arm64, uv downloaded `litellm` as a wheel. The staged uv environment is the vendor's stated 1.5 GB per version. `~/.pg0` is 85 MB after one memory.
- **The `hindsight` CLI got installed as a side effect.** The first `hindsight-embed` run fetched `https://hindsight.vectorize.io/get-cli` and wrote `~/.local/bin/hindsight` (1.1.0, arm64 Mach-O). The hook package does not need it. It stays because `hindsight-embed memory …` forwards to it.
- **Hook shape.** `dist/installer.js` registers `SessionStart` (30 s), `UserPromptSubmit` (30 s) and `Stop` (60 s), each `node dist/claude-…-hook.js` or `dist/codex-…-hook.js`. Every hook returns at once when `HINDSIGHT_DISABLE_HOOKS=1` or the config has `disabled: true`. The companion skill `hindsight-coding-agent` is 80 KB and model-invoked. The package also registers an MCP server `hindsight` (`node dist/mcp-server.js`) at user scope.
- **Existing hooks it will sit beside.** `~/.claude/settings.json` already has NotchBar's hook on every event plus `rtk hook claude` on PreToolUse and `codegraph prompt-hook` on UserPromptSubmit. `~/.codex/config.toml` already has `codex_hooks = true` (NotchBar wrote it, and the tracked copy has it too), which the Codex install needs.
- **This machine today.** uv 0.13.5 and node through mise, Codex CLI, OrbStack, the 1Password CLI. No Ollama, no Amp, no LLM API key in the environment or `~/.zsh.local`. rustup 1.99 lives in `~/.cargo/bin`, but the mise `rust` shim has no version set, so `rustc` is not on PATH.

## How the hook package behaves

From `sdks/integrations/coding-agents.md` in the installed `hindsight-docs` skill.

- **One bank per repository**, named `coding-agent::{gitProject}`, shared by Claude Code and Codex and by every worktree of the repo. Outside a git repo the bank is the basename of the directory the session started in.
- **Session start** picks the bank, seeds it in the background from the agent's past transcripts in that repo and up to 300 commit messages, and on a cold repo runs a headless codebase survey with `claude -p --model haiku --max-budget-usd 2`, repeated every 20 commits.
- **First prompt** injects one low-budget reflect over the bank, once per session, within a 20 s budget with a fallback to page search and then recall.
- **Every reply** appends the new turns to a per-session document (user text, assistant text, and one line per tool call made of the tool name and the first line of its main input, for Bash the command; tool results are not stored), extracted server-side in `concise` mode. Facts consolidate into one set of beliefs per repo and feed five seeded knowledge pages that refresh hourly when something changed.
- **Mid-task** the agent has MCP tools `hindsight_search_knowledge_pages`, `hindsight_list_knowledge_pages`, `hindsight_read_knowledge_page`, `hindsight_reflect`, `hindsight_capture_initiative`, `hindsight_ingest_document`, `hindsight_sync_status` and `hindsight_diagnose`.
- **Configuration is one file**, `~/.hindsight/coding-agent.json`. `optInOnly: true` plus `optInPaths` makes every repo outside the listed prefixes inert, with no bank created. `banks.<id>.disabled` blacklists one repo. `defaultBankConfig` carries bank-config fields into every bank the plugin creates, which is where memory defence goes.
- **Daemon mode** starts `hindsight-embed` on demand, adopts a server already on the port, never stops it on exit, and picks the extraction LLM as `HINDSIGHT_API_LLM_PROVIDER` if set, else the first of `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, else the Claude Code CLI.
- **Updates.** `autoUpdate` is on by default and re-stages the runtime from npm once a day (`maybeAutoUpdate` returns before contacting npm when it is off). Re-running `install` is the documented update that also rewires new hooks. `uninstall` removes exactly what it added, and `install` backs up each touched file as `<file>.hindsight-backup`.
- **Logs** in `~/.hindsight/coding-agents-logs/` (`plugin.log`, `diag.jsonl`, `usage.jsonl`). `npx @vectorize-io/hindsight-coding-agents stats` summarises tool use per agent.

## Design

- **Install through the vendor's installer at a pinned version, from `setup/misc.sh`, guarded like the other optional tools.** `npx -y @vectorize-io/hindsight-coding-agents@0.8.2 install claude-code codex --server daemon` when `~/.hindsight/coding-agent.json` is missing. The two versions (`0.8.2` for the package, `1.1.0` for `hindsight-embed`) are constants in `bin/hindsight-memory`; this code runs on every prompt, so a new release is a reviewed bump, not something `npx -y` picks up on its own. The installer writes only `serverMode` into the config, so a re-run keeps every other key. The installer owns the hooks in `~/.claude/settings.json`, the `[mcp_servers]` entry in `~/.codex/config.toml` and the user-scope MCP registration. `claude-config save` already drops `hooks` and never tracks `~/.claude.json`, so nothing of it lands in the repo by accident.
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

  Plus `"embedVersion": "1.1.0"`, `"codebaseSurvey": false`, `"autoInject": "pages"`, `"pageTriggerCron": "H */6 * * *"` and `"pageRefreshEveryTurns": 10`. `autoUpdate` is off because `upup` is this repo's one upgrade path. The survey is off because it runs `claude -p` with Read over the whole repo, untracked `.env` included, on the subscription; `hindsight-memory survey on` enables it. The first prompt gets the knowledge pages matching it (retrieval only, 7 s budget) instead of a reflect, see Latency and quota. Pages refresh every six hours at a per-page hashed minute (`H`, the vendor's Jenkins-style spread, so five pages don't queue on the same worker pool as retain), and a tick with nothing new is skipped server-side; the vendor default is hourly, the earlier `0 6 * * *` left pages up to 24 h stale and fired all of them at once. A roster every ten turns cuts the per-turn re-injection. Memory defence is the server's 45-pattern secret and PII scrubber, off by default; `redact` keeps the memory while dropping the key-shaped string, and it does not catch passwords or opaque tokens.

- **Management is one `bin/` script.** `hindsight-memory paths list|add <dir>|remove <dir>` edits `optInPaths` with jq, writing through a temp file. Paths are stored as typed with the trailing slash stripped and a true `$HOME` prefix collapsed to `~`, no `realpath`, because the plugin expands only `~` and `~/` and tests a literal prefix. `on|off` flips `disabled`, the kill switch every hook checks. `survey on|off` flips `codebaseSurvey`. `status` wraps the `coding-agent` profile's `daemon status`, the config summary, the last 24 h of model calls per bank and model from the daemon's `llm-requests` endpoint (the profile log names a scope only for calls over 10 s, so it undercounts), and the tail of `plugin.log`. `uninstall` runs the vendor's `uninstall all` and stops the daemon. `upgrade` re-runs the pinned installer and reports a newer npm release as a notice. The script has a self-check against a fixture `HOME`, like `bin/lib/test-claude-desktop-account`.
- **The provider is explicit, twice.** `tilde/.zshenv` exports `HINDSIGHT_API_LLM_PROVIDER=claude-code` (not `zsh/env.zsh`, which only interactive shells read), and `env` in `agents/claude-settings.json` carries the same value, which Claude Code applies to its process and so to every hook it spawns. The plan's first draft persisted it in the daemon profile instead; review of `dist/daemon-start.js` 0.8.2 showed `daemonEnv()` re-detecting the provider from the hook's environment and `configureProfile()` rewriting the profile with `--merge --env HINDSIGHT_API_LLM_PROVIDER=<detected>` on every cold start, so a profile pin is overwritten and the hook's environment is the only input. Without either, the plugin picks the first of `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY` in the hook's environment and only then the `claude` CLI, and a running daemon is adopted rather than restarted, so the first session of the day would decide billing. A bare `hindsight-embed` with no provider refuses to start (`LLM API key is required`).
- **Upgrades in `upup`.** A `Hindsight memory` step runs `hindsight-memory upgrade`, which re-runs the pinned installer (the vendor's update path, which also re-wires new hook entry points) and reports a newer release on npm as a notice. The bump itself is a commit. Skipped when the config file is absent.
- **The memory skills go.** `hindsight-local` and `hindsight-self-hosted` are removed from `agents/claude-skills.txt` and uninstalled. Both describe themselves as "use to remember", so the model would pick one at random. `hindsight-local` writes to the default daemon profile (port 8888, bank `default`) and `hindsight-self-hosted` to a server and bank the user types in; neither is the per-repo bank the hooks use (port 9077, profile `coding-agent`), so memory would split. The package's own `hindsight-coding-agent` skill covers "remember this in hindsight". `hindsight-docs` and `hindsight-architect` stay.
- **Nothing for Amp or Claude Desktop.** Amp is not installed and has no documented integration. Claude Desktop only has a raw MCP route and it is not needed for coding memory.

## Risks and what to watch

- **Terms of service.** The vendor's docs and the daemon's own startup log say the `claude-code` provider runs automated model calls on a personal subscription, for local personal use only, and that Anthropic's terms may change. Every retain, consolidation, page refresh and codebase survey spends subscription quota. If that becomes a problem, the switch is `HINDSIGHT_API_LLM_PROVIDER=anthropic` plus a key in `~/.zsh.local` through a 1Password reference, the pattern `upup` already uses for `DOTFILES_MAC_PASSWORD_OP`.
- **Latency and quota.** One retain took 20 s through the CLI (`retain_extract_facts` 18.6 s, `consolidation` 13.1 s in the profile log, both on `claude-sonnet-4-5-20250929`). With the defaults above, an active repo costs roughly one extraction per reply, one consolidation per batch, one low-budget reflect per session and five page refreshes a day. `hindsight-memory status` prints the day's count from the profile log so the spend is visible. The `Stop` hook has a 60 s window and the retain itself is server-side, so the hook returns early, but a slow extraction queue delays what the next session sees. The first-prompt reflect has a 20 s budget and falls back to retrieval. Measured on the first day: it timed out in 3 of 3 sessions on Sonnet 4.5 (single calls took 11 to 15 s, a reflect needs several), the server cancelled each after 20 to 25 s on disconnect, and the fallback page search returned five empty pages because their only refresh ran before consolidation had produced anything. `autoInject` stayed on `reflect` until three session starts on the new models showed whether it fits the window. They did not: on 2026-10-24 all five dotfiles starts timed out at 20 s on Sonnet 5.5, with the synthesis call alone at 20.8 to 28.9 s after three or four 2.5 to 7 s tool calls, and the fallback page search then answered in 37 to 49 ms. So `autoInject` is `pages`: the same pages, without the 20 s wait and the discarded Sonnet calls. Raising `reflectTimeoutMs` was rejected because the installer rewrites the host hook timeout to 30 s on every `upup`, the server's per-call reflect timeout is 30 s, and a session start would stall about 45 s. Across the first day the 187 slow calls averaged 92 s (consolidation) and 101 s (retain), most of it the one-time history import.
- **Disk.** 1.5 GB of uv cache per `hindsight-embed` version. `uv cache prune` reclaims old ones. The embedded Postgres grows with memories.
- **Transcript contents.** Every reply's turns are stored in the local database, including the first line of each tool input, so a token pasted into a prompt or passed on a command line lands in Postgres. The opt-in list is the privacy switch and it gates the Stop hook and the seed on the session's working directory, so a mid-session `cd` changes nothing. Memory defence redacts key-shaped strings on retain and does not rescan existing memories.
- **GUI-launched sessions.** Hooks need `node`, `npx`, `uv` and `claude` on PATH. `tilde/.zprofile` puts mise shims on PATH for GUI apps, which should cover it. Verify from a Claude Desktop-launched Claude Code once.
- **Docs disagree with themselves** on the embed config path and on the daemon's idle timeout. The hook package's own table says the daemon never exits on its own, and that is what the prototype showed.

## Alternatives rejected

| Alternative | Why not |
| --- | --- |
| Skills only (`hindsight-local`) | Model-invoked, so nothing is stored unless the agent decides to. No git seeding, no knowledge pages, no sharing between agents. |
| Self-hosted in OrbStack | Avoids nothing the daemon needs (the Rust build did not happen) and adds a 3.7 GB image and a container to keep running. |
| Hindsight Cloud | Transcripts and git history leave the machine, and it costs credits. |
| Anthropic API key | The vendor's recommendation and the fallback if the subscription route stops working, but it meters every extraction. The user chose the subscription route knowing the caveat. |
| Letting `npx -y` and `autoUpdate` float to the latest release | Hook code that runs on every prompt should change through a reviewed bump, not a background fetch. |
| Tracking `coding-agent.json` as a symlink under `tilde/` | The installer writes it, and `optInPaths` is machine-local state. Defaults merged by a script keep the repo's intent without fighting the installer. |
