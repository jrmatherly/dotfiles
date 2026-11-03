# Project skill stack: our variation of AAS Core

Status: proposed, 2026-11-02. Plan: `docs/superpowers/plans/2026-11-02-project-skill-stack.md`.

## The decision

Build `claude-stack`, a per-project selector over the tools already installed, on top of `claude-catalog`. Do not install AAS Core, its MCP server or its catalog.

Our problem is the opposite of the one AAS solves. AAS helps a project find skills it lacks among about 2,900. We already have 612 tools loaded in every repo, and that excess is what hurts: it costs context on every request and pushes most skill descriptions out of the listing.

## What AAS Core is

Read from the docs and from the 19.15.0 package, with REA over `tools/lib/aas-v1`.

- **It does not choose.** The docs say the MCP "does not scan the repository and does not decide which skills are best". `search.js` returns matches in catalog order with no score. The tool descriptions and `AGENT_SELECTION_CONTRACT` tell the model how to choose. Core validates IDs and structure, then records the result as `aas-stack.json`.
- **The MCP path is closed.** REA found no child-process, request or configuration relations in the six files of the server path (static analysis, 56 other files out of scope). A grep of the same core files for `child_process`, `fetch`, `process.cwd` and `readdir` found nothing.
- **The categorization doc is a keyword bucketer.** `auto_categorize_skills.py` matches names and descriptions against keyword lists, with exact matches scoring 2x partial ones. The result in 19.15.0 is 114 categories over 2,743 skills.
- **The doc's install command fails today.** The docs and the repo's `package.json` pin 20.4.0, but npm returned 404 for that version on 2026-11-02. npm `latest` is 19.15.0.
- **The content is a large unaudited pool.** The 19.15.0 index declares `risk: critical` on 1,351 skills and `offensive` on 146, and 1,486 have source `community`.

## What we measured

Machine: this Mac, Claude Code 2.1.317, 62 of 66 plugins enabled at user scope. All tokens are the context size of a first `claude -p` request (input + cache creation + cache read).

| Measure | All plugins | 25 domain plugins off via `settings.local.json` |
| --- | --- | --- |
| Context tokens (3 runs) | 78,023 / 78,025 / 78,025 | 53,283 / 53,283 (see note) |
| Skills / agents / tools | 325 / 200 / 606 | 202 / 36 / 440 |
| Listed skills keeping a description (model-reported, so approximate) | 63 of 283 | 84 of 157 |

Note: the first narrow run read 51,568 because the claude.ai connector had not loaded (429 tools). It was excluded. Saving: 24,742 tokens, 32%. The catalog's `cost` figures predicted 31,964 for this set, so they overstate real savings by about 1.3x.

- **Precedence works.** `false` in `.claude/settings.local.json` overrides the user scope, as `settings-reference` documents.
- **Worktrees inherit it.** A fresh `git worktree` with no local file of its own still loaded 202 skills and about 53.7k tokens.
- **Plugin skills cannot be filtered one by one.** `skillOverrides` does not apply to plugin skills (`skills.md`). The plugin is the unit.
- **The rule file does not reach sibling worktrees.** A gitignored `.claude/rules/` file loaded in the main checkout but not in a worktree (sentinel test: `PELICAN-7` versus `NONE`). So a worktree gets the narrowed plugins without the note naming them. Accepted as a known limit.
- **Domain plugins are rarely used.** Across 7 repos with 716 sessions, the 23 selectable plugins showed up in 2 repo and plugin pairs, both in `home-cluster`: `cloudflare` 49 times and `redis-development` 2 times (Skill, Agent and MCP tool calls, plus typed slash commands, subagent transcripts included). Outside that set, `voltagent-qa-sec` was used once in `ai-kb`. It owns a curated pick, so it stays core.
- **A signal sketch held up.** On 8 real repos, tracked paths and dependency manifests selected these keep sets with no false drop once repo history counts as a keep signal:

