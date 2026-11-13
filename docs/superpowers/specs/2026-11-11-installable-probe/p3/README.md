# P3 sync probes

Evidence for the P3 plan (`docs/superpowers/plans/2026-11-12-p3-sign-in-and-sync.md`), run on 2026-11-12 with mise 2026.11.5 in scratch homes on the owner's Mac. Not part of the product. Each script builds its own scratch folder, points `HOME` and every `MISE_*_DIR` at it, runs every mise call from the scratch home and removes the folder on exit (`KEEP=1` keeps it).

| Script | Question |
| --- | --- |
| `1-track-in-place.sh` | Does mise's sync save the user's files where P1 and P2 put them, and where does `mise dot track` write its entry? |
| `2-folder-outside-checkout.sh` | Does a folder outside the checkout, linked into the config dir, sync both ways between two installed copies? |
| `4-adopt-final-hook.sh` | Does `mise bootstrap --adopt` apply the base, with and without `--only final-hook`? |
| `5-track-table-and-conflict.sh` | What does mise print with no origin and no conflict, is a track entry honoured as its own table, and what happens on a restore onto a different local file? |

Two probes were run inline and are not saved; the plan's table records their results: probe 3 (what the override file can hold, and `mise set --override`'s exit code) and probe 6 (a link with no target yet, `disable_tools`, how mise authenticates its Git calls, and credential precedence).

Known flaw: in scripts 1, 2, 4 and 5 the `[exit N]` lines are not mise's exit status. `m` returns the status of the `grep` that filters mise's version warning, so a call with no other output reads as 1. The answers the plan uses come from the files and the text these scripts print, not from those lines.
