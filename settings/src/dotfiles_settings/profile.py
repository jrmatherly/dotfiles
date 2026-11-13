"""Profiles: named variants of one user's settings, such as personal and work.

A profile is a mise config environment, rotm-p-<name>, named in the env list of miserc.local.toml. Its settings
are mise's per-environment override file, which mise ranks above the shared config.override.toml, so a profile
holds only what differs. The module off list and the recorded tool settings get a file per profile, since mise
has no per-environment form for either."""
import os, re, tomllib
from pathlib import Path

from . import mise, sync
from .model import InvalidValue, SettingsError

# A bare name in the env list would also load a project's mise.<name>.toml
PREFIX = "rotm-p-"
DEFAULT = "default"  # no profile: the shared settings alone
NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,30}")
ENV_LINE = re.compile(r"^[ \t]*env[ \t]*=.*\n?", re.M)

shared = False  # set by --shared: writes go to the shared files while a profile is active


def miserc() -> Path:
    return mise.config_dir() / "miserc.local.toml"


def selected() -> list[str]:
    """The saved env list."""
    try:
        env = tomllib.loads(miserc().read_text()).get("env", [])
    except FileNotFoundError:
        return []
    except tomllib.TOMLDecodeError as e:
        raise SettingsError(f"{miserc()} is not valid TOML: {e}") from None
    if not (isinstance(env, list) and all(isinstance(e, str) for e in env)):
        raise SettingsError(f"env in {miserc()} is not a list of names")
    return env


def active() -> str | None:
    """The profile in effect: the last rotm-p- entry of the env list mise uses, which is MISE_ENV where a shell
    sets it and the saved list otherwise."""
    env = os.environ.get("MISE_ENV")
    names = [e.strip() for e in env.split(",")] if env else selected()
    return next((e[len(PREFIX):] for e in reversed(names) if e.startswith(PREFIX)), None)


def target() -> str | None:
    """The profile writes go to."""
    return None if shared else active()


def override_path(name: str) -> Path:
    return mise.config_dir() / f"config.{PREFIX}{name}.override.toml"


def settings_file(name: str) -> Path:
    """A profile's override file for a write. mise would create a missing one in the config dir, which on an
    installed copy is the checkout, so a profile whose file is not on this Mac is refused."""
    path = override_path(name)
    if not (path.exists() or path.is_symlink()):
        raise SettingsError(f"the profile {name} has no settings file on this Mac. Run `rotm settings sync now` to "
                            f"fetch it, or `rotm settings profile use {DEFAULT}` to leave it")
    return path


def modules_off_name(name: str) -> str:
    return f"modules-off.{PREFIX}{name}.local"


def tools_path(name: str) -> Path:
    return sync.user_dir() / f"tools.{PREFIX}{name}.toml"


def names() -> list[str]:
    start, end = len(f"config.{PREFIX}"), -len(".override.toml")
    return sorted(p.name[start:end] for p in mise.config_dir().glob(f"config.{PREFIX}*.override.toml"))


def _ensure() -> None:
    # Links a profile's files into the config dir, so mise never creates one inside an installed copy's checkout
    sync._helper("lib/rotm-user-layer", "ensure")


def new(name: str) -> list[str]:
    if not NAME.fullmatch(name) or name == DEFAULT:
        raise InvalidValue(f"a profile name is 1 to 31 lowercase letters, digits or hyphens, starting with a letter "
                           f"or digit, and not {DEFAULT!r}: {name!r}")
    if name in names():
        raise InvalidValue(f"the profile {name} already exists")
    folder = sync.user_dir()
    folder.mkdir(parents=True, exist_ok=True)
    (folder / override_path(name).name).touch()
    # Its own copy: mise reads the skipped files from miserc only, so a module switch cannot fall through
    shared_off = mise.config_dir() / "modules-off.local"
    (folder / modules_off_name(name)).write_text(shared_off.read_text() if shared_off.exists() else "")
    _ensure()
    return [f"Made the profile {name}. Switch to it with `rotm settings profile use {name}`."]


def use(name: str) -> list[str]:
    path = miserc()
    text = path.read_text() if path.exists() else ""
    line = ENV_LINE.search(text)
    if line:
        try:
            tomllib.loads(line.group())
        except tomllib.TOMLDecodeError:
            raise SettingsError(f"the env list in {path} spans several lines; put it on one line and try again") from None
    _ensure()
    if name != DEFAULT and name not in names():
        raise InvalidValue(f"no profile named {name}. Profiles: {', '.join([DEFAULT, *names()])}")
    # apply reports what differs from the last state it saw, so it is shown this one: what the switch itself changes
    # is what `rotm install` and `set-defaults` have to act on
    sync._remember()
    was = selected()
    env = [e for e in was if not e.startswith(PREFIX)] + ([PREFIX + name] if name != DEFAULT else [])
    if env:
        # --only final-hook applies nothing; mise writes the line and keeps the rest of the file
        mise.run_mise(["-E", ",".join(env), "bootstrap", "--save-env", "--only", "final-hook"])
    elif was:
        # mise cannot save an empty list (it errors with no -E), so the line is removed here
        left = ENV_LINE.sub("", text, count=1)
        try:
            still = tomllib.loads(left).get("env")
        except tomllib.TOMLDecodeError:
            still = True
        if still:  # a quoted key, or a list under another spelling: nothing here can remove it safely
            raise SettingsError(f"could not remove the env list from {path}; edit it by hand")
        path.write_text(left)
    return [f"Now using {'the shared settings' if name == DEFAULT else f'the profile {name}'}.", *sync.apply(),
            "Open a new shell to pick this up."]


def listing() -> list[str]:
    current, have = active(), names()
    shown = current if current in have else None
    lines = [f"{'*' if n == (shown or DEFAULT) else ' '} {n}" for n in [DEFAULT, *have]]
    if current and current not in have:
        lines.append(f"The saved profile {current} has no settings file on this Mac.")
    if os.environ.get("MISE_ENV"):
        lines.append("MISE_ENV is set in this shell, and mise uses it in place of the saved profile.")
    return lines
