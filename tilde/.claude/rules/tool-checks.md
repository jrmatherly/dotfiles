# Checking whether a tool is installed

- Before saying a CLI is missing, run `command -v <tool>`. Tools here come from Homebrew, mise and uv, so a miss in one place isn't a miss everywhere (`brew list`, `mise ls`, `uv tool list` say which).
- A failed `npx --no-install`, `pnpm exec` or `python -m` only means that runner couldn't find it (project `node_modules`, npx cache, current venv). Retry with the bare command before concluding anything.
- If it still fails, report the exact check that failed ("`command -v foo` found nothing"), not "not installed".
