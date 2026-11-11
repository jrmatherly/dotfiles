# rtk

A hook rewrites Bash commands to `rtk <cmd>`, which condenses their output to save tokens. Treat that output as complete. Exit codes are unchanged.

- When a result is empty where output was expected, contradicts its exit code or looks cut short, re-run it as `rtk bypass <cmd>` for the raw output. `RTK_DISABLED=1 <cmd>` skips rtk for one command.
- `rtk gain` shows the token savings and `rtk discover` finds commands rtk could have condensed. Run them only when asked.
