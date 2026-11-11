"""Load and validate registry.toml, the list of every setting."""
import os, re, tomllib
from pathlib import Path

from .model import Setting, SettingsError

KINDS = ("env", "macos-default", "package", "dotfile", "tool")
TYPES = ("bool", "string", "int", "enum", "path")
WIDGETS = ("", "lines", "seats")
REQUIRED = ("id", "section", "label", "help", "kind", "key", "type", "access")
OPTIONAL = {"true_value": "", "choices": [], "default": "", "widget": ""}
ID = re.compile(r"[a-z0-9_]+(\.[a-z0-9_]+)+")
ENV_KEY = re.compile(r"[A-Z_][A-Z0-9_]*")


def default_path() -> Path:
    if os.environ.get("DOTFILES_SETTINGS_REGISTRY"):
        return Path(os.environ["DOTFILES_SETTINGS_REGISTRY"])
    beside = Path(__file__).resolve().with_name("registry.toml")  # installed wheel
    return beside if beside.is_file() else Path(__file__).resolve().parents[2] / "registry.toml"


def load(path: Path | None = None) -> list[Setting]:
    path = path or default_path()
    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise SettingsError(f"{path}: {e}") from None
    tables = data.get("setting", [])
    if not tables:
        raise SettingsError(f"{path}: no settings")
    settings, seen = [], set()
    for t in tables:
        s = parse(t)
        if s.id in seen:
            raise SettingsError(f"duplicate id: {s.id}")
        seen.add(s.id)
        settings.append(s)
    return settings


def parse(t: dict) -> Setting:
    id = t.get("id", "?")
    if not isinstance(id, str) or not ID.fullmatch(id):
        raise SettingsError(f"id must be dotted lowercase: {id!r}")
    for name in REQUIRED:
        if name not in t:
            raise SettingsError(f"{id}: missing field {name!r}")
    for name, value in t.items():
        if name not in REQUIRED and name not in OPTIONAL:
            raise SettingsError(f"{id}: unknown field {name!r}")
        ok = isinstance(value, list) and all(isinstance(c, str) for c in value) if name == "choices" else isinstance(value, str)
        if not ok:
            raise SettingsError(f"{id}: field {name!r} has the wrong type")
    f = {**OPTIONAL, **t}
    if f["kind"] not in KINDS:
        raise SettingsError(f"{id}: unknown kind {f['kind']!r}")
    if f["type"] not in TYPES:
        raise SettingsError(f"{id}: unknown type {f['type']!r}")
    if f["access"] not in ("rw", "ro"):
        raise SettingsError(f"{id}: access must be rw or ro")
    if f["widget"] not in WIDGETS:
        raise SettingsError(f"{id}: unknown widget {f['widget']!r}")
    if f["kind"] == "env" and not ENV_KEY.fullmatch(f["key"]):
        raise SettingsError(f"{id}: env key must match [A-Z_][A-Z0-9_]*")
    if f["type"] == "bool" and not f["true_value"]:
        raise SettingsError(f"{id}: bool needs true_value")
    if f["type"] == "enum" and not f["choices"]:
        raise SettingsError(f"{id}: enum needs choices")
    if f["choices"] and f["default"] and f["default"] not in f["choices"]:
        raise SettingsError(f"{id}: default {f['default']!r} is not one of the choices")
    return Setting(**{**f, "choices": tuple(f["choices"])})
