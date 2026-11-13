"""Sync of the user's folder through a private GitHub repository (on, off, now, status, apply), and the tool
settings mise cannot hold: recorded in tools.toml in that folder and replayed on another Mac. A profile
(profile.py) has its own tools file there, laid over the shared one."""
import json, os, re, subprocess, sys, tomllib
from collections.abc import Callable
from pathlib import Path

from . import mise
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
    # json.dumps of a str is a TOML basic string once DEL is escaped; ensure_ascii would write surrogates TOML refuses
    basic = lambda v: json.dumps(v, ensure_ascii=False).replace("\x7f", "\\u007f")
    render = lambda t: "[tools]\n" + "".join(f"{basic(k)} = {basic(v)}\n" for k, v in sorted(t.items()))
    edit_file(path, lambda text: render(change(_parse(text, path))))


def _target_tools() -> Path:
    from . import profile  # here, not at the top: profile.py imports this module
    name = profile.target()
    return profile.tools_path(name) if name else tools_path()


def wanted_tools() -> Tools:
    """The tool settings in effect: the shared file's, with the active profile's laid over them."""
    from . import profile
    name = profile.active()
    return {**_load(tools_path()), **(_load(profile.tools_path(name)) if name else {})}


def masked(s: Setting) -> bool:
    """Whether a --shared write of s is hidden by the active profile's own value."""
    from . import profile
    name = profile.active()
    return bool(profile.shared and name and s.id in _load(profile.tools_path(name)))


def record(s: Setting, value: str) -> None:
    if s.scope == "machine":
        return
    _save(_target_tools(), lambda t: {**t, s.id: value})
    if not masked(s):  # tools.applied.toml is what this Mac's tools hold, one file whatever the profile
        _save(applied_path(), lambda t: {**t, s.id: value})


def forget(s: Setting) -> None:
    if s.scope == "machine":
        return
    drop = lambda t: {k: v for k, v in t.items() if k != s.id}
    # The profile's value first, then the shared one, as a reset of an env setting does
    path = next((p for p in (_target_tools(), tools_path()) if s.id in _load(p)), None)
    if path:
        _save(path, drop)
    # Still applied while another layer sets it: the shared file under a profile's, or the profile's under --shared
    want = wanted_tools().get(s.id)
    if want is not None:
        _save(applied_path(), lambda t: {**t, s.id: want})
    elif s.id in _load(applied_path()):
        _save(applied_path(), drop)


def replay(settings: list[Setting], adapters: dict[str, Adapter]) -> list[str]:
    by_id = {s.id: s for s in settings}
    wanted, applied = wanted_tools(), _load(applied_path())
    lines, done = [], {}
    for id, value in sorted(wanted.items()):
        if id not in by_id:
            lines.append(f"Skipped {id}: this version has no such setting.")
            continue
        s = by_id[id]
        try:
            if adapters[s.kind].read(s).value != value:
                adapters[s.kind].write(s, value)
                lines.append(f"Set {id} to your saved value.")
            done[id] = value
        except SettingsError as e:
            lines.append(f"Could not apply {id}: {e}")
    for id in sorted(applied.keys() - wanted.keys()):
        if id not in by_id:
            lines.append(f"Skipped {id}: this version has no such setting.")
            continue
        try:
            adapters[by_id[id].kind].reset(by_id[id])
            lines.append(f"Reset {id}: your saved settings no longer change it.")
        except SettingsError as e:
            done[id] = applied[id]  # still applied here, so the next replay tries the reset again
            lines.append(f"Could not apply {id}: {e}")
    _save(applied_path(), lambda _: done)
    return lines


KEPT = ("config.override.toml", "modules-off.local", "tools.toml")
# A profile's three files (profile.py)
KEPT_PROFILE = re.compile(r"config\.rotm-p-[a-z0-9-]+\.override\.toml|modules-off\.rotm-p-[a-z0-9-]+\.local"
                          r"|tools\.rotm-p-[a-z0-9-]+\.toml")
