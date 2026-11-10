"""Package state per manager from `mise bootstrap packages status`, and the [tools] from `mise ls --global`.
Read-only: a package has no value to set, and removing one is `mise bootstrap packages prune`, not a reset."""
import json, time

from .. import mise
from ..model import Setting, SettingsError, Source, Value

MANAGERS = ("brew", "brew-cask", "vscode")
TTL = 5.0
NAMED = 10


def summarize(packages: list[dict]) -> tuple[str, bool]:
    bad = [p for p in packages if p.get("state") != "installed"]
    value = f"{len(packages) - len(bad)} installed"
    if not bad:
        return value, False
    names = ", ".join(f"{p['package']} ({p.get('state')})" for p in bad[:NAMED])
    more = f", and {len(bad) - NAMED} more" if len(bad) > NAMED else ""
    return f"{value}, {len(bad)} not: {names}{more}", True


def last_line(e: SettingsError) -> str:
    lines = str(e).strip().splitlines()
    return lines[-1] if lines else ""


def parse(args: list[str]) -> dict:
    try:
        return json.loads(mise.run_mise(args) or "{}")
    except json.JSONDecodeError as e:
        raise SettingsError(f"mise {' '.join(args)}: {e}") from None


class PackageAdapter:
    def __init__(self):
        self._status: tuple[float, dict | SettingsError] | None = None

    def status(self) -> dict | SettingsError:
        # One mise call serves all three manager rows; a failure is cached too, so it is not retried per row
        if self._status is None or time.monotonic() - self._status[0] > TTL:
            try:
                data = parse(["bootstrap", "packages", "status", "--json"])
            except SettingsError as e:
                data = e
            self._status = (time.monotonic(), data)
        return self._status[1]

    def read(self, s: Setting) -> Value:
        if s.key == "tools":
            try:
                tools = parse(["ls", "--global", "--json"])
            except SettingsError as e:
                return Value(s.id, f"ls failed: {last_line(e)}", Source.UNSET, None, True)
            versions = [(name, v) for name, vs in tools.items() for v in vs]
            bad = [f"{name}@{v.get('requested_version') or v.get('version')}" for name, v in versions
                   if not v.get("installed")]
            value = f"{len(versions) - len(bad)} installed" + (f", {len(bad)} not: {', '.join(bad)}" if bad else "")
            return Value(s.id, value, Source.SEED, value, bool(bad))
        status = self.status()
        if isinstance(status, SettingsError):
            return Value(s.id, f"status failed: {last_line(status)}", Source.UNSET, None, True)
        manager = status.get(s.key)
        if not manager or not manager.get("available"):
            return Value(s.id, "not available", Source.UNSET, None, False)
        packages = manager.get("packages", [])
        value, drift = summarize(packages)
        homebrew = sum(p.get("managed_by") == "homebrew" for p in packages)
        if s.key == "brew-cask" and homebrew:
            value += f"; {homebrew} still managed by Homebrew"
        return Value(s.id, value, Source.SEED, value, drift)

    def write(self, s: Setting, value: str) -> None:
        raise SettingsError(f"{s.id} is read-only: edit tilde/.config/mise/conf.d/30-packages.toml")

    def reset(self, s: Setting) -> None:
        raise SettingsError(f"{s.id} is read-only: edit tilde/.config/mise/conf.d/30-packages.toml")

    def apply(self, settings: list[Setting]) -> list[str]:
        # Installs what is missing; never upgrades or prunes
        keys = {s.key for s in settings}
        lines = []
        for key in (*MANAGERS, "tools"):
            if key not in keys:
                continue
            args = ["install", "--yes"] if key == "tools" else ["bootstrap", "packages", "apply", "--yes", "--manager", key]
            try:
                mise.run_mise(args)
            except SettingsError as e:
                raise SettingsError(last_line(e)) from None
            lines.append(f"{key}: applied")
        self._status = None
        return lines
