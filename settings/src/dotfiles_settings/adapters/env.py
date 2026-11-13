"""Env settings: read from mise's config.override.toml, written through `mise set --override`.
A machine-scoped setting goes to config.local.toml instead, which mise never syncs."""
import os, subprocess, tomllib
from pathlib import Path

from .. import mise, registry
from ..model import InvalidValue, Setting, SettingsError, Source, Value

# mise parses {{ {% {# as Tera and expands $VAR, so the stored value would not be the typed one
REFUSED = (("{{", "{{"), ("{%", "{%"), ("{#", "{#"), ("$", "$"), ("\n", "a line break"), ("\r", "a line break"))
VSCODE_KEY = "VSCODE_FONT_PRESET"


def override_path() -> Path:
    return mise.config_dir() / "config.override.toml"


def local_path() -> Path:
    return mise.config_dir() / "config.local.toml"


def read_override() -> dict[str, str]:
    return read_env(override_path())


def read_env(path: Path) -> dict[str, str]:
    try:
        data = tomllib.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as e:
        raise SettingsError(f"{path}: {e}") from None
    table = data.get("env", {})
    return {k: v for k, v in table.items() if isinstance(v, str)} if isinstance(table, dict) else {}


def seed_env(keys: set[str]) -> dict[str, str]:
    # A fresh `zsh -ic` never reaches the prompt, so mise activate never runs; the guard skips A1's override cache
    child = {k: v for k, v in os.environ.items() if k not in keys} | {"DOTFILES_NO_OVERRIDE_ENV": "1"}
    try:
        # New session: an interactive zsh on the TUI's terminal left every later keypress read failing with EIO
        r = subprocess.run(["zsh", "-ic", "/usr/bin/env -0"], env=child, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20, start_new_session=True)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise SettingsError(f"could not start a zsh to read the seed values: {e}") from None
    if r.returncode != 0:
        raise SettingsError(f"zsh -ic exited {r.returncode} while reading the seed values")
    pairs = (entry.split("=", 1) for entry in r.stdout.decode(errors="replace").split("\0") if "=" in entry)
    return {k: v for k, v in pairs if k in keys}


def vscode_env_path() -> Path:
    return Path(os.environ.get("VSCODE_SETTINGS_ENV") or Path.home() / ".config/dotfiles/vscode.env")


def file_seed(key: str) -> str | None:
    if key != VSCODE_KEY:
        return None
    try:
        lines = vscode_env_path().read_text().splitlines()
    except OSError:
        return None
    for line in lines:
        if line.startswith(f"{key}="):
            v = line[len(key) + 1:]
            return v[1:-1] if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"" else v
    return None


class EnvAdapter:
    write_note = "Open a new shell to pick this up."

    def __init__(self):
        self._seed: dict[str, str] | None = None

    def read(self, s: Setting) -> Value:
        # The override file outranks config.local.toml in mise, so a value left there from before scope existed wins
        override = {**read_env(local_path()), **read_override()} if s.scope == "machine" else read_override()
        if self._seed is None:  # one shell start serves every row
            self._seed = seed_env({e.key for e in registry.load() if e.kind == "env"})
        found = self._seed.get(s.key)
        if found is None:
            found = file_seed(s.key)
        default = (os.path.expanduser(s.default) if s.type == "path" else s.default) or None
        if s.key in override:
            return Value(s.id, override[s.key], Source.OVERRIDE, found if found is not None else default, False)
        if found is not None:
            return Value(s.id, found, Source.SEED, found, False)
        if default is not None:
            return Value(s.id, default, Source.DEFAULT, default, False)
        return Value(s.id, None, Source.UNSET, None, False)

    def write(self, s: Setting, value: str) -> None:
        for needle, name in REFUSED:
            if needle in value:
                raise InvalidValue(f"{s.id}: a value cannot contain {name}")
        if s.scope == "machine":
            mise.run_mise(["set", "--file", str(local_path()), f"{s.key}={value}"])
            self.reset_override(s)
            stored = read_env(local_path())
        else:
            mise.run_mise(["set", "--override", f"{s.key}={value}"])
            stored = read_override()
        if stored.get(s.key) != value:
            raise SettingsError(f"{s.key} was changed by another writer, try again")

    def reset(self, s: Setting) -> None:
        if s.scope == "machine" and s.key in read_env(local_path()):
            mise.run_mise(["unset", "--file", str(local_path()), s.key])
        self.reset_override(s)

    def reset_override(self, s: Setting) -> None:
        if s.key in read_override():
            mise.run_mise(["unset", "--override", s.key])

    def watch_paths(self) -> list[Path]:
        return [override_path(), local_path(), vscode_env_path()]