# bin/claude-config's rule for env keys, plus PASSWORD and ACCESS_KEY
SECRET = re.compile(r"(TOKEN|SECRET|PASSPHRASE|PASSWORD|API_KEY|ACCESS_KEY|CLIENT_KEY)$", re.I)
LOGIN = ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"]
NOT_CONNECTED = "no setup repository is connected"
NO_CONFLICT = "no sharing conflicts"
CONFLICT = "Conflict: "  # how mise 2026.11.8 lists a held conflict
# Not --keep-local: on a Mac connected onto a different file it needs a save, and that save breaks the history
DECIDE = ("Your saved settings and this Mac's differ in the files above, and neither was overwritten. "
          "To keep the saved copy of a file, run `mise dot pull --take-remote <file>`. To keep this Mac's, copy "
          "the file somewhere else first, run the same command, and copy yours back. Then run "
          "`rotm settings sync now`.")
INSTALL = "Nothing was installed or removed. Run `rotm install` to install what is now on."
DEFAULTS = "macOS preferences changed. Run `set-defaults` to write them."


def _call(*argv: str) -> subprocess.CompletedProcess[str]:
    # From $HOME, like mise.run_mise
    try:
        return subprocess.run(argv, capture_output=True, text=True, cwd=Path.home())
    except FileNotFoundError:
        raise SettingsError(f"{argv[0]} is not on PATH") from None


def _gh(*args: str) -> subprocess.CompletedProcess[str]:
    return _call(os.environ.get("DOTFILES_SETTINGS_GH", "gh"), *args)


def _mise_call(*args: str) -> subprocess.CompletedProcess[str]:
    return _call(os.environ.get("DOTFILES_SETTINGS_MISE", "mise"), *args)


def _text(*args: str) -> str:
    """Both streams of a mise call whatever its exit code: mise prints some answers on stderr."""
    r = _mise_call(*args)
    return r.stdout + r.stderr


def _helper(*argv: str) -> str:
    from .adapters.tool import _check, run  # here, not at the top: tool.py imports this module
    return _check(run(list(argv)))


def _toml(path: Path) -> dict:
    try:
        return tomllib.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as e:
        raise SettingsError(f"{path} is not valid TOML: {e}") from None


def _guard() -> None:
    folder = user_dir()
    names = sorted(p.name for p in folder.iterdir()) if folder.is_dir() else []
    stray = [n for n in names if n not in KEPT and not KEPT_PROFILE.fullmatch(n)]
    if stray:
        raise SettingsError(f"{folder} holds {', '.join(stray)}. Sync would keep it in the settings repository's "
                            "history for good, so move it out of that folder and run this again.")
    from . import registry
    machine = {s.key: s.id for s in registry.load() if s.kind == "env" and s.scope == "machine"}
    for name in ["config.override.toml", *(n for n in names if n.endswith(".override.toml") and n not in KEPT)]:
        override, shared = folder / name, name in KEPT
        # `mise unset --override` and `rotm settings set` on a single-Mac setting only reach the shared file
        unset = "mise unset --override" if shared else f"mise unset --file {override}"
        env = _toml(override).get("env", {})
        keys = [k for t in (env if isinstance(env, list) else [env]) if isinstance(t, dict) for k in t]
        secrets = sorted(k for k in keys if SECRET.search(k))
        if secrets:
            raise SettingsError(f"{', '.join(secrets)} in {override} looks like a secret, and sync "
                                f"would keep it in the settings repository's history for good. Run `{unset} "
                                f"{' '.join(secrets)}`, keep it in ~/.zsh.local instead, and run this again.")
        # Left there by a version from before scope existed
        left = sorted(k for k in keys if k in machine)
        if left and shared:
            raise SettingsError(f"{', '.join(left)} in {override} describes this Mac, and sync would carry it to your "
                                "next Mac. Run " + ", ".join(f"`rotm settings set {machine[k]} <value>`" for k in left)
                                + ", which moves it to config.local.toml, and run this again.")
        if left:
            raise SettingsError(f"{', '.join(left)} in {override} describes this Mac, and sync would carry it to your "
                                f"next Mac. Run `{unset} {' '.join(left)}` and run this again.")


