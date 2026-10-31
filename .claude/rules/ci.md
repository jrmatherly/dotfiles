---
paths:
  - '.github/**'
  - 'renovate.json'
  - 'pnpm-workspace.yaml'
  - 'package.json'
  - 'tilde/.config/mise/config.toml'
---

# CI and Renovate

- The `check` workflow runs `pnpm check` on a pinned macOS image (15-minute timeout) for every PR and push to `main`, Renovate's PRs included.
- Renovate (Mend app, `renovate.json`) opens update PRs for `package.json` (dependencies and the `packageManager` pnpm pin), the workflow's pinned actions and `runs-on` image, and the global mise config's single-version tools. `node` and `python` are disabled: its mise manager reads only a list's first entry.
- Keep Renovate's `minimumReleaseAge` in step with `pnpm-workspace.yaml`'s.
- Add an `allowedVersions` rule when a mise comment holds a tool back a major (as for `npm:typescript`).
