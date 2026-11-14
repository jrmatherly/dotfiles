"""The dotfiles-settings command: list, get, set, reset, apply, status, sync, profile, tui and serve. Exit codes 0 ok, 1 failure,
2 unknown id, invalid value or refused profile name, 3 read-only."""
import argparse, importlib, json, os, re, subprocess, sys
from pathlib import Path

from . import mise, profile, registry, sync
from .adapters import ADAPTERS, tool
from .model import InvalidValue, Setting, SettingsError, Value, note_for

TRUE = ("true", "on", "yes", "1")
FALSE = ("false", "off", "no", "0")


class ReadOnly(SettingsError):
    """A set or reset of an ro setting (exit 3)."""


def normalize(s: Setting, raw: str) -> str:
    if s.type == "bool":
        if raw.lower() in TRUE:
            return s.true_value
        if raw.lower() in FALSE:
            return ""
        raise InvalidValue(f"{s.id}: expected on or off, got {raw!r}")
    if s.type == "int":
        if not re.fullmatch(r"-?[0-9]+", raw):
            raise InvalidValue(f"{s.id}: expected a whole number, got {raw!r}")
        return str(int(raw))
    if s.type == "enum":
        if raw not in s.choices:
            raise InvalidValue(f"{s.id}: expected one of {', '.join(s.choices)}, got {raw!r}")
        return raw
    if s.type == "path":
        path = os.path.expanduser(raw)
        if not os.path.isabs(path):
            raise InvalidValue(f"{s.id}: expected an absolute path, got {raw!r}")
        return path
    return raw


def to_json(s: Setting, v: Value) -> dict:
    seats, role = s.widget == "seats", s.key.partition(":")[2]
    return {"setting_id": s.id, "value": v.value, "source": v.source.value, "seed": v.seed, "drift": v.drift,
            "label": s.label, "section": s.section, "type": s.type, "choices": list(s.choices),
            "widget": s.widget, "access": s.access, "help": s.help, "kind": s.kind, "scope": s.scope,
            "seat_models": tool.seat_models(role) if seats else [], "seat_efforts": list(tool.EFFORTS) if seats else [],
            "seat_list": seats and role in tool.LIST_ROLES}


def git(*args: str) -> str | None:
    dotfiles = os.environ.get("DOTFILES")
    if not dotfiles:
        return None
    try:
        r = subprocess.run(["git", "-C", dotfiles, *args], capture_output=True, text=True)
    except FileNotFoundError:
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def status() -> dict:
    dotfiles = os.environ.get("DOTFILES")
    return {"mode": "installed" if dotfiles and mise.installed(Path(dotfiles)) else "clone",
            "branch": git("symbolic-ref", "-q", "--short", "HEAD"), "commit": git("rev-parse", "--short", "HEAD"),
            "profile": profile.state(), "sync": sync.state()}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dotfiles-settings", description="See and change this dotfiles repo's settings.")
    sub = p.add_subparsers(dest="command", required=True)
    c = sub.add_parser("list", help="every setting with its value and source")
    c.add_argument("--section")
    c.add_argument("--json", action="store_true")
    c = sub.add_parser("get", help="one setting's value")
    c.add_argument("id")
    c.add_argument("--json", action="store_true")
    c = sub.add_parser("set", help="change a setting")
    c.add_argument("id")
    c.add_argument("value")
    shared = "with a profile active, change the shared settings instead of the profile's"
    c.add_argument("--shared", action="store_true", help=shared)
    c = sub.add_parser("reset", help="go back to what the shell files set")
    c.add_argument("id")
    c.add_argument("--shared", action="store_true", help=shared)
    c = sub.add_parser("apply", help="apply the settings of one kind")
    c.add_argument("kind")
    c = sub.add_parser("status", help="this copy's mode, branch and commit, the profile in use and the sync state")
    c.add_argument("--json", action="store_true")
    c = sub.add_parser("sync", help="keep your settings in a private GitHub repository and load them on another Mac")
    c.add_argument("action", choices=("on", "off", "now", "status", "apply"))
    c.add_argument("--repo", default="rotm-settings", help="the repository's name in your account (sync on)")
    c = sub.add_parser("profile", help="keep named variants of your settings, such as personal and work")
    actions = c.add_subparsers(dest="action", required=True)
    actions.add_parser("list", help="every profile, the active one marked")
    for action, text in (("use", "switch to a profile, or to default for the shared settings alone"),
                         ("new", "make a profile")):
        actions.add_parser(action, help=text).add_argument("name")
    sub.add_parser("tui", help="open the terminal UI")
    c = sub.add_parser("serve", help="open the UI in a browser tab")
    c.add_argument("--no-open", action="store_true")
    return p