def _stop_on_conflict() -> None:
    r = _mise_call("dot", "conflicts")
    out = (r.stdout + r.stderr).strip()
    if CONFLICT in out:
        raise SettingsError(f"{out}\n{DECIDE}")
    if out and r.returncode != 0:
        raise SettingsError(out)


def _mise(*args: str) -> None:
    try:
        mise.run_mise(list(args))
    except SettingsError:
        _stop_on_conflict()  # a paused sync can exit 1; the conflict is the useful message
        raise


def _sign_in() -> None:
    if _gh("auth", "status").returncode == 0:
        return
    login = "gh " + " ".join(LOGIN)
    if not sys.stdin.isatty():
        raise SettingsError(f"gh is not signed in to GitHub. Run `{login}`, then run this again.")
    if subprocess.run([os.environ.get("DOTFILES_SETTINGS_GH", "gh"), *LOGIN], cwd=Path.home()).returncode != 0:
        raise SettingsError(f"The GitHub sign-in did not finish. Run `{login}`, then run this again.")


def on(repo: str) -> list[str]:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", repo):
        raise SettingsError(f"--repo takes the name of a repository in your own account, such as rotm-settings, "
                            f"not {repo!r}")
    _sign_in()
    r = _gh("api", "user", "--jq", ".login")
    if r.returncode != 0:
        raise SettingsError(f"gh could not read your GitHub login: {r.stderr.strip()}")
    login = r.stdout.strip()
    name, url = f"{login}/{repo}", f"https://github.com/{login}/{repo}.git"
    # A failed lookup is taken as no repository: gh repo create then fails with gh's reason if one exists
    lookup = _gh("repo", "view", name, "--json", "isEmpty", "--jq", ".isEmpty")
    empty = lookup.stdout.strip() == "true"
    if lookup.returncode == 0:
        # One we did not create may be public, and connecting it would publish the folder's whole history
        if _gh("repo", "view", name, "--json", "visibility", "--jq", ".visibility").stdout.strip() != "PRIVATE":
            raise SettingsError(f"{name} is not a private repository, and your settings would be public in it. "
                                f"Run `gh repo edit {name} --visibility private "
                                "--accept-visibility-change-consequences`, or pass `--repo <another name>`.")
    if lookup.returncode == 0 and not empty:
        if _gh("api", f"repos/{name}/contents/.mise-history/format.toml").returncode != 0:
            raise SettingsError(f"{name} is not a settings repository. Pass `--repo <another name>`.")
        try:
            _helper("lib/rotm-user-layer", "restore", url)
        except SettingsError:
            _stop_on_conflict()
            raise
        return [f"Loaded your saved settings from {name}.", *apply(),
                "Sync is on, and it runs when you ask: run `rotm settings sync now` after you change a setting."]
    lines = []
    if lookup.returncode != 0:
        r = _gh("repo", "create", repo, "--private")
        if r.returncode != 0:
            raise SettingsError(f"gh could not create the private repository {name}: {r.stderr.strip()}")
        lines.append(f"Created the private repository {name}.")
    _helper("lib/rotm-user-layer", "ensure")
    _guard()
    _helper("lib/rotm-user-layer", "track")
    _mise("dot", "save")
    _mise("dot", "origin", "set", url, "--sync", "manual", "--yes")
    _mise("dot", "sync")
    _stop_on_conflict()
    _remember()  # this Mac's choices are already in effect, so its first apply has nothing to announce
    return lines + [f"Your settings are saved in {name}. Sync is on, and it runs when you ask: run "
                    "`rotm settings sync now` after you change a setting, and `rotm settings sync on` on your next "
                    "Mac to load them there."]


