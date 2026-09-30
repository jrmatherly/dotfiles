# OrbStack

> Lightweight Docker engine and Linux machines for macOS. It is the repo's container runtime

## Repo setup

- **Install:** `cask "orbstack"` in `setup/Brewfile`. The Brewfile also installs the `docker`, `docker-buildx` and `docker-compose` formulae, and OrbStack ships its own copies of these tools (it installs them only if working ones are missing)
- **Shell:** `tilde/.zprofile` sources `~/.orbstack/shell/init.zsh`, which adds `~/.orbstack/bin` to `PATH` and adds zsh completions
- **SSH:** `tilde/.ssh/config` starts with `Include ~/.orbstack/ssh/config`, which defines the `orb` host. It must stay above any `Host` blocks
- **Aliases (`zsh/aliases.zsh`):** `d` = `docker`, `dc` = `docker compose`, `ld` = `lazydocker`

## Docker

- **Context:** OrbStack creates and automatically uses a Docker context named `orbstack`. `docker context ls` shows it; if another context is active, run `docker context use orbstack`
- **Compose:** `docker compose` (`dc`) works as usual
- **Domains:** each container gets `container-name.orb.local`, and each Compose service gets `service.project.orb.local`. HTTPS works with no setup, and you don't need port numbers for web services

## CLI (`orb` = `orbctl`)

- **`orb`:** open a shell in the default Linux machine
- **`orb <command>`:** run a command in Linux, e.g. `orb uname -a`
- **`orb -m <machine> -u <user> <command>`:** run a command in a specific machine as a specific user
- **`orb status` / `orb start` / `orb stop`:** check, start or stop OrbStack (or a single machine)
- **`orb list`:** list machines; **`orb info <machine>`:** show machine details
- **`orb create ubuntu my-ubuntu`:** create a machine (add `--arch amd64` for Intel, or set `--cpus`, `--memory` and `--disk`)
- **`orb delete` / `orb clone` / `orb default`:** remove, copy or pick the default machine
- **`orb logs <machine>`:** show boot logs
- **`orb push` / `orb pull`:** copy files to or from Linux
- **`orb debug <container>`:** debug a Docker container with extra tools
- **`orb k8s`:** show how to use Kubernetes
- **`orb config show` / `orb config set`:** view or change OrbStack settings
- **`orb doctor`:** check that OrbStack is set up correctly and in control
- **`orb top`:** live activity monitor

## Machines

- **`ssh orb`:** SSH into the default machine; `ssh <machine>@orb` or `ssh <user>@<machine>@orb` for others
- **Mac files in Linux:** `/mnt/mac`; other machines at `/mnt/machines/<name>`
- **Linux files on the Mac:** `~/OrbStack`, or the OrbStack section in Finder
- **`mac <command>`:** run a macOS command from inside a machine

## Sources

- https://docs.orbstack.dev/docker/
- https://docs.orbstack.dev/docker/domains
- https://docs.orbstack.dev/machines/
- https://docs.orbstack.dev/machines/ssh
- Installed OrbStack 2.2.3: `orb --help`, `orbctl --help`, `~/.orbstack/shell/init.zsh`, `~/.orbstack/ssh/config`
