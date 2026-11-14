# Hindsight's daemon environment and the uv cache

Findings from 2026-11-13 on why `~/.cache/uv` grows, what a prune can and cannot do, and whether Hindsight is installed and configured the way its vendor intends as of November 2026. The plan built on it is `docs/superpowers/plans/2026-11-13-hindsight-daemon-environment-and-uv-cache.md`. It extends `docs/superpowers/specs/completed/2026-10-24-hindsight-memory.md`.

## Goal

The Hindsight daemon runs from one reviewed, locked environment that never multiplies, and `sysup` prunes the uv cache when it safely can.

## Decisions the owner made

1. 2026-11-13: `sysup` gains a `uv cache prune` step.
2. 2026-11-13: this work comes before the rest of P5 (the `app-v0.1.0` tag, Tasks 9, 11 and 12).

## Open decisions for the owner

| # | Question | Recommendation |
| --- | --- | --- |
| A | Run the daemon from a locked uv project (finding 4) instead of the vendor's default `uvx`? | Yes. It is the vendor's own code path (`embedPackagePath`), it removes the cause, and it makes the 231 dependencies a reviewed diff. |
| B | What `sysup` says when the cache is in use and the prune is skipped. | `ok` below 20 cached environments, `notice` with the command at 20 or more. |
| C | Bump the pins (hook package 0.8.3 to 0.8.6 or 0.8.7, daemon 1.1.0 to 1.2.1) now or later? | Later, as its own commit after the lock lands (Task 4), because 0.8.7 carries a breaking rename. |
| D | Delete the stale `~/.pg0/instances/hindsight-embed-` (65 MB, not this session's)? | Yes, after checking nothing uses it (Task 3). |

## Verified facts

Each row was measured on this Mac on 2026-11-13 (uv 0.13.7) unless it names another source.

| # | Fact | How it was checked |
| --- | --- | --- |
| 1 | The cause of the growth is floating dependencies. 37 cached environments hold `hindsight-api 1.1.0`. Consecutive ones differ only in bumped dependencies (`claude_agent_sdk` 0.2.181 to 0.2.182 and `openai` 3.50.0 to 3.51.0 between two of 2026-11-13; `cyclopts` and `github_copilot_sdk` between the next two). The first and the latest differ in dozens. | `diff` of the `*.dist-info` names in `site-packages` of four pairs under `~/.cache/uv/archive-v0`. |
| 2 | A new environment appears at each daemon cold start after any dependency released. The newest was created at 23:19, the minute the running daemon started. Four appeared on 2026-11-13. | Directory mtimes against `ps -o lstart`. |
| 3 | `hindsight-api-slim` bounds almost every dependency from below only. | Subagent read of PyPI `requires_dist` for 1.2.1; consistent with fact 1. Not re-read here. |
| 4 | The daemon can run from a fixed environment with no `uvx`. The hook package runs `uv run --directory <embedPackagePath> hindsight-embed` when `embedPackagePath` is set (`~/.hindsight/coding-agents/dist/daemon-start.js`, `getEmbedCommand`). `hindsight-embed` then prefers a `hindsight-api` binary in its own environment over `uvx hindsight-api@<version>` (`daemon_embed_manager.py`, `_find_api_command`). | A project with `hindsight-embed==1.1.0` and `hindsight-api==1.1.0` locked 231 packages in 0.7 s and synced in 1 s from the cache. `_find_api_command` returned `.venv/bin/hindsight-api`. A daemon on a throwaway profile (port 9199) was healthy in 31 s, ran as `.venv/bin/python …/hindsight-api`, and left no `uv` parent process. The live daemon on 9077 stayed healthy. The profile and its database were removed afterwards. |
| 5 | Today's daemon holds the cache lock for its whole life, because its parent is `uv tool uvx hindsight-api@1.1.0 --idle-timeout 0 --port 9077`. So does each session's `uv tool uvx --python 3.12 browser-use@latest --cli-mcp`. | `ps`. Lock semantics from the uv docs (subagent) and fact 6. |
| 6 | A prune against a held lock waits `UV_LOCK_TIMEOUT` seconds (default 300), prints `Cache is currently in-use, waiting for other uv processes to finish`, then `error: Timeout (4s) when waiting for lock on …` and exits 2. It deletes nothing. | Throwaway `UV_CACHE_DIR` with a sleeping `uvx` process and `UV_LOCK_TIMEOUT=4`. |
| 7 | A prune with the lock free removes every cached tool environment (3 of 3), and the next `uvx` rebuilds what it needs. There is no dry run. | Same throwaway cache. |
| 8 | `du` overstates the cache. Environments are copy-on-write clones of the unpacked wheels: creating a 2.0 GiB-by-`du` environment used about 70 MiB of free space. `du` reports 105 GiB for the cache, yet the volume has 149 GiB free where the 2026-11-13 morning note said 92 GiB. | `df` before and after `uv sync`; the delete-side reading was noise (minus 152 MiB), so the real size of the cache is not measured. |
| 9 | The vendor knows. Issue vectorize-io/hindsight#2915 (35 environments, 55.5 GiB) was closed 2026-07-31 by a docs change (PR 3118): stop the daemon, then `uv cache prune`. | `gh issue view`, `gh pr view`. |
| 10 | The pins are behind. npm has hook package 0.8.7; 0.8.6 is the newest that `min-release-age` allows today. PyPI has `hindsight-embed`, `hindsight-api` 1.2.1. | `npm view`, `npm pack --dry-run`; PyPI from the subagent. |
| 11 | `uv` has no cache size limit or TTL. PR astral-sh/uv#20116 (open) adds a preview `cache-autoprune` and makes `uvx` release the lock before running the command. uv 0.13.8 only stops duplicate builds from concurrent `uvx` calls. | Subagent read of the uv docs, issues 5731 and 9790, and the 0.13.8 notes. Not re-read here. |

## What this means

- **The lock fixes the cause and a gap in the first design.** The 2026-10-24 spec says hook code changes only through a reviewed bump. The daemon's 200-odd dependencies were outside that rule: each cold start could run versions nobody reviewed. A tracked `uv.lock` puts them inside it.
- **It also frees the cache lock.** `uv run … hindsight-embed daemon start` exits once the daemon is up (fact 4), so the daemon stops blocking prunes. The browser-use servers still hold it while sessions are open, and `@latest` in that plugin is not this repo's to change.
- **The prune is housekeeping, not the fix.** It removes every cached environment each time it runs (fact 7), they come back as tools are used, and how much real space it frees is unmeasured (fact 8). Task 3 takes that measurement.
- **A prune is safe for memory.** The database is in `~/.pg0` (1.2 GiB) and the config in `~/.hindsight` (68 MB), both outside the cache.

## Checked and left alone

From the vendor pages the owner listed. These rest on the docs subagent's reading unless a fact above covers them.

- **MCP server page.** The documented HTTP endpoint (`/mcp/{bank_id}/`) is one static bank per registration. The installer's `node dist/mcp-server.js` picks the bank per repository, which is what this setup needs (the process is visible in `ps`). No change.
- **Extensions page.** Tenant API keys and model-call logging. Neither helps a single-user daemon bound to 127.0.0.1.
- **Skills and Claude Agent SDK pages.** A model-invoked memory skill and a library for apps you build. Both overlap the hook package; the 2026-10-24 spec already removed the equivalent skills.
- **Config keys.** None of the keys in `bin/hindsight-memory`'s defaults is documented as removed. `daemonIdleTimeout` and `autoReflect` are deprecated and this repo sets neither. `memory_defense` is not on the coding-agents page; Task 3 reads one bank's stored config to confirm it is applied.
- **`HINDSIGHT_API_*_LOCAL_FORCE_CPU`.** In the vendor's Mac sample. No evidence here of a GPU problem, so not adopted.
- **`uv tool install hindsight-embed --with hindsight-api`.** Would also avoid `uvx`, but the hook package only knows `uvx hindsight-embed@<version>` or `embedPackagePath`, and a tool install keeps no reviewed lock.
- **`UV_EXCLUDE_NEWER`.** Freezes resolution by date for one process tree, but it has to be bumped by hand and still resolves on every start.

## Not verified

- The real size of the cache and what a prune frees (fact 8).
- Which config keys 0.8.7's "Knowledge Pages to Pages" rename touches.
- That the hook's own cold start (not a hand-run `daemon start`) works with `embedPackagePath` on the `coding-agent` profile. Task 3 proves it on the live daemon.
