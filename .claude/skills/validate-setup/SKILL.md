---
name: validate-setup
description: Snapshot the machine state setup.sh manages before and after running it, and diff the two, to verify a setup change.
argument-hint: 'before|after'
disable-model-invocation: true
allowed-tools: Bash(.claude/skills/validate-setup/snapshot.sh *) Bash(mkdir -p private/setup-snapshots) Bash(diff *) Bash(pnpm check *)
---

Phase: $ARGUMENTS

- **before**: run `pnpm check` (stop and report if it fails), then `mkdir -p private/setup-snapshots` and `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/before.txt`. Tell the user to run `./setup.sh --skip-brew` (add `--skip-codegraph` if CodeGraph is irrelevant) **in their own terminal** — it prompts interactively — and then invoke `/validate-setup after`.
- **after**: run `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/after.txt`, then `diff -u private/setup-snapshots/before.txt private/setup-snapshots/after.txt`. Explain every changed line: expected from the change under test, or a regression. No diff means setup was a no-op — say whether that was expected.
- Anything else: explain the two phases and stop.

Never run `./setup.sh` yourself.
