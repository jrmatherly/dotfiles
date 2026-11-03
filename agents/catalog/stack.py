#!/usr/bin/env python3
"""Select which installed Claude Code plugins a project needs. See bin/claude-stack.

Only plugins named in curated.toml's [stack.signals] can be turned off here. Evidence comes from tracked
paths, dependency manifests and this project's own session history (tool names only).
"""
import os, re, subprocess
from collections import Counter
from pathlib import Path

HOME = Path.home()
CATALOG = Path(os.environ.get("CLAUDE_STACK_CATALOG") or HOME / ".claude/catalog/catalog.json")
PROJECTS = Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude") / "projects"  # empty = unset, as in the shell
MANIFEST = re.compile(r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|go\.mod|Cargo\.toml|mix\.exs|[^/]*\.csproj|Gemfile)$")
MANIFEST_BYTES = 200_000
# The ':' skips a bare name that equals a plugin's, "input" skips tool definitions, and the
# </command-message> prefix skips text that only quotes a command
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
