"""The link and copy state of conf.d/40-dotfiles.toml from `mise dotfiles status --json`, as one read-only row.
`apply` runs `mise dotfiles apply --yes`, which refuses to replace a real file and never gets `--force`."""
import os, subprocess
from pathlib import Path

from .. import mise
from ..model import Setting, SettingsError, Source, Value
from .package import last_line, parse

FORCE_HINT = "Move each aside, or adopt it with `mise dotfiles add <path>`, then apply again."
APPLY = ("dotfiles", "apply", "--yes")
FINE = ("applied", "tracked")
READ_ONLY = "dotfiles are declared in conf.d/40-dotfiles.toml, edit that file"


def entries() -> list[dict]:
    data = parse(["dotfiles", "status", "--json"])
    return data.get("files", []) + data.get("edits", [])


def label(entry: dict) -> str:
    return f'{entry["path"]} ({entry["edit"]})' if "edit" in entry else entry["target"]


def conflicts(stderr: str) -> list[str]:
    lines = stderr.splitlines()
    start = next((i + 1 for i, l in enumerate(lines) if "refusing to overwrite existing files" in l), len(lines))
    paths = []
    for l in lines[start:]:
        if not l.startswith("  "):
            break
        paths.append(l.strip())
    return paths


def errors(stderr: str) -> list[str]:
    # Each `mise ERROR` line and the indented lines under it, minus mise's version and --verbose footer
    out, keep = [], False
    for l in stderr.splitlines():
        if l.startswith("mise ERROR"):
            keep = not ("Version:" in l or "Run with --verbose" in l)
        elif not l.startswith("  "):
            keep = False
        if keep:
            out.append(l)
    return out


class DotfileAdapter:
    def read(self, s: Setting) -> Value:
        try:
            found = entries()
        except SettingsError as e:
            return Value(s.id, f"status failed: {last_line(e)}", Source.UNSET, None, True)
        bad = [e for e in found if e.get("state") not in FINE]
        value = f"{len(found) - len(bad)} of {len(found)} applied" + "".join(
            f"; {label(e)}: {e.get('state')}" + (f" ({e['reason']})" if e.get("reason") else "") for e in bad)
        return Value(s.id, value, Source.SEED, None, bool(bad))

    def write(self, s: Setting, value: str) -> None:
        raise SettingsError(READ_ONLY)

    def reset(self, s: Setting) -> None:
        raise SettingsError(READ_ONLY)

    def apply(self, settings: list[Setting]) -> list[str]:
        # Not run_mise: a failure needs stderr's conflict list, not just its last line
        try:
            r = subprocess.run([os.environ.get("DOTFILES_SETTINGS_MISE", "mise"), *APPLY], capture_output=True,
                               text=True, cwd=Path.home())
        except FileNotFoundError:
            raise SettingsError(mise.MISSING) from None
        if r.returncode == 0:
            return [l.removeprefix("mise ") for l in (r.stdout + r.stderr).splitlines() if l.strip()]
        if paths := conflicts(r.stderr):
            raise SettingsError(f"{len(paths)} path(s) in the way, nothing was changed: {', '.join(paths)}. {FORCE_HINT}")
        raise SettingsError("\n".join(errors(r.stderr)) or f"mise {' '.join(APPLY)} exited {r.returncode}")
