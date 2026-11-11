"""Coding-agent settings: each tool's own file is read directly and written through its CLI where it has one."""
import json, os, re, shutil, subprocess, tempfile, urllib.request
from collections.abc import Callable
from pathlib import Path

from ..model import Setting, SettingsError, Source, Value

Reader = Callable[[str, Setting], Value]
Writer = Callable[[str, Setting, str], None]
Resetter = Callable[[str, Setting], None]


def run(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    if not os.environ.get("DOTFILES"):
        raise SettingsError("DOTFILES is not set")
    script = Path(os.environ["DOTFILES"]) / "bin" / argv[0]
    return subprocess.run([str(script), *argv[1:]], capture_output=True, text=True, cwd=cwd)


def edit_file(path: Path, change: Callable[[str], str]) -> None:
    real = path.resolve()  # write the link's target, keep the link
    for _ in (1, 2):
        before = real.read_text()
        after = change(before)
        if after == before:
            return
        fd, tmp = tempfile.mkstemp(dir=real.parent, prefix=real.name + ".")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(after)
                f.flush()
                os.fsync(f.fileno())
            shutil.copymode(real, tmp)
            if real.read_text() == before:  # nobody wrote since we read
                os.replace(tmp, real)
                return
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    raise SettingsError(f"{path} changed while it was being edited. Try again")


def _check(r: subprocess.CompletedProcess[str]) -> str:
    if r.returncode != 0:
        raise SettingsError(re.sub(r"\x1b\[[0-9;]*m|\x1b\(B", "", r.stderr).strip() or f"exit {r.returncode}")
    return r.stdout


def hindsight_config() -> Path:
    return Path(os.environ.get("HINDSIGHT_CONFIG") or Path.home() / ".hindsight/coding-agent.json")


def hindsight_port(config: dict) -> int:
    return config.get("apiPort") or 9077  # a stored null means the default, as jq's `.apiPort // 9077`


def _load_hindsight() -> dict | None:
    try:
        data = json.loads(hindsight_config().read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _read_hindsight(name: str, s: Setting) -> Value:
    config = _load_hindsight()
    if name == "daemon":
        path = hindsight_config()
        if not path.exists():
            state = "uninstalled" if Path(f"{path}.uninstalled").exists() else "not installed"
        else:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{hindsight_port(config or {})}/health", timeout=1) as r:
                    state = "running" if r.status == 200 else "down"
            except Exception:
                state = "down"
        return Value(s.id, state, Source.DEFAULT, None, False)
    if config is None:
        return Value(s.id, None, Source.UNSET, s.default, False)
    if name == "enabled":
        value = "" if config.get("disabled") is True else "true"
    elif name == "survey":
        value = "true" if config.get("codebaseSurvey") is True else ""
    else:
        value = "\n".join(config.get("optInPaths") or [])
    return Value(s.id, value, Source.SEED if value == s.default else Source.OVERRIDE, s.default, False)


def _write_hindsight(name: str, s: Setting, value: str) -> None:
    on = "on" if value == s.true_value else "off"
    if name == "enabled":
        _check(run(["hindsight-memory", on]))
    elif name == "survey":
        _check(run(["hindsight-memory", "survey", on]))
    elif name == "paths":
        stored = (_load_hindsight() or {}).get("optInPaths") or []
        wanted = [line.strip() for line in value.splitlines() if line.strip()]
        for p in (p for p in wanted if p not in stored):
            _check(run(["hindsight-memory", "paths", "add", p]))
        for p in (p for p in stored if p not in wanted):
            _check(run(["hindsight-memory", "paths", "remove", p]))
    else:
        raise SettingsError(f"{s.id} is read-only")


TOOLS: dict[str, tuple[Reader, Writer | None, Resetter | None]] = {
    "hindsight": (_read_hindsight, _write_hindsight, None),
}


def _tool(s: Setting) -> tuple[str, tuple[Reader, Writer | None, Resetter | None]]:
    tool, _, name = s.key.partition(":")
    if tool not in TOOLS:
        raise SettingsError(f"{s.id}: unknown tool {tool!r}")
    return name, TOOLS[tool]


class ToolAdapter:
    def read(self, s: Setting) -> Value:
        name, (reader, _, _) = _tool(s)
        return reader(name, s)

    def write(self, s: Setting, value: str) -> None:
        name, (_, writer, _) = _tool(s)
        if writer is None:
            raise SettingsError(f"{s.id} is read-only")
        writer(name, s, value)

    def reset(self, s: Setting) -> None:
        name, (_, _, resetter) = _tool(s)
        if resetter:
            resetter(name, s)
        else:
            self.write(s, self.read(s).seed or "")
