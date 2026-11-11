"""Coding-agent settings: each tool's own file is read directly and written through its CLI where it has one."""
import os, shutil, subprocess, tempfile
from collections.abc import Callable
from pathlib import Path

from ..model import Setting, SettingsError, Value

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


TOOLS: dict[str, tuple[Reader, Writer | None, Resetter | None]] = {}


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
