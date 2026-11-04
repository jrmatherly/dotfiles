#!/usr/bin/env python3
"""Select which installed Claude Code plugins a project needs. See bin/claude-stack.

Only plugins named in curated.toml's [stack.signals] can be turned off here. Evidence comes from tracked
paths (files on disk outside git), dependency manifests and this project's own session history (tool names only).
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
MAX_WALK = 50_000
DIMENSIONS = ("architecture", "languages", "domain", "data", "integrations", "testing", "security", "ux", "deployment", "maintenance")
MAX_TOOLS, MAX_WHY, MAX_RULE_BYTES = 24, 120, 4000
SETTINGS, MANIFEST_FILE, RULE = ".claude/settings.local.json", ".claude/skill-stack.json", ".claude/rules/skill-stack.md"
PATHS = (SETTINGS, MANIFEST_FILE, RULE)
# The ':' skips a bare name that equals a plugin's, "input" skips tool definitions, and the
# </command-message> prefix skips text that only quotes a command
USE = re.compile(rb'"name":"Skill","input":\{"skill":"([a-z0-9-]+):|"subagent_type":"([a-z0-9-]+):|"name":"mcp__plugin_([a-z0-9-]+)_[^"]*","input"|<\\?/command-message>(?:\\n|\s)*<command-name>/([a-z0-9-]+):')


class StackError(Exception):
    """An expected failure the CLI reports without a traceback."""


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, errors="surrogateescape")
    except OSError:
        return None
    return r.stdout.rstrip("\n") if r.returncode == 0 else None


def project_root(path):
    """The checkout Claude Code reads local settings from: a linked worktree inherits its main checkout's.
    A folder outside git is its own root."""
    common = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common is None:
        p = Path(path).resolve()
        if not p.is_dir():
            raise StackError(f"not a directory: {path}")
        # a repo git can't read (corrupt, not owned by you, no git) must not lose the gitignore guard
        if any((d / ".git").exists() for d in (p, *p.parents)):
            raise StackError(f"git can't read the repository here: {path}")
        return p
    common = Path(common)
    own = git(path, "rev-parse", "--absolute-git-dir")
    linked = own is not None and Path(own).resolve() != common.resolve()
    if linked and common.name == ".git" and git(common.parent, "rev-parse", "--is-bare-repository") == "false":
        return common.parent.resolve()
    top = git(path, "rev-parse", "--show-toplevel")
    if not top:
        raise StackError(f"no work tree in this bare repository: {path}")
    return Path(top).resolve()


def tracked_files(root):
    out = git(root, "ls-files", "-z")
    if out is None:
        # outside git: files on disk, skipping hidden folders (.claude, .venv, .remember)
        def unreadable(e):
            # a skipped folder is missing evidence, which would turn plugins off
            raise StackError(f"can't read {e.filename}, so refusing rather than guessing")
        files = []
        for d, dirs, fs in os.walk(root, onerror=unreadable):
            dirs[:] = [x for x in dirs if not x.startswith(".") and x != "node_modules"]
            files += [str(Path(d, f).relative_to(root)) for f in fs]
            # refuse rather than truncate: missing evidence would turn plugins off ($HOME passed 1.2M files in 20s)
            if len(files) > MAX_WALK:
                raise StackError(f"more than {MAX_WALK} files outside git here, so run it in a project folder: {root}")
        return files
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
    """Missing is None. Unlike build_catalog.load_json, bad JSON raises: we must not overwrite what we can't parse."""
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


# ---------- picks and the rule ----------

def check_tool(use, catalog, decisions, root):
    """Why a tool can't be recorded for this project, or None."""
    item = next((i for i in catalog["items"] if i.get("use") == use), None)
    if item is None:
        return f"unknown tool: {use}"
    if item.get("status") in ("retired", "internal"):
        return f"{item['status']} tool: {use}"
    if not item.get("enabled", True):
        return f"disabled tool: {use}"
    if item.get("scope") == "project" and item.get("project") != str(root).replace(str(HOME), "~", 1):
        return f"tool from another project: {use}"
    key = next((p["key"] for p in catalog["plugins"] if p["name"] == item.get("source")), None)
    if decisions.get(key, {}).get("state") == "off":
        return f"tool in a plugin that is off here: {use}"
    return None


