---
paths:
  - 'setup.sh'
  - 'zsh/env.zsh'
  - 'docs/privacy.md'
---

# Telemetry opt-outs are listed twice

`setup.sh` exports a subset of the telemetry opt-out variables in `zsh/env.zsh`, because `env.zsh` isn't sourced yet on a fresh Mac. `bin/lib/test-conventions` fails the gate when a `setup.sh` export is missing from `env.zsh`. Add, rename or remove a variable in both files, and in `docs/privacy.md`, in the same change. When the change touches `setup.sh`'s list, also update the tool list in `README.md` ("exports telemetry opt-outs (…)"). An opt-out that a Claude Code plugin hook reads (the Azure plugin's `AZURE_MCP_COLLECT_TELEMETRY`) also goes into `env` in `agents/claude-settings.json`, so Claude Code launched from an app that never sourced the shell still carries it.
