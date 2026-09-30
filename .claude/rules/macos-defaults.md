---
paths:
  - 'setup/macos.sh'
---

# macOS defaults

- Security-sensitive and per-machine settings prompt; don't apply them unconditionally.
- Verify each `defaults` domain/key against the current macOS release before adding it; prefer leaving a value at the macOS default over pinning it.
- The script force-quits Finder, Dock, Messages, Activity Monitor, Notification Center, SystemUIServer and Terminal at the end — keep that list and `README.md`'s description of it in sync.
