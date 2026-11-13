"""Sync of the user's folder through a private GitHub repository (on, off, now, status, apply), and the tool
settings mise cannot hold: recorded in tools.toml in that folder and replayed on another Mac."""
import json, os, re, shutil, subprocess, sys, tomllib
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
SECRET = re.compile(r"(TOKEN|SECRET|PASSPHRASE|API_KEY|CLIENT_KEY)$")  # bin/claude-config's rule for env keys
LOGIN = ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"]
NOT_CONNECTED = "no setup repository is connected"
NO_CONFLICT = "no sharing conflicts"
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


def _text(*args: str) -> str:
    """Both streams of a mise call whatever its exit code: mise prints some answers on stderr."""
    r = _call(os.environ.get("DOTFILES_SETTINGS_MISE", "mise"), *args)
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
    stray = sorted(p.name for p in folder.iterdir() if p.name not in KEPT) if folder.is_dir() else []
    if stray:
        raise SettingsError(f"{folder} holds {', '.join(stray)}. Sync would keep it in the settings repository's "
                            "history for good, so move it out of that folder and run this again.")
    env = _toml(folder / "config.override.toml").get("env", {})
    secrets = sorted(k for k in env if SECRET.search(k))
    if secrets:
        raise SettingsError(f"{', '.join(secrets)} in {folder / 'config.override.toml'} looks like a secret, and sync "
                            "would keep it in the settings repository's history for good. Run `mise unset --override "
                            f"{' '.join(secrets)}`, keep it in ~/.zsh.local instead, and run this again.")


def _stop_on_conflict() -> None:
    out = _text("dot", "conflicts").strip()
    if out and NO_CONFLICT not in out:
        raise SettingsError(f"{out}\n{DECIDE}")


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
    if conflicts and NO_CONFLICT not in conflicts:
        lines += [conflicts, DECIDE]
    return lines


def off() -> list[str]:
    mise.run_mise(["dot", "origin", "--remove"])
    return [f"Sync is off. Your settings stay in {user_dir()}, and the repository keeps its history. "
            "Run `rotm settings sync on` to connect again."]


def _changes(override: Path, modules_off: Path) -> tuple:
    """What apply cannot act on itself: (what rotm install acts on, what set-defaults writes)."""
    o = _toml(override)
    boot = o.get("bootstrap", {})
    off = modules_off.read_text().split() if modules_off.exists() else []
    return ((off, boot.get("packages"), o.get("settings", {}).get("disable_tools")),
            boot.get("macos", {}).get("defaults"))


def _snapshot() -> tuple[tuple[Path, ...], tuple[Path, ...]]:
    """The two files apply compares, and its copies of them from the last apply."""
    live = (mise.config_dir() / "config.override.toml", mise.config_dir() / "modules-off.local")
    return live, tuple(applied_path().parent / f"{p.name}.applied" for p in live)


def _remember() -> None:
    for src, copy in zip(*_snapshot()):
        copy.parent.mkdir(parents=True, exist_ok=True)
        if src.exists():
            shutil.copyfile(src, copy)
        else:
            copy.unlink(missing_ok=True)


def apply() -> list[str]:
    from . import registry
    from .adapters import ADAPTERS  # here, not at the top: the adapters import this module
    _helper("lib/rotm-modules", "sync")
    lines = replay(registry.load(), ADAPTERS)
    live, copies = _snapshot()
    (install, macos), (install_was, macos_was) = _changes(*live), _changes(*copies)
    # setup.sh sets it when it has just installed with these files, where the line would be false
    if install != install_was and not os.environ.get("ROTM_JUST_INSTALLED"):
        lines.append(INSTALL)
    if macos != macos_was:
        lines.append(DEFAULTS)
    _remember()
    return lines
