---
paths:
  - 'setup.sh'
  - 'setup/**'
---

# Setup scripts

- A closed stdin (non-interactive run) must mean "skip", never abort or overwrite.
- `brew.sh` runs first; later scripts may use Homebrew tools but must guard with `command_exists` for `--skip-brew` on a fresh Mac.
- Every behavior change updates `setup/README.md` (and `README.md` for flags) in the same commit.
- `--skip-codegraph` must leave an existing CodeGraph install untouched, including its mise shim (a `mise reshim` while `MISE_DISABLE_TOOLS` is set deletes it).
- Fresh-install paths (no Homebrew, no 1Password, no `node_modules`) can't be verified on this machine — say so when a change touches them.
- Validate with `/validate-setup before`, then `./setup.sh --skip-brew` in a terminal (it is interactive), then `/validate-setup after`.
