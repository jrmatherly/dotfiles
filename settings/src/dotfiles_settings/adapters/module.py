"""The module switches. bin/lib/rotm-modules owns the off list and the line that tells mise which files to skip.
Both files are git-ignored, so an installed copy can keep them too."""
from pathlib import Path

from .. import mise, profile
from ..model import InvalidValue, Setting, SettingsError, Source, Value
from .tool import _check, run

HELPER = "lib/rotm-modules"
NOTE = ("Turning a module on installs it at the next rotm update or setup.sh. Turning one off installs nothing "
        "more for it, and no package is uninstalled: `mise bootstrap packages prune --dry-run` lists every package "
        "no config declares, for all modules at once. The next sysup removes its mise tools.")


class ModuleAdapter:
    def write_note(self, s: Setting) -> str:
        return NOTE

    def watch_paths(self) -> list[Path]:
        name = profile.active()
        return [mise.config_dir() / "modules-off.local", profile.miserc(),
                *([mise.config_dir() / profile.modules_off_name(name)] if name else [])]

    def read(self, s: Setting) -> Value:
        try:
            off = _check(run([HELPER, "off"])).split()
        except (OSError, SettingsError):
            return Value(s.id, None, Source.UNSET, s.default, False)
        value = "" if s.key in off else s.true_value
        return Value(s.id, value, Source.SEED if value == s.default else Source.OVERRIDE, s.default, False)

    def write(self, s: Setting, value: str) -> None:
        if value not in (s.true_value, ""):
            raise InvalidValue(f"{s.id}: on or off, not {value!r}")
        _check(run([HELPER, "set", s.key, "on" if value == s.true_value else "off"],
                   env={"ROTM_SHARED": "1"} if profile.shared else None))

    def reset(self, s: Setting) -> None:
        self.write(s, s.true_value)
