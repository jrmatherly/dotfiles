#!/usr/bin/env python3
"""Select which installed Claude Code plugins a project needs. See bin/claude-stack.

Only plugins named in curated.toml's [stack.signals] can be turned off here. Evidence comes from tracked
paths, dependency manifests and this project's own session history (tool names only).
"""
import argparse, json, os, re, subprocess, sys, tempfile
from collections import Counter
from datetime import date
from pathlib import Path

HOME = Path.home()
CATALOG = Path(os.environ.get("CLAUDE_STACK_CATALOG") or HOME / ".claude/catalog/catalog.json")
PROJECTS = Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude") / "projects"  # empty = unset, as in the shell
MANIFEST = re.compile(r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|go\.mod|Cargo\.toml|mix\.exs|[^/]*\.csproj|Gemfile)$")
MANIFEST_BYTES = 200_000
# The ':' skips a bare name that equals a plugin's, "input" skips tool definitions, and the
# </command-message> prefix skips text that only quotes a command
SETTINGS, MANIFEST_FILE, RULE = ".claude/settings.local.json", ".claude/skill-stack.json", ".claude/rules/skill-stack.md"
USE = re.compile(rb'"name":"Skill","input":\{"skill":"([a-z0-9-]+):|"subagent_type":"([a-z0-9-]+):|"name":"mcp__plugin_([a-z0-9-]+)_[^"]*","input"|<\\?/command-message>(?:\\n|\s)*<command-name>/([a-z0-9-]+):')


class StackError(Exception):
    """An expected failure the CLI reports without a traceback."""


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    except OSError:
        return None
    return r.stdout.rstrip("\n") if r.returncode == 0 else None


def project_root(path):
    """The checkout Claude Code reads local settings from: a linked worktree inherits its main checkout's."""
    common = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common is None:
        raise StackError(f"not a git repository: {path}")
    common = Path(common)
    if common.name == ".git" and git(common.parent, "rev-parse", "--is-bare-repository") == "false":
        return common.parent.resolve()
    top = git(path, "rev-parse", "--show-toplevel")
    if not top:
        raise StackError(f"no work tree in this bare repository: {path}")
    return Path(top).resolve()


def tracked_files(root):
    out = git(root, "ls-files", "-z") or ""
    return [f for f in out.split("\0") if f and "node_modules/" not in f]


def manifest_text(root, files):
    chunks = []
    for f in files:
        p = Path(root) / f
        if not MANIFEST.search(f) or p.is_symlink():
            continue
        try:
            with open(p, "rb") as fh:
                chunks.append(fh.read(MANIFEST_BYTES).decode(errors="ignore"))
        except OSError:
            continue
    return "\n".join(chunks)


def slug(root):
    return re.sub(r"[^A-Za-z0-9]", "-", str(Path(root).resolve()))


def usage_counts(root, plugins, projects_dir):
    """Selectable plugins this project has really used, from tool names in its transcripts."""
    name_to_key = {p["name"]: p["key"] for p in plugins}
    base = slug(root)
    dirs = [Path(projects_dir) / base, *Path(projects_dir).glob(f"{base}--claude-worktrees-*")]
    counts = Counter()
    for d in dirs:
        for f in d.rglob("*.jsonl"):
            try:
                data = f.read_bytes()
            except OSError:
                continue
            for m in USE.finditer(data):
                key = name_to_key.get(next(g for g in m.groups() if g).decode())
                if key:
                    counts[key] += 1
    return counts


def reason(sig, files, text, used):
    for rx in sig.get("paths", []):
        hit = next((f for f in files if re.search(rx, f)), None)
        if hit:
            return f"path: {hit}"
    for rx in sig.get("deps", []):
        if re.search(rx, text):
            return f"dependency: {rx}"
    return f"used here {used} times" if used else None


def selectable(catalog):
    enabled = {p["key"] for p in catalog["plugins"] if p.get("enabled")}
    return {k: sig for k, sig in catalog["signals"].items() if k in enabled}


def decide(files, text, usage, catalog, keep=(), off=()):
    out = {}
    for key, sig in selectable(catalog).items():
        if key in off:
            out[key] = dict(state="off", why="turned off by hand")
        elif key in keep:
            out[key] = dict(state="keep", why="kept by hand")
        else:
            why = reason(sig, files, text, usage.get(key, 0))
            out[key] = dict(state="keep", why=why) if why else dict(state="off", why="no signal")
    return out


# ---------- local files ----------

def read_json(path):
    """A file we must not overwrite if we can't parse it. Missing is None."""
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as e:
        raise StackError(f"can't read {path}: {e}")
    if not isinstance(data, dict):
        raise StackError(f"can't read {path}: not a JSON object")
    return data


def write_text(path, text):
    """Atomic and private: a settings file can hold permission grants."""
    target = path.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        os.replace(tmp, target)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def write_settings(path, old, new):
    if new == (old or {}):
        return
    if new:
        write_text(path, json.dumps(new, indent=2) + "\n")
    else:
        path.unlink(missing_ok=True)


