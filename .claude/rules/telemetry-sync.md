---
paths:
  - 'setup.sh'
  - 'zsh/env.zsh'
  - 'docs/privacy.md'
  - 'settings/registry.toml'
---

# Telemetry opt-outs are listed twice

`setup.sh` exports a subset of the telemetry opt-out variables in `zsh/env.zsh`, because `env.zsh` isn't sourced yet on a fresh Mac. `bin/lib/test-conventions` fails the gate when a `setup.sh` export is missing from `env.zsh`. Add, rename or remove a variable in both files, and in `docs/privacy.md`, in the same change. When the change touches `setup.sh`'s list, also update the tool list in `README.md` ("exports telemetry opt-outs (…)"). An opt-out that a Claude Code plugin hook reads (the Azure plugin's `AZURE_MCP_COLLECT_TELEMETRY`) also goes into `env` in `agents/claude-settings.json`, so Claude Code launched from an app that never sourced the shell still carries it. Each opt-out exported by `zsh/env.zsh` is also a read-only entry in `settings/registry.toml`, and `settings/tests/test_registry.py` fails the gate when an entry's variable is no longer exported there, so add, rename or remove the registry entry in the same change.