def find(settings: list[Setting], id: str) -> Setting:
    for s in settings:
        if s.id == id:
            return s
    raise InvalidValue(f"unknown setting {id!r}")


def writable(settings: list[Setting], id: str) -> Setting:
    s = find(settings, id)
    if s.access == "ro":
        raise ReadOnly(f"{id} is read-only")
    return s


def run(args: argparse.Namespace) -> None:
    mise.check_version()
    if args.command == "tui":
        ui("tui").run()
        return
    if args.command == "serve":
        ui("serve").run(not args.no_open)
        return
    if args.command == "status":
        st = status()
        if args.json:
            print(json.dumps(st, indent=2))
            return
        sync_line = st["sync"]["origin"] if st["sync"]["connected"] else "not connected"
        print(f"Mode: {st['mode']}\nBranch: {st['branch'] or 'none'}\nCommit: {st['commit'] or 'none'}\n"
              f"Profile: {st['profile']['active']}\nSync: {sync_line}")
        return
    if args.command == "sync":
        lines = sync.on(args.repo) if args.action == "on" else getattr(sync, args.action)()
        print("\n".join(lines) if lines else "Nothing to apply: your saved settings are already in effect here.")
        return
    if args.command == "profile":
        print("\n".join(profile.listing() if args.action == "list" else getattr(profile, args.action)(args.name)))
        return
    settings = registry.load()
    if args.command == "list":
        if args.section:
            settings = [s for s in settings if s.section.lower() == args.section.lower()]
            if not settings:
                raise InvalidValue(f"unknown section {args.section!r}")
        rows = [(s, ADAPTERS[s.kind].read(s)) for s in settings]
        if args.json:
            print(json.dumps([to_json(s, v) for s, v in rows], indent=2))
        else:
            for s, v in rows:
                print(f"{s.id}\t{v.value or ''}\t{v.source.value}")
    elif args.command == "get":
        s = find(settings, args.id)
        v = ADAPTERS[s.kind].read(s)
        print(json.dumps(to_json(s, v), indent=2) if args.json else v.value or "")
    elif args.command in ("set", "reset"):
        s = writable(settings, args.id)
        adapter = ADAPTERS[s.kind]
        profile.shared = args.shared
        if args.command == "set":
            adapter.write(s, normalize(s, args.value))
        else:
            adapter.reset(s)
        if note := note_for(adapter, s):
            print(note, file=sys.stderr)
    elif args.command == "apply":
        if args.kind not in ADAPTERS:
            raise InvalidValue(f"unknown kind {args.kind!r}")
        apply = getattr(ADAPTERS[args.kind], "apply", None)
        lines = apply([s for s in settings if s.kind == args.kind]) if apply else []
        print("\n".join(lines) if lines else f"{args.kind}: nothing to apply")


def ui(name: str):
    # Textual is imported only here, so the rest of the CLI runs on the standard library alone
    try:
        return importlib.import_module(f".{name}", __package__)
    except ImportError as e:
        if (e.name or "").split(".")[0] in ("textual", "textual_serve"):
            raise SettingsError("tui and serve need Textual. Run bin/dotfiles-settings, or install the package with uv.") from None
        raise


def main(argv: list[str] | None = None) -> None:
    args = parser().parse_args(argv)
    try:
        run(args)
    except SettingsError as e:
        print(f"dotfiles-settings: {e}", file=sys.stderr)
        raise SystemExit(3 if isinstance(e, ReadOnly) else 2 if isinstance(e, InvalidValue) else 1) from None
    raise SystemExit(0)