def write_manifest(path, manifest):
    write_text(path, json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def merge_settings(current, offs, owned):
    """Our false entries come and go. Anything else in enabledPlugins is the user's and wins."""
    plugins = dict(current.get("enabledPlugins") or {})
    for key in owned:
        if plugins.get(key) is False:
            del plugins[key]
    now_owned = set()
    for key in sorted(offs):
        if key not in plugins:
            plugins[key] = False
            now_owned.add(key)
    new = dict(current)
    if plugins:
        new["enabledPlugins"] = plugins
    else:
        new.pop("enabledPlugins", None)
    return new, now_owned


# ---------- commands ----------

def evidence(root, catalog, keep, off, projects_dir):
    files = tracked_files(root)
    usage = usage_counts(root, catalog["plugins"], projects_dir)
    return decide(files, manifest_text(root, files), usage, catalog, keep, off)


def sticky(old, catalog, keep, off):
    """Flags last until reset, and the newest flag on a key wins."""
    known = selectable(catalog)
    both = set(keep) & set(off)
    if both:
        raise StackError(f"both --keep and --off name: {', '.join(sorted(both))}")
    unknown = sorted(k for k in (*keep, *off) if k not in known)
    if unknown:
        raise StackError(f"not selectable (not in [stack.signals], or off at user scope): {', '.join(unknown)}")
    keeps = (set(old.get("keep", [])) - set(off) | set(keep)) & set(known)
    offs = (set(old.get("off", [])) - set(keep) | set(off)) & set(known)
    return sorted(keeps), sorted(offs)


def check_ignored(root):
    for rel in (SETTINGS, MANIFEST_FILE, RULE):
        if git(root, "check-ignore", "-q", rel) is None:
            raise StackError(f"{rel} is tracked or not ignored by git here, so refusing to write it")


def apply_stack(root, catalog, keep, off, picks=None, projects_dir=PROJECTS):
    root = Path(root)
    s_path, m_path, r_path = root / SETTINGS, root / MANIFEST_FILE, root / RULE
    old = read_json(m_path) or {}
    keeps, offs = sticky(old, catalog, keep, off)
    check_ignored(root)
    settings = read_json(s_path)
    prev_owned = set(old.get("owned", []))
    for key in keep:
        if (settings or {}).get("enabledPlugins", {}).get(key) is False and key not in prev_owned:
            raise StackError(f"{key} is set to false in {SETTINGS} by you, so --keep can't turn it on. Remove that entry first")
    decisions = evidence(root, catalog, keeps, offs, projects_dir)
    new_settings, owned = merge_settings(settings or {}, {k for k, d in decisions.items() if d["state"] == "off"}, prev_owned)
    manifest = dict(schema=1, generated=str(date.today()), decisions=decisions, owned=sorted(owned),
                    keep=keeps, off=offs, capabilities=old.get("capabilities", []))
    if {**old, "generated": None} == {**manifest, "generated": None}:
        manifest["generated"] = old["generated"]
    # This order means a crash can't leave false entries that no manifest owns
    write_manifest(m_path, {**manifest, "owned": sorted(prev_owned | owned)})
    write_settings(s_path, settings, new_settings)
    write_text(r_path, "Generated by claude-stack, do not edit.\n")
    write_manifest(m_path, manifest)
    return manifest


def reset_stack(root):
    root = Path(root)
    s_path, m_path, r_path = root / SETTINGS, root / MANIFEST_FILE, root / RULE
    manifest = read_json(m_path)
    if manifest is None:
        return
    settings = read_json(s_path)
    new_settings, _ = merge_settings(settings or {}, set(), set(manifest.get("owned", [])))
    write_settings(s_path, settings, new_settings)
    r_path.unlink(missing_ok=True)
    m_path.unlink(missing_ok=True)


def stack_status(root, catalog, projects_dir=PROJECTS):
    manifest = read_json(Path(root) / MANIFEST_FILE)
    if manifest is None:
        return "none"
    now = evidence(root, catalog, manifest.get("keep", []), manifest.get("off", []), projects_dir)
    was = manifest.get("decisions", {})
    changed = [f"{k} is now {now[k]['state']}" for k in sorted(now) if was.get(k, {}).get("state") != now[k]["state"]]
    return f"stale: {'; '.join(changed)}" if changed else "current"


def load_catalog():
    data = None
    try:
        data = json.loads(CATALOG.read_text())
    except (OSError, ValueError):
        pass
    if not isinstance(data, dict) or "plugins" not in data or "signals" not in data:
        raise StackError(f"no usable catalog at {CATALOG}: run claude-catalog first")
    return data


def scan(root, catalog, keep, off):
    old = read_json(Path(root) / MANIFEST_FILE) or {}
    keeps, offs = sticky(old, catalog, keep, off)
    decisions = evidence(root, catalog, keeps, offs, PROJECTS)
    for key, d in sorted(decisions.items(), key=lambda kv: (kv[1]["state"], kv[0])):
        print(f"{d['state']} {key}  {d['why']}")
    cost = {p["key"]: p.get("cost") or 0 for p in catalog["plugins"]}
    saved = sum(cost.get(k, 0) for k, d in decisions.items() if d["state"] == "off")
    print(f"estimated saving: {saved:,} tokens (catalog figures, which run high)")
    print(f"applied: {stack_status(root, catalog)}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="claude-stack")
    ap.add_argument("command", choices=["scan", "apply", "reset"])
    ap.add_argument("path", nargs="?", default=".")
    ap.add_argument("--keep", action="append", default=[], metavar="KEY")
    ap.add_argument("--off", action="append", default=[], metavar="KEY")
    ap.add_argument("--picks", metavar="FILE")
    a = ap.parse_args(argv)
    # The wrapper's `mise -C` moves us, so a relative path or --picks resolves from the caller's directory
    if os.environ.get("CLAUDE_STACK_CWD"):
        os.chdir(os.environ["CLAUDE_STACK_CWD"])
    try:
        root = project_root(Path(a.path))
        if a.command == "reset":
            reset_stack(root)
            print(f"reset {root}")
            return 0
        catalog = load_catalog()
        if a.command == "scan":
            scan(root, catalog, a.keep, a.off)
            return 0
        manifest = apply_stack(root, catalog, a.keep, a.off)
        print(f"applied to {root}: {len(manifest['owned'])} plugins off. A new session picks this up. `claude-stack reset` undoes it")
        return 0
    except StackError as e:
        print(f"claude-stack: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
