"""The tool settings mise cannot hold: recorded in tools.toml in the user's folder and replayed on another Mac."""
import json, os, tomllib
from collections.abc import Callable
from pathlib import Path

from .model import Adapter, Setting, SettingsError

Tools = dict[str, str]


def user_dir() -> Path:
    return Path(os.environ.get("ROTM_USER_DIR") or Path.home() / ".config/rotm")


def tools_path() -> Path:
    return user_dir() / "tools.toml"


def applied_path() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "rotm/tools.applied.toml"


def _parse(text: str, path: Path) -> Tools:
    try:
        return tomllib.loads(text).get("tools", {})
    except tomllib.TOMLDecodeError as e:
        raise SettingsError(f"{path} is not valid TOML: {e}") from None


def _load(path: Path) -> Tools:
    try:
        return _parse(path.read_text(), path)
    except FileNotFoundError:
        return {}


def _save(path: Path, change: Callable[[Tools], Tools]) -> None:
    from .adapters.tool import edit_file  # here, not at the top: tool.py imports this module
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()
    # json.dumps of a str is a valid TOML basic string
    render = lambda t: "[tools]\n" + "".join(f"{json.dumps(k)} = {json.dumps(v, ensure_ascii=False)}\n"
                                             for k, v in sorted(t.items()))
    edit_file(path, lambda text: render(change(_parse(text, path))))


def record(s: Setting, value: str) -> None:
    if s.scope == "machine":
        return
    for path in (tools_path(), applied_path()):
        _save(path, lambda t: {**t, s.id: value})


def forget(s: Setting) -> None:
    if s.scope == "machine":
        return
    for path in (tools_path(), applied_path()):
        if s.id in _load(path):
            _save(path, lambda t: {k: v for k, v in t.items() if k != s.id})


def replay(settings: list[Setting], adapters: dict[str, Adapter]) -> list[str]:
    by_id = {s.id: s for s in settings}
    wanted, applied = _load(tools_path()), _load(applied_path())
    lines, done = [], {}
    for id, value in sorted(wanted.items()):
        if id not in by_id:
            lines.append(f"skipped {id}: not a setting here")
            continue
        s = by_id[id]
        try:
            if adapters[s.kind].read(s).value != value:
                adapters[s.kind].write(s, value)
                lines.append(f"set {id}")
            done[id] = value
        except SettingsError as e:
            lines.append(f"{id}: {e}")
    for id in sorted(applied.keys() - wanted.keys()):
        if id not in by_id:
            lines.append(f"skipped {id}: not a setting here")
            continue
        try:
            adapters[by_id[id].kind].reset(by_id[id])
            lines.append(f"reset {id}")
        except SettingsError as e:
            done[id] = applied[id]  # still applied here, so the next replay tries the reset again
            lines.append(f"{id}: {e}")
    _save(applied_path(), lambda _: done)
    return lines
