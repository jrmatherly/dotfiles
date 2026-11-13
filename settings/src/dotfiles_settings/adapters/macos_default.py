"""macOS preferences declared in mise's conf.d/20-macos.toml: read from `mise bootstrap macos defaults status`,
written by a one-line edit of the tracked fragment (on an installed copy, of the user's override file; with a
profile active, of that profile's override file) plus one `defaults write`."""
import copy, json, re, subprocess, sys, tomllib
from pathlib import Path

from .. import mise, profile
from ..model import InvalidValue, Setting, SettingsError, Source, Value
from .env import override_path
from .tool import edit_file

FLAGS = {"bool": "-bool", "int": "-int", "string": "-string", "enum": "-string", "path": "-string"}
RESTART = {"com.apple.dock": "Dock", "com.apple.finder": "Finder"}
BARE = re.compile(r"[A-Za-z0-9_-]+")
MISSING = object()


def fragment_path() -> Path:
    return mise.config_dir() / "conf.d" / "20-macos.toml"


def split_key(setting_key: str) -> tuple[str, str]:
    domain, sep, key = setting_key.partition("/")
    if not (sep and domain and key):
        raise SettingsError(f"macos-default key must be <domain>/<key>: {setting_key!r}")
    return domain, key


def to_literal(s: Setting, value: str) -> str:
    if s.type == "bool":
        if value == s.true_value:
            return "true"
        if value == "":
            return "false"
        raise InvalidValue(f"{s.id}: expected {s.true_value!r} or '', got {value!r}")
    if s.type == "int":
        try:
            return str(int(value))
        except ValueError:
            raise InvalidValue(f"{s.id}: expected a whole number, got {value!r}") from None
    return json.dumps(value)


def render(s: Setting, v) -> str:
    if isinstance(v, bool):
        return s.true_value if v else ""
    return v if isinstance(v, str) else str(v)


def parse_literal(literal: str):
    return tomllib.loads(f"v = {literal}")["v"]


# The one place the table's path is spelled. mise 2026.11.8 deprecates [bootstrap.macos.defaults]
TABLE = ("bootstrap", "settings", "macos", "defaults")


def _tables(data: dict) -> dict:
    for name in TABLE:
        data = data.setdefault(name, {})
    return data


def declared(text: str, domain: str, key: str):
    try:
        tables = _tables(tomllib.loads(text))
    except tomllib.TOMLDecodeError as e:
        raise SettingsError(f"20-macos.toml: {e}") from None
    for name, table in tables.items():
        if name.lower() == domain.lower() and isinstance(table, dict):
            return table.get(key, MISSING)
    return MISSING


def locate(lines: list[str], domain: str, key: str) -> tuple[int | None, int, int | None]:
    """The table's header index, the index its lines end before, and the key's line index."""
    name = re.escape(json.dumps(domain)) + (f"|{re.escape(domain)}" if BARE.fullmatch(domain) else "")
    header = re.compile(rf"\[\s*{re.escape('.'.join(TABLE))}\.(?:{name})\s*\]\s*(#.*)?")
    start = next((i for i, line in enumerate(lines) if header.fullmatch(line.strip())), None)
    if start is None:
        return None, len(lines), None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    line = re.compile(rf"\s*(?:{re.escape(key)}|{re.escape(json.dumps(key))})\s*=\s*")
    at = next((i for i in range(start + 1, end) if line.match(lines[i])), None)
    return start, end, at


def literal_end(line: str) -> int:
    """Where the value's literal ends on its line, before any trailing comment."""
    start = re.match(r"[^=]*=\s*", line).end()
    rest = line[start:].rstrip("\n")
    for i in [m.start() for m in re.finditer("#", rest)] + [len(rest)]:
        try:
            parse_literal(rest[:i])
        except tomllib.TOMLDecodeError:
            continue
        return start + len(rest[:i].rstrip())
    raise SettingsError(f"edit 20-macos.toml by hand: {line.split('=')[0].strip()} is not a one-line scalar")


def checked(text: str, out: str, domain: str, key: str, value=MISSING) -> str:
    want = copy.deepcopy(tomllib.loads(text))
    table = _tables(want).setdefault(domain, {})
    if value is MISSING:
        table.pop(key, None)
    else:
        table[key] = value
    try:
        ok = tomllib.loads(out) == want
    except tomllib.TOMLDecodeError:
        ok = False
    if not ok:
        raise SettingsError(f"could not edit {domain} {key} in 20-macos.toml cleanly, edit it by hand")
    return out


