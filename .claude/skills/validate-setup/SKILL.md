---
name: validate-setup
description: Snapshot the machine state `mise bootstrap` manages before and after `./setup.sh`, and diff the two, to verify a setup change.
argument-hint: 'before|after'
disable-model-invocation: true
allowed-tools: Bash(.claude/skills/validate-setup/snapshot.sh *) Bash(mkdir -p private/setup-snapshots) Bash(diff *) Bash(pnpm check *) Bash(ls -t private/setup-logs/*) Bash(grep * private/setup-logs/*) Bash(mise -C ~ bootstrap status*) Bash(mise -C ~ bootstrap --dry-run*) Edit(/private/setup-snapshots/**)
---

Phase: $ARGUMENTS

- **before**: run `pnpm check` (stop and report if it fails), then `mkdir -p private/setup-snapshots` and `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/before.txt`. Run `mise -C ~ bootstrap --dry-run --skip macos-defaults` and say what it would change. Tell the user to run `./setup.sh` (add `--skip-codegraph` if CodeGraph is irrelevant, `-- --skip packages` to leave packages alone) **in their own terminal**, since it prompts, and then invoke `/validate-setup after`. They don't need to paste the output: setup.sh records each run to `private/setup-logs/<timestamp>.log`.
- **after**:
  1. Run `.claude/skills/validate-setup/snapshot.sh > private/setup-snapshots/after.txt`, then `diff -u private/setup-snapshots/before.txt private/setup-snapshots/after.txt`. Explain every changed line: expected from the change under test, or a regression. No diff means setup was a no-op. Say whether that was expected.
  2. Run `mise -C ~ bootstrap status --missing`. It lists every entry and exits 1 when one differs from the config. Name each entry whose last column is not `installed`, `applied`, `set` or `unchanged`. Exit 1 is not a failure by itself: setup never applies macOS preferences and apps rewrite their own, so `defaults` entries can differ (`set-defaults` applies them). An entry of any other part is a part that failed, fixed by rerunning `./setup.sh`.
  3. Read the newest log (`ls -t private/setup-logs/*.log`, first entry) and `grep -inE 'error|warn|deprecat|fail|not found'` it. Explain each hit (expected, harmless upstream noise, or a problem), and confirm the step under test printed what it should.
- Anything else: explain the two phases and stop.

Never run `./setup.sh` or `mise bootstrap` without `--dry-run` yourself.