def now() -> list[str]:
    if NOT_CONNECTED in _text("dot", "origin"):
        raise SettingsError("Sync is not connected. Run `rotm settings sync on` first.")
    _guard()
    _stop_on_conflict()  # a save while sync on's conflict is held starts a history unrelated to the origin's
    _mise("dot", "save")
    _mise("dot", "sync")
    _mise("dot", "pull")
    _stop_on_conflict()
    # A profile another Mac made arrives in the folder with no link in the config dir: mise would not load it
    _helper("lib/rotm-user-layer", "ensure")
    return [*apply(), "Saved and synced: this Mac and your settings repository hold the same settings."]


def status() -> list[str]:
    origin = _text("dot", "origin").strip().partition("\n")[0]
    if NOT_CONNECTED in origin:
        return ["Sync is not connected. Run `rotm settings sync on` to save your settings to a private GitHub "
                "repository."]
    waiting = [l.strip() for l in _text("dot", "status").splitlines() if "unsaved" in l or "pending" in l]
    conflicts = _text("dot", "conflicts").strip()
    lines = [f"Sync is on: {origin}", *waiting]
    if waiting:
        lines.append("Run `rotm settings sync now` to save and share them.")
    if CONFLICT in conflicts:
        lines += [conflicts, DECIDE]
    elif conflicts and NO_CONFLICT not in conflicts:
        lines.append(conflicts)
    return lines


def off() -> list[str]:
    mise.run_mise(["dot", "origin", "--remove"])
    return [f"Sync is off. Your settings stay in {user_dir()}, and the repository keeps its history. "
            "Run `rotm settings sync on` to connect again."]


def _merge(under, over):
    if isinstance(under, dict) and isinstance(over, dict):
        return {k: _merge(under.get(k), over[k]) if k in over else under[k] for k in under.keys() | over.keys()}
    return under if over is None else over


def _effective() -> dict:
    """What apply cannot act on itself, from the files in effect: the active profile's override file laid over the
    shared one, and the module list rotm-modules uses. off, packages and disable_tools are what rotm install acts
    on, macos what set-defaults writes."""
    from . import profile
    name, cfg = profile.active(), mise.config_dir()
    o = _merge(_toml(cfg / "config.override.toml"), _toml(profile.override_path(name)) if name else {})
    boot = o.get("bootstrap", {})
    off = cfg / profile.modules_off_name(name) if name else None
    if not (off and off.exists()):
        off = cfg / "modules-off.local"
    return {"off": off.read_text().split() if off.exists() else [], "packages": boot.get("packages"),
            "disable_tools": o.get("settings", {}).get("disable_tools"),
            "macos": boot.get("settings", {}).get("macos", {}).get("defaults")}


def _effective_path() -> Path:
    return applied_path().parent / "effective.applied.json"


def _remember(effective: dict | None = None) -> None:
    effective, path = effective or _effective(), _effective_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(effective, sort_keys=True) + "\n")
    for old in ("config.override.toml.applied", "modules-off.local.applied"):  # what apply kept before profiles
        (path.parent / old).unlink(missing_ok=True)


def apply() -> list[str]:
    from . import registry
    from .adapters import ADAPTERS  # here, not at the top: the adapters import this module
    _helper("lib/rotm-modules", "sync")
    lines = replay(registry.load(), ADAPTERS)
    now_, was = _effective(), {"off": [], "packages": None, "disable_tools": None, "macos": None}
    try:
        was = json.loads(_effective_path().read_text())
    except (OSError, ValueError):
        pass
    install = ("off", "packages", "disable_tools")
    # setup.sh sets it when it has just installed with these files, where the line would be false
    if any(now_[k] != was.get(k) for k in install) and not os.environ.get("ROTM_JUST_INSTALLED"):
        lines.append(INSTALL)
    if now_["macos"] != was.get("macos"):
        lines.append(DEFAULTS)
    _remember(now_)
    return lines
