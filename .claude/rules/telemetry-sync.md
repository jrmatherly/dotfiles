---
paths:
  - 'setup.sh'
  - 'zsh/env.zsh'
  - 'docs/privacy.md'
---

# Telemetry opt-outs are listed twice

`setup.sh` exports the same telemetry opt-out variables as `zsh/env.zsh`, because `env.zsh` isn't sourced yet on a fresh Mac. Add, rename or remove a variable in both files, and in `docs/privacy.md`, in the same change. When the change touches `setup.sh`'s list, also update the tool list in `README.md` ("exports telemetry opt-outs (…)").