def validate_picks(picks, catalog, decisions, root):
    """The model chooses and this checks. The result becomes an auto-loaded rule, so it reports every problem at once."""
    caps = picks.get("capabilities") if isinstance(picks, dict) else None
    if not isinstance(caps, list) or not all(isinstance(c, dict) for c in caps):
        raise StackError("picks: capabilities must be a list of objects")
    problems, seen, total = [], set(), 0
    for c in caps:
        dim, status, tools, why = c.get("dimension"), c.get("status"), c.get("tools"), c.get("why")
        if dim not in DIMENSIONS:
            problems.append(f"unknown dimension: {dim}")
        elif dim in seen:
            problems.append(f"duplicate dimension: {dim}")
        seen.add(dim)
        if not isinstance(tools, list) or not all(isinstance(t, str) for t in tools) or not isinstance(why, str):
            problems.append(f"bad entry: {dim}")
            continue
        if status not in ("covered", "gap", "n/a"):
            problems.append(f"unknown status: {dim}")
        if status == "covered" and not tools:
            problems.append(f"covered needs a tool: {dim}")
        if status != "covered" and tools:
            problems.append(f"only covered lists tools: {dim}")
        if status == "gap" and not why:
            problems.append(f"gap needs a why: {dim}")
        if "\n" in why or len(why) > MAX_WHY:
            problems.append(f"why must be one line of at most {MAX_WHY} characters: {dim}")
        total += len(tools)
        problems += filter(None, (check_tool(t, catalog, decisions, root) for t in dict.fromkeys(tools)))
    if total > MAX_TOOLS:
        problems.append(f"more than {MAX_TOOLS} tools: {total}")
    problems += [f"missing dimension: {d}" for d in DIMENSIONS if d not in seen]
    if problems:
        raise StackError("picks: " + "; ".join(problems))
    return caps


def render_rule(capabilities, decisions, owned):
    """Validated names and our own wording only. `why` stays in the manifest: it isn't fit to become an instruction."""
    lines = ["Generated by claude-stack, do not edit. Run /project-stack to change it.", ""]
    chosen = [f"- {c['dimension']}: `{t}`" for c in capabilities if c["status"] == "covered" for t in c["tools"]]
    if chosen:
        lines += ["Tools chosen for this project:", "", *chosen, ""]
    gaps = [f"- {c['dimension']}" for c in capabilities if c["status"] == "gap"]
    if gaps:
        lines += ["No installed tool fits these:", "", *gaps, ""]
    off = [f"- `{k}`" for k in sorted(decisions) if decisions[k]["state"] == "off" and k in owned]
    if off:
        lines += ["Plugins turned off here. If you need one, run `claude-stack apply --keep <key>` and start a new session:", "", *off, ""]
    text = "\n".join(lines).rstrip() + "\n"
    size = len(text.encode())
    if size > MAX_RULE_BYTES:
        raise StackError(f"the rule would exceed {MAX_RULE_BYTES:,} bytes ({size}), so choose fewer tools")
    return text


# ---------- commands ----------

def evidence(root, catalog, keep, off, usage):
    files = tracked_files(root)
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
    if git(root, "rev-parse", "--git-dir") is None:
        # outside git nothing can commit these files, but a linked folder would send the writes elsewhere,
        # which git refuses inside a repo ("beyond a symbolic link")
        for d in (".claude", ".claude/rules"):
            if (Path(root) / d).is_symlink():
                raise StackError(f"{d} is a symlink here, so refusing to write through it")
        return
    for rel in PATHS:
        if git(root, "check-ignore", "-q", rel) is None:
            raise StackError(f"{rel} is tracked or not ignored by git here, so refusing to write it")


def apply_stack(root, catalog, keep, off, picks=None, projects_dir=PROJECTS):
    root = Path(root)
    s_path, m_path, r_path = (root / p for p in PATHS)
    old = read_json(m_path) or {}
    keeps, offs = sticky(old, catalog, keep, off)
    check_ignored(root)
    settings = read_json(s_path)
    prev_owned = set(old.get("owned", []))
    mine = (settings or {}).get("enabledPlugins") or {}
    for flag, keys, value in (("--keep", keep, False), ("--off", off, True)):
        for key in keys:
            if mine.get(key) is value and key not in prev_owned:
                raise StackError(f"{key} is set to {str(value).lower()} in {SETTINGS} by you, so {flag} can't change it. Remove that entry first")
    decisions = evidence(root, catalog, keeps, offs, usage_counts(root, catalog["plugins"], projects_dir))
    new_settings, owned = merge_settings(settings or {}, {k for k, d in decisions.items() if d["state"] == "off"}, prev_owned)
    # Picks are checked against what will really be on: a user's own false turns a kept plugin off too
    effective = {k: {**d, "state": "off"} if mine.get(k) is False else d for k, d in decisions.items()}
    if picks is not None:
        capabilities = validate_picks(picks, catalog, effective, root)
    else:
        # Earlier picks too: this apply may have turned off a plugin one of them needs, or an update renamed a tool
        earlier = old.get("capabilities", [])
        try:
            capabilities = validate_picks({"capabilities": earlier}, catalog, effective, root) if earlier else []
        except StackError as e:
            raise StackError(f"earlier {e}. Rerun /project-stack to choose again, or run `claude-stack reset` to start over")
    rule = render_rule(capabilities, decisions, owned)
    manifest = dict(schema=1, generated=str(date.today()), decisions=decisions, owned=sorted(owned),
                    keep=keeps, off=offs, capabilities=capabilities)
    if {**old, "generated": None} == {**manifest, "generated": None}:
        manifest["generated"] = old["generated"]
    # This order means a crash can't leave false entries that no manifest owns
    write_manifest(m_path, {**manifest, "owned": sorted(prev_owned | owned)})
    write_settings(s_path, settings, new_settings)
    write_text(r_path, rule)
    write_manifest(m_path, manifest)
    return manifest


