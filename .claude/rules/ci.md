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
- `check.yml` installs mise at the floor in `setup/mise-floor.sh` and uv. Renovate does not bump the `version:` input: raise it with the floor (`bin/lib/test-override-env` fails when they differ).
- `check` runs a dry run of `conf.d/30-packages.toml` on every push, against an empty prefix: a formula, cask or tap formula that does not resolve fails it, and VS Code extension ids are not checked. `fresh-install` is manual (`gh workflow run fresh-install.yml`). It deletes the runner's Homebrew, runs `./setup.sh -y --skip-codegraph` (mise's installer, the packages, `mise bootstrap` without macOS preferences, `mise install`, then the task), logs free disk space and mise's download cache per manager, and fails when a bootstrap part or the task fails, or any package or tool is not installed. The `setup.sh` step accepts exit 2 (only packages or tools failed) and leaves the verdict to the later check steps, so the tolerated `royal-tsx` miss alone stays green. Run it after changing the package list in bulk, the setup path or the mise floor. A hosted runner is not a clean Mac (Xcode is preinstalled, sudo needs no password). The full proof is the VM checklist in the A6 plan's Task 6.
- Keep Renovate's `minimumReleaseAge` in step with `pnpm-workspace.yaml`'s.
- Add an `allowedVersions` rule when a mise comment holds a tool back a major (as for `npm:typescript`).
