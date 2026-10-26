# REA

[REA](https://github.com/morluto/rea) (`rea-agents`) is a reverse-engineering toolkit that runs as a CLI and as an MCP server for Claude Code. It inspects binaries, app bundles, managed (.NET) assemblies, SQLite databases, web bundles and running apps, and drives external engines it never installs itself: Hopper Disassembler and Ghidra here. This page covers how it is installed by these dotfiles, how Claude Code reaches it, what works on this Mac today and how to check.

## Summary

- Installed as the mise npm tool `npm:rea-agents` (`tilde/.config/mise/config.toml`, `latest` with a 6 h release-age floor because REA ships several releases a day). `upup` upgrades it with the other mise tools.
- Registered with Claude Code at user scope as the `rea` MCP server by `setup/misc.sh`. The registered command is `bin/rea-mcp`, a launcher that resolves `GHIDRA_INSTALL_DIR` and `JAVA_HOME` from Homebrew at every start and execs `rea mcp`, so no versioned path is stored and a Ghidra upgrade that moves its JDK cannot strand the registration.
- The `reverse-engineer-anything` skill (REA's own workflow instructions) is the copy bundled with the installed `rea-agents`, written by `rea setup --skill` into `~/.agents/skills` and `~/.claude/skills` by `setup/misc.sh` and refreshed by `upup` after each REA upgrade, so it always describes the server that is running.
- Permission rules for its 229 MCP tools (6.8.0) are in `agents/claude-settings.json`: static-analysis tools run without a prompt, tools that drive a live app, browser or process or write files ask first (details in [agents/README.md](../agents/README.md)).
- Engines: Hopper (Brewfile cask, free demo until licensed) works. Ghidra (Brewfile formula, 12.2) is installed and its JDK resolves, but REA 6.8.0 still refuses Ghidra 12.2 (re-measured 2026-10-26) and the Homebrew build has no native decompiler, so the Ghidra provider is unusable until upstream lifts those limits.

## Commands

| Command | What it does |
| --- | --- |
| `rea doctor` | Check everything REA can see: runtime, engines, clients, skill. Expect `config_drift` rows for the Claude Code registration and the skill: both are managed here, not by `rea setup` |
| `rea-mcp --print-env` | Show the `GHIDRA_INSTALL_DIR` and `JAVA_HOME` the launcher hands to `rea mcp` |
| `eval "$(rea-mcp --print-env \| sed 's/^/export /')" && rea doctor --provider ghidra --json` | The Ghidra provider's checks under the launcher's environment |
| `rea capabilities --json` | Every provider, its operations and their side effects (the source of the permission rules) |
| `rea analyze {{path}} [--provider hopper\|ghidra]` | Overview of an app or binary |
| `rea decompile {{path}} ...` | One function as pseudo-code |
| `rea --help`, `rea {{command}} --help` | The full command list (175 commands in 6.8.0) and each command's options |
| `claude mcp get rea` | What Claude Code has registered; "Connected" means the server process starts, not that an engine works |

## How Claude Code reaches it

`setup/misc.sh` registers `rea` through the repo's `register_mcp` helper with the command `$DOTFILES/bin/rea-mcp` and no arguments or environment. A later setup run checks the registration for the command, args and environment lines it would write and warns with the re-register command when one is missing, so a registration written by `rea setup` or a moved launcher is never silently kept.

The launcher exists because Homebrew's `ghidra` formula depends on a versioned, keg-only `openjdk@N` that moves between Ghidra releases (`openjdk@21` for 12.1, `openjdk@25` for 12.2), and REA needs `JAVA_HOME` spelled out: its own fallback through `java` on PATH finds no JVM here, since Homebrew's OpenJDK is keg-only. A `JAVA_HOME` pinned in the registration dangled after the 12.2 upgrade while `claude mcp get rea` still said Connected. `bin/rea-mcp` reads both from the installed keg at every start (`brew --prefix ghidra`, then the `JAVA_HOME` default in that keg's `bin/ghidraRun` wrapper, about 0.3 s), so it uses the same JDK Homebrew's own `ghidraRun` uses and never one a `brew update` without `brew upgrade` only promises. A preset `JAVA_HOME` wins like that wrapper does, one without `bin/java` is dropped with a warning on stderr (Claude Code's MCP log shows it), `brew` is found at `/opt/homebrew/bin/brew` when Claude Code was launched from an app without the shell's PATH, and without Homebrew Ghidra the server still starts for Hopper and the built-in providers. Then it execs the mise `rea` shim with `mcp`.

`rea setup`'s client registration is not used (only its `--skill` install is). It writes an `npx -y rea-agents@<exact version>` registration that goes stale, and `npx` here resolves through npm's `min-release-age`.

## Engines on this Mac

| Engine | Install | State (2026-10-24) |
| --- | --- | --- |
| Hopper Disassembler | Brewfile cask `hopper-disassembler`; REA finds it at its default path | Works as the free demo until licensed in the app |
| Ghidra | Brewfile formula `ghidra` (12.2, pulls `openjdk@25`) | JDK check passes through the launcher. REA 6.8.0 accepts only Ghidra 12.1.x, verified build 12.1.4 ([morluto/rea#6921](https://github.com/morluto/rea/issues/6921)) and the Homebrew build ships no native decompiler for darwin/arm64 ([#7018](https://github.com/morluto/rea/issues/7018)), so `rea analyze --provider ghidra` fails with `unsupported_version` |
| IDA, JADX, Kuna, Frida, GDB, Rizin/Cutter, sigrok, adb | Not installed, or not configured | `rea doctor` lists each with the variable that would enable it (`REA_JADX_MCP_JAR`, `REA_KUNA_COMMAND`, `REA_IDA_MCP_CONFIG`) |

Built-in providers that need no engine work today: native macOS inspection (Mach-O, plists, signatures, Swift demangling, AX-driven UI capture), the artifact graph (app bundles, DMGs mounted read-only, PKGs, ASAR), .NET metadata, SQLite, JavaScript and Electron static analysis, and web bundle capture through Playwright.

## When something changes

- After `upup` upgrades REA, re-run the MCP inspector command in [agents/README.md](../agents/README.md) and compare the tool list with the permission rules: a new tool arrives with no rule.
- After a Ghidra upgrade, nothing to do for the JDK. `rea-mcp --print-env` shows the new `openjdk@N`. If REA starts accepting the installed Ghidra line, the `ghidra-version` row in `rea doctor` stops reporting `config_drift` (today: "12.2; accepted releases are 12.1.x").
- If the dotfiles clone moves, re-run `./setup.sh --skip-brew` (or `setup/misc.sh`): the registration holds the launcher's absolute path and `register_mcp` warns about the old one.
- Hopper: licence it in the app; REA notices on the next `doctor`.

## Privacy

REA runs locally and the docs name no telemetry. Tools under `capture_*` and `observe_*` launch and drive the target app, browser or process and may use the network as that target would; they are in `permissions.ask` for that reason. See [privacy.md](privacy.md) for the rest of the setup.