def reset_stack(root):
    root = Path(root)
    s_path, m_path, r_path = (root / p for p in PATHS)
    manifest = read_json(m_path)
    if manifest is None:
        return
    settings = read_json(s_path)
    new_settings, _ = merge_settings(settings or {}, set(), set(manifest.get("owned", [])))
    write_settings(s_path, settings, new_settings)
    r_path.unlink(missing_ok=True)
    m_path.unlink(missing_ok=True)


def stack_status(root, catalog, projects_dir=PROJECTS, usage=None):
    manifest = read_json(Path(root) / MANIFEST_FILE)
    if manifest is None:
        return "none"
    if usage is None:
        usage = usage_counts(root, catalog["plugins"], projects_dir)
    now = evidence(root, catalog, manifest.get("keep", []), manifest.get("off", []), usage)
    was = manifest.get("decisions", {})
    changed = [f"{k} is now {now[k]['state']}" for k in sorted(now) if was.get(k, {}).get("state") != now[k]["state"]]
    # A catalog change or a lost settings file leaves the manifest claiming what is no longer true
    owned = manifest.get("owned", [])
    mine = (read_json(Path(root) / SETTINGS) or {}).get("enabledPlugins") or {}
    changed += [f"{k} is no longer selectable" for k in owned if k not in now]
    changed += [f"{k} is no longer off in {SETTINGS}" for k in owned if k in now and mine.get(k) is not False]
    return f"stale: {'; '.join(changed)}" if changed else "current"


def load_catalog():
    try:
        data = json.loads(CATALOG.read_text())
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict) or not {"plugins", "signals"} <= data.keys():
        raise StackError(f"no usable catalog at {CATALOG}: run claude-catalog first")
    return data


def scan(root, catalog, keep, off):
    old = read_json(Path(root) / MANIFEST_FILE) or {}
    keeps, offs = sticky(old, catalog, keep, off)
    usage = usage_counts(root, catalog["plugins"], PROJECTS)
    decisions = evidence(root, catalog, keeps, offs, usage)
    for key, d in sorted(decisions.items(), key=lambda kv: (kv[1]["state"], kv[0])):
        print(f"{d['state']} {key}  {d['why']}")
    cost = {p["key"]: p.get("cost") or 0 for p in catalog["plugins"]}
    saved = sum(cost.get(k, 0) for k, d in decisions.items() if d["state"] == "off")
    print(f"estimated saving: {saved:,} tokens (catalog figures, which run high)")
    # Zero on a repo with a long history means the transcript format moved, not that nothing was used
    print(f"history: {sum(usage.values()):,} plugin tool calls in this repo's sessions")
    print(f"applied: {stack_status(root, catalog, usage=usage)}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="claude-stack")
    ap.add_argument("command", choices=["scan", "apply", "reset"])
    ap.add_argument("path", nargs="?", default=".")
    ap.add_argument("--keep", action="append", default=[], metavar="KEY")
    ap.add_argument("--off", action="append", default=[], metavar="KEY")
    ap.add_argument("--picks", metavar="FILE")
    a = ap.parse_args(argv)
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
        picks = None
        if a.picks:
            picks = read_json(Path(a.picks))
            if picks is None:
                raise StackError(f"can't read {a.picks}: no such file")
        manifest = apply_stack(root, catalog, a.keep, a.off, picks)
        print(f"applied to {root}: {len(manifest['owned'])} plugins off. A new session picks this up. `claude-stack reset` undoes it")
        return 0
    except StackError as e:
        print(f"claude-stack: {e}", file=sys.stderr)
        return 2
    except (OSError, ValueError, TypeError, KeyError, re.error) as e:
        # Malformed settings, picks or catalog, or a write the filesystem refused. Nothing partial is left that reset can't undo
        print(f"claude-stack: {type(e).__name__}: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