def set_key(text: str, domain: str, key: str, literal: str) -> str:
    new = parse_literal(literal)
    old = declared(text, domain, key)
    if old is not MISSING:
        if not isinstance(old, (bool, int, float, str)):
            raise SettingsError(f"edit 20-macos.toml by hand: {key} is not a one-line scalar")
        if type(old) is not type(new):
            raise InvalidValue(f"{domain} {key} is declared as {type(old).__name__}, not {type(new).__name__}")
    lines = text.splitlines(keepends=True)
    start, end, at = locate(lines, domain, key)
    name = key if BARE.fullmatch(key) else json.dumps(key)
    if at is not None:
        cut = literal_end(lines[at])
        lines[at] = lines[at][:re.match(r"[^=]*=\s*", lines[at]).end()] + literal + lines[at][cut:]
    elif start is not None:
        # after the table's last key, so comments that introduce the next table stay with it
        last = max((i for i in range(start, end) if lines[i].strip() and not lines[i].lstrip().startswith("#")))
        lines.insert(last + 1, f"{name} = {literal}\n")
    else:
        header = domain if BARE.fullmatch(domain) else json.dumps(domain)
        lines = [text.rstrip("\n") + "\n", f"\n[{'.'.join(TABLE)}.{header}]\n", f"{name} = {literal}\n"]
    return checked(text, "".join(lines), domain, key, new)


def remove_key(text: str, domain: str, key: str) -> str:
    old = declared(text, domain, key)
    if old is MISSING:
        return text
    lines = text.splitlines(keepends=True)
    _, _, at = locate(lines, domain, key)
    if at is None or not isinstance(old, (bool, int, float, str)):
        raise SettingsError(f"edit 20-macos.toml by hand: {key} is not a one-line scalar")
    literal_end(lines[at])
    del lines[at]
    return checked(text, "".join(lines), domain, key)


def head_text() -> str | None:
    path = fragment_path().resolve()
    try:
        top = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True)
        if top.returncode != 0:
            return None
        root = Path(top.stdout.strip())
        r = subprocess.run(["git", "-C", str(root), "show", f"HEAD:{path.relative_to(root)}"],
                           capture_output=True, text=True)
    except (OSError, ValueError):
        return None
    return r.stdout if r.returncode == 0 else None


def defaults_write(domain: str, key: str, flag: str, arg: str) -> None:
    try:
        r = subprocess.run(["defaults", "write", domain, key, flag, arg], capture_output=True, text=True)
    except OSError as e:
        raise SettingsError(f"defaults write {domain} {key}: {e}") from None
    if r.returncode != 0:
        raise SettingsError(r.stderr.strip() or f"defaults write {domain} {key} exited {r.returncode}")


def killall(app: str) -> None:
    try:
        subprocess.run(["killall", app], capture_output=True)
    except OSError:
        pass


def read_text(path: Path | None = None) -> str:
    """The fragment by default. A missing override file reads as empty."""
    path = path or fragment_path()
    try:
        return path.read_text()
    except OSError as e:
        if isinstance(e, FileNotFoundError) and path != fragment_path():
            return ""
        raise SettingsError(f"{path}: {e}") from None


def shared_target(domain: str, key: str) -> Path:
    """The file a change is written to with no profile: the override file on an installed copy or when it already
    declares the key (a clone that received it by sync), the tracked fragment otherwise."""
    if mise.installed(fragment_path()) or declared(read_text(override_path()), domain, key) is not MISSING:
        return override_path()
    return fragment_path()


def target(domain: str, key: str) -> Path:
    """The file a change is written to: the profile's override file when one is the target of writes."""
    name = profile.target()
    return profile.settings_file(name) if name else shared_target(domain, key)


def masked(domain: str, key: str) -> str | None:
    """The active profile, when a --shared write is hidden by that profile's own value for the key."""
    name = profile.active()
    if profile.shared and name and declared(read_text(profile.override_path(name)), domain, key) is not MISSING:
        return name
    return None


def put(path: Path, text: str) -> None:
    """Write text to the fragment as it is, or to an override file through its link, atomically and only on a change."""
    if path == fragment_path():
        path.write_text(text)
        return
    real = path.resolve()
    if not real.parent.is_dir():
        raise SettingsError(f"{path} links into {real.parent}, which does not exist. Run `sysup` to create it")
    if not real.exists():
        if not text:
            return
        real.touch()
    edit_file(path, lambda _: text)


