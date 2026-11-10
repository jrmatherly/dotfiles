"""The shapes every adapter and front end share: a setting, its value and where the value came from."""
from dataclasses import dataclass
from enum import Enum
from typing import Protocol


class SettingsError(Exception):
    """An expected failure the CLI reports without a traceback (exit 1)."""


class InvalidValue(SettingsError):
    """A value the setting does not accept (exit 2)."""


class Source(Enum):
    OVERRIDE = "override"
    SEED = "seed"
    DEFAULT = "default"
    UNSET = "unset"


@dataclass(frozen=True, kw_only=True)
class Setting:
    id: str
    section: str
    label: str
    help: str
    kind: str
    key: str
    type: str
    access: str
    true_value: str = ""
    choices: tuple[str, ...] = ()
    default: str = ""
    widget: str = ""


@dataclass(frozen=True)
class Value:
    setting_id: str
    value: str | None
    source: Source
    seed: str | None
    drift: bool


class Adapter(Protocol):
    """Optional, looked up with getattr: apply(self, settings) -> list[str], watch_paths(self) -> list[Path],
    and write_note, either a string or write_note(self, s) -> str."""

    def read(self, s: Setting) -> Value: ...
    def write(self, s: Setting, value: str) -> None: ...
    def reset(self, s: Setting) -> None: ...


def note_for(adapter: object, s: Setting) -> str:
    note = getattr(adapter, "write_note", "")
    return note(s) if callable(note) else note