| Repo | Sessions | Kept beyond core | Off | Estimated saving |
| --- | --- | --- | --- | --- |
| `dotfiles` | 149 | `voltagent-lang` | 22 of 23 | 29,091 |
| `claude-multipass` | 41 | `voltagent-lang` | 22 of 23 | 29,091 |
| `skills` | 6 | `voltagent-lang`, `voltagent-core-dev` | 21 of 23 | 28,283 |
| `llm-router` | 92 | `voltagent-lang`, `core-dev`, `infra`, `data-ai` | 19 of 23 | 26,506 |
| `home-cluster` | 154 | `cloudflare`, `redis-development` (history only), `voltagent-lang`, `infra` | 19 of 23 | 25,584 |
| `serviceradar` | 99 | `redis-development`, `voltagent-lang`, `core-dev`, `infra`, `data-ai` | 18 of 23 | 25,020 |
| `reactive-resume` | 0 | `cloudflare`, `redis-development`, `voltagent-lang`, `core-dev`, `infra`, `data-ai` | 17 of 23 | 23,987 |
| `ai-kb` | 175 | `qdrant-skills`, `redis-development`, `sentry`, `sentry-cli`, `voltagent-lang`, `core-dev`, `infra`, `data-ai` | 15 of 23 | 21,566 |

The saving column uses catalog estimates, so expect about 75% of it in practice. These numbers come from a throwaway sketch run with `langfuse-observability` still in the set. Dropping it changes only the off count, because it costs 0 tokens. Not measured: whether a narrower listing makes skills fire more accurately. The final plan task records the real token number for one repo.

## What we take from AAS, and what we leave

| AAS idea | Verdict | Why |
| --- | --- | --- |
| The agent judges, a tool validates and records | Take | Deterministic evidence plus model judgment, with no ranking engine to maintain |
| Ten capability dimensions, with `n/a` marked rather than skipped | Take | A short checklist that stops the model stopping at its first match |
| Report catalog gaps explicitly | Take | A gap is the only honest trigger for looking outside what we have |
| Durable manifest of the selection | Take, small | `.claude/skill-stack.json` explains each choice and lets `reset` undo exactly what it wrote |
| Preview before change | Take | `scan` writes nothing and `apply` is separate |
| Local MCP server, approval digests, content-addressed runtime | Leave | They protect an external download we are not doing |
| Immutable plan, journal, recovery | Leave | Our only write is one gitignored JSON key, and AAS itself marks apply and recovery as experimental |
| Keyword auto-categorization | Leave | 23 selectable plugins are classified by hand once in `curated.toml`, and `lint` catches drift |
| Install from the 2,900-skill pool | Leave | Unaudited, and nothing has shown a need. Revisit when real gap reports accumulate |

## Design

**Unit of selection.** One install key such as `cloudflare@claude-plugins-official`. Only plugins named in `[stack.signals]` in `curated.toml` are selectable. Everything else is core and stays on, so a newly installed plugin is safe by default.

**Keep rule.** A selectable plugin stays on if a path signal, a dependency signal, repo history or a sticky `--keep` says so. Otherwise it goes off. A plugin that owns a curated `pick` cannot be selectable, because the catalog tells the model to use it. `lint` enforces this. A hooks-only plugin such as `langfuse-observability` stays core too: it costs no tokens, and turning it off would silently stop its hooks.

**Git repos only.** `claude-stack` refuses a non-git path. Outside a repo, `apply ~` would write `~/.claude/rules/skill-stack.md`, a user-level rule that loads everywhere.

**The asymmetry that sets the default.** A wrong keep costs about 1,000 tokens. A wrong drop hides a tool, and the fix is one command. So history counts as a keep signal, and the rule file names what is off and how to restore it.

**Two layers.**

1. `claude-stack` (deterministic): reads `catalog.json`, gathers evidence, writes `enabledPlugins` entries, the manifest and the rule file.
2. `project-stack` skill (judgment): reads the project, walks the ten dimensions, searches `catalog.json`, reads candidate `SKILL.md` files, picks exact tools per capability, reports gaps, and calls `claude-stack apply --picks`.

**What a session sees.** Fewer tools, more descriptions, and a short `.claude/rules/skill-stack.md` naming the chosen tool per capability.

**Non-goals.** No external catalog, no installing anything, no auto-run on session start, no per-skill filtering inside a plugin, no change to user-scope defaults.

## Open choice for later, not in this plan

Opt-in at user scope: turn the 23 plugins off in `agents/claude-plugins.txt` and let each project enable what it needs. Unknown repos would then start small too. It changes every session, so it should wait for real use of the opt-out version. `skillListingBudgetFraction` is a second knob if descriptions are still short after selection.