def status_entries() -> list[dict]:
    out = mise.run_mise(["bootstrap", "macos", "defaults", "status", "--json"])
    try:
        data = json.loads(out or "{}")
    except json.JSONDecodeError as e:
        raise SettingsError(f"mise bootstrap macos defaults status --json: {e}") from None
    return data.get("macos_defaults", {}).get("entries", [])


class MacosDefaultAdapter:
    def write_note(self, s: Setting) -> str:
        if name := masked(*split_key(s.key)):
            return (f"Saved in {override_path()}, the shared settings. The profile {name} keeps its own value, which "
                    f"stays in effect there: `rotm settings reset {s.id}` removes it.")
        if name := profile.target():
            return f"Saved in {profile.override_path(name)}, the profile {name}'s settings, and wrote that one preference."
        if target(*split_key(s.key)) == fragment_path():
            return ("Edited tilde/.config/mise/conf.d/20-macos.toml, a tracked file, and wrote that one preference. "
                    "Commit the file to keep the change.")
        return f"Saved in {override_path()}, your own settings file, and wrote that one preference."

    def read(self, s: Setting) -> Value:
        domain, key = split_key(s.key)
        entry = next((e for e in status_entries() if str(e.get("domain", "")).lower() == domain.lower()
                      and e.get("key") == key and e.get("host") == "any" and e.get("path") is None), None)
        if entry is None:
            return Value(s.id, s.default or None, Source.DEFAULT if s.default else Source.UNSET, None, False)
        value, drift = render(s, entry["value"]), entry.get("state") != "set"
        name = profile.active()
        if any(declared(read_text(p), domain, key) is not MISSING
               for p in ([profile.override_path(name)] if name else []) + [override_path()]):
            seed = declared(read_text(), domain, key)
            return Value(s.id, value, Source.OVERRIDE, None if seed is MISSING else render(s, seed), drift)
        head = head_text()
        if head is None:
            return Value(s.id, value, Source.SEED, None, drift)
        old = declared(head, domain, key)
        if old is MISSING:
            return Value(s.id, value, Source.OVERRIDE, None, drift)
        same = old == entry["value"] and type(old) is type(entry["value"])
        return Value(s.id, value, Source.SEED if same else Source.OVERRIDE, render(s, old), drift)

    def write(self, s: Setting, value: str) -> None:
        # One key only: `defaults apply` would undo every hand change and write the config.local.toml opt-ins
        domain, key = split_key(s.key)
        literal = to_literal(s, value)
        path = target(domain, key)
        text = read_text(path)
        put(path, set_key(text, domain, key, literal))
        if masked(domain, key):  # the profile's value stays in effect, so there is nothing to read back or write
            return
        try:
            taken = self.read(s).value == render(s, parse_literal(literal))
        except SettingsError:
            put(path, text)
            raise
        if not taken:
            put(path, text)
            raise SettingsError(f"another config file (config.local.toml) declares {domain} {key} "
                                f"and outranks {path.name}, so change it there")
        defaults_write(domain, key, FLAGS[s.type], literal if s.type in ("bool", "int") else value)
        if self.read(s).drift:
            raise SettingsError(f"{domain} {key} did not take the value")
        if domain in RESTART:
            killall(RESTART[domain])

    def reset(self, s: Setting) -> None:
        domain, key = split_key(s.key)
        # The file that holds the value: the profile's when it declares the key, else as with no profile
        name = profile.target()
        mine = profile.override_path(name) if name else None
        path = mine if mine and declared(read_text(mine), domain, key) is not MISSING else shared_target(domain, key)
        if path != fragment_path():
            put(path, remove_key(read_text(path), domain, key))
            if masked(domain, key):
                return
            # The value the next layer down holds: the shared override file's under a profile's, else the fragment's
            old = declared(read_text(override_path()), domain, key) if path == mine else MISSING
            if old is MISSING:
                old = declared(read_text(), domain, key)
            if old is MISSING:
                print(f'mise never deletes a preference. Run: defaults delete {domain} "{key}"', file=sys.stderr)
                return
            value = render(s, old)
            literal = to_literal(s, value)
            defaults_write(domain, key, FLAGS[s.type], literal if s.type in ("bool", "int") else value)
            if domain in RESTART:
                killall(RESTART[domain])
            return
        head = head_text()
        if head is None:
            raise SettingsError("20-macos.toml is not in git HEAD, so there is no committed value to return to")
        old = declared(head, domain, key)
        if old is not MISSING:
            self.write(s, render(s, old))
            return
        fragment_path().write_text(remove_key(read_text(), domain, key))
        print(f'mise never deletes a preference. Run: defaults delete {domain} "{key}"', file=sys.stderr)
