#!/usr/bin/env python3
"""Build a catalog of Claude Code skills, commands, subagents and MCP servers.

Scans ~/.claude (installed plugins, user skills, claude.ai-synced skills) and
~/.claude.json (MCP servers), merges hand-written notes from curated.toml, and
writes CATALOG.md (for AI assistants) and catalog.html (for people).

    python3 build_catalog.py [--out DIR] [--curated FILE]

Stdlib only. Re-run after installing/removing plugins.
"""
import argparse, json, re, shutil, subprocess, sys, time, tomllib
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

HOME = Path.home()
CLAUDE = HOME / ".claude"
HERE = Path(__file__).resolve().parent


# ---------- parsing ----------

def frontmatter(path):
    """Top-level scalar keys of a YAML frontmatter block (no PyYAML needed)."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    m = re.match(r"---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    out, lines, i = {}, m.group(1).splitlines(), 0
    while i < len(lines):
        km = re.match(r"([A-Za-z_][\w-]*):\s*(.*)$", lines[i])
        i += 1
        if not km:
            continue
        key, val = km.group(1), km.group(2).strip()
        cont = []
        while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
            cont.append(lines[i].strip())
            i += 1
        if val in ("|", ">", "|-", ">-", "|+", ">+", ""):
            val = " ".join(c for c in cont if c)
        else:
            val = " ".join([val] + [c for c in cont if c])
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            if val[0] == '"':
                try:
                    val = json.loads(val)
                except json.JSONDecodeError:
                    val = val[1:-1]
            else:
                val = val[1:-1].replace("''", "'")
        out[key] = val
    return out


def load_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return default


def as_list(v):
    return [] if v is None else v if isinstance(v, list) else [v]


def clean(s):
    return re.sub(r"\s+", " ", s or "").strip()


# ---------- scanning ----------

def scan_skills(dirs, prefix, source, kind="skill"):
    items = []
    for d in dirs:
        if not d.is_dir():
            continue
        files = [d / "SKILL.md"] if (d / "SKILL.md").exists() else sorted(d.glob("*/SKILL.md"))
        for f in files:
            fm = frontmatter(f)
            name = fm.get("name") or f.parent.name
            items.append(dict(kind=kind, name=f"{prefix}{name}", source=source,
                              desc=clean(fm.get("description")), path=str(f)))
    return items


def scan_md(paths, prefix, source, kind):
    """Commands/agents: each path is a dir of .md files or a single .md file."""
    items = []
    for p in paths:
        files = sorted(p.rglob("*.md")) if p.is_dir() else [p] if p.suffix == ".md" and p.exists() else []
        for f in files:
            if f.name.lower() in ("readme.md", "claude.md"):
                continue
            fm = frontmatter(f)
            name = fm.get("name") or f.stem
            items.append(dict(kind=kind, name=f"{prefix}{name}", source=source,
                              desc=clean(fm.get("description")), path=str(f)))
    return items


def mcp_entries(servers, source, scope):
    out = []
    for name, cfg in (servers or {}).items():
        target = cfg.get("url") or " ".join([cfg.get("command", "")] + cfg.get("args", []))
        out.append(dict(kind="mcp", name=name, source=source, scope=scope,
                        transport=cfg.get("type") or ("http" if cfg.get("url") else "stdio"),
                        target=clean(target), desc=""))
    return out


def marketplace_entries():
    entries = {}
    for mf in (CLAUDE / "plugins/marketplaces").glob("*/.claude-plugin/marketplace.json"):
        for p in (load_json(mf, {}) or {}).get("plugins", []):
            entries[f"{p.get('name')}@{mf.parent.parent.name}"] = p
    return entries


def scan_plugins():
    installed = (load_json(CLAUDE / "plugins/installed_plugins.json", {}) or {}).get("plugins", {})
    enabled = (load_json(CLAUDE / "settings.json", {}) or {}).get("enabledPlugins", {})
    market = marketplace_entries()
    plugins, items = [], []
    for key, installs in sorted(installed.items()):
        root = Path(installs[0]["installPath"])
        pname, mkt = key.split("@", 1)
        manifest = next((load_json(root / c) for c in (".claude-plugin/plugin.json", "plugin.json")
                         if (root / c).exists()), None)
        entry = market.get(key, {})
        spec = manifest if manifest is not None else entry  # strict:false plugins live in marketplace.json
        pname = spec.get("name") or pname  # the '/' prefix is the manifest name, not the install key
        prefix = f"{pname}:"
        on = enabled.get(key, True)
        before = len(items)

        skill_dirs = [root / "skills"] + [root / s for s in as_list(spec.get("skills"))]
        items += scan_skills(dict.fromkeys(skill_dirs), prefix, pname)
        cmd_paths = [root / "commands"] + [root / c for c in as_list(spec.get("commands"))]
        items += scan_md(dict.fromkeys(cmd_paths), prefix, pname, "command")
        agent_paths = [root / "agents"] + [root / a for a in as_list(spec.get("agents"))]
        items += scan_md(dict.fromkeys(agent_paths), prefix, pname, "agent")

        mcp = spec.get("mcpServers")
        if mcp is None and (root / ".mcp.json").exists():
            mcp = ".mcp.json"
        if isinstance(mcp, str):  # file path; both {"mcpServers": {...}} and flat {...} are valid
            d = load_json(root / mcp, {}) or {}
            mcp = d.get("mcpServers", d)
        items += mcp_entries(mcp, pname, "plugin")

        for it in items[before:]:
            it["enabled"] = on
        lsp = list((spec.get("lspServers") or {}).keys())
        plugins.append(dict(name=pname, key=key, marketplace=mkt, enabled=on,
                            version=installs[0].get("version", ""), lsp=lsp,
                            desc=clean((manifest or {}).get("description") or entry.get("description")),
                            count=len(items) - before))
    # dedupe (same file reachable via default dir + declared dir)
    seen, uniq = set(), []
    for it in items:
        k = (it["kind"], it["name"])
        if k not in seen:
            seen.add(k)
            uniq.append(it)
    return plugins, uniq


def scan_user():
    items = []
    user_dirs = [d for d in sorted((CLAUDE / "skills").iterdir()) if d.name != "synced"] \
        if (CLAUDE / "skills").is_dir() else []
    items += scan_skills(user_dirs, "", "user")
    items += scan_skills(sorted((CLAUDE / "skills/synced").glob("*")), "anthropic-skills:", "claude.ai (synced)")
    items += scan_md([CLAUDE / "commands"], "", "user", "command")
    items += scan_md([CLAUDE / "agents"], "", "user", "agent")
    cfg = load_json(HOME / ".claude.json", {}) or {}
    items += mcp_entries(cfg.get("mcpServers"), "user", "user")
    for proj, pc in (cfg.get("projects") or {}).items():
        for e in mcp_entries(pc.get("mcpServers"), "project", "project"):
            e["project"] = proj.replace(str(HOME), "~")
            items.append(e)
    for it in items:
        it.setdefault("enabled", True)
    return items


# ---------- merge curated ----------

def usage(it):
    """How an agent or user actually invokes the item."""
    n, k = it["name"], it["kind"]
    if k in ("skill", "command"):
        return n if n.startswith("/") else f"/{n}"
    if k == "agent":
        return f'Agent(subagent_type="{n}")'
    scope = it.get("scope")
    if scope == "plugin":
        return f"mcp__plugin_{it['source']}_{n}__*"
    if scope == "connector":
        return f"mcp__claude_ai_{n.replace(' ', '_')}__*"
    return f"mcp__{n}__*"


def merge(items, cur):
    by_name = {}
    for it in items:
        by_name.setdefault(it["name"], it)
    for b in cur.get("builtin", []):
        items.append(dict(kind=b.get("kind", "skill"), name=b["name"], source="built-in",
                          desc=b["desc"], enabled=True))
    for c in cur.get("connector", []):
        items.append(dict(kind="mcp", name=c["name"], source="claude.ai connector", scope="connector",
                          desc=c["desc"], enabled=True))
    for it in items:
        it["use"] = usage(it)
    by_name = {it["name"]: it for it in items}
    for name, o in cur.get("notes", {}).items():
        it = by_name.get(name)
        if it:
            it["note"] = o
    for name, m in cur.get("mcp", {}).items():
        it = by_name.get(name)
        if it and it["kind"] == "mcp":
            it["desc"] = m.get("desc", it["desc"])
            it["tools"] = m.get("tools", "")
    return by_name


def lint(items, by_name, cur):
    problems = []
    sources = {i["source"] for i in items}
    for g in cur.get("group", []):
        for n in g.get("items", []) + as_list(g.get("pick")):
            if n not in by_name:
                problems.append(f"group '{g['title']}' names unknown item: {n}")
        for pl in g.get("plugins", []):
            if pl not in sources:
                problems.append(f"group '{g['title']}' names unknown plugin: {pl}")
    for n in cur.get("internal", []):
        if n not in by_name:
            problems.append(f"curated internal entry for unknown item: {n}")
    for n in list(cur.get("notes", {})) + list(cur.get("mcp", {})) + list(cur.get("retire", {})) \
            + list(cur.get("duplicates", {})) + list(cur.get("duplicates", {}).values()):
        if n not in by_name:
            problems.append(f"curated entry for unknown item: {n}")
    for n in cur.get("plugin_status", {}):
        if n not in sources:
            problems.append(f"curated plugin_status for unknown plugin: {n}")
    for it in items:
        if not it["desc"] and not it.get("note"):
            problems.append(f"no description: {it['kind']} {it['name']}")
    return problems


# ---------- usage, cost, status ----------

CLEANUP_DEFAULTS = dict(unused_days=14, unused_sessions=10, cost_tokens=1000, overlap_ratio=0.8)
DAY_MS = 86_400_000


def attach_usage(plugins, items):
    """Read the counters Claude Code itself keeps in ~/.claude.json (pluginUsage/skillUsage).
    Undocumented keys: if they vanish, usage is just reported as unknown."""
    cfg = load_json(HOME / ".claude.json", {}) or {}
    pu, su = cfg.get("pluginUsage") or {}, cfg.get("skillUsage") or {}
    startups = cfg.get("numStartups")
    now = time.time() * 1000
    for p in plugins:
        u = pu.get(p["key"])
        if u:
            p["uses"] = u.get("usageCount", 0)
            p["days_idle"] = round((now - u["lastUsedAt"]) / DAY_MS, 1) if u.get("lastUsedAt") else None
            p["sessions_idle"] = startups - u["lastUsedNumStartups"] \
                if startups is not None and u.get("lastUsedNumStartups") is not None else None
    for it in items:
        u = su.get(it["name"].lstrip("/"))
        if u and it["kind"] in ("skill", "command"):
            it["uses"] = u.get("usageCount", 0)
            it["days_idle"] = round((now - u["lastUsedAt"]) / DAY_MS, 1) if u.get("lastUsedAt") else None
    return bool(pu or su)


def plugin_costs(plugins, items, cache_file):
    """Always-on context tokens per plugin from `claude plugin details`, cached per version.
    `details` misses agents listed file-by-file in plugin.json (it reports 0 for voltagent),
    so when it counts fewer components than we scanned, estimate the gap at ~4 chars/token."""
    exe = shutil.which("claude")
    cache = load_json(cache_file, {}) or {}

    def details(p):
        ck = f"{p['key']}@{p['version']}"
        if ck in cache:
            return ck, cache[ck]
        if not exe:
            return ck, None
        try:
            out = subprocess.run([exe, "plugin", "details", p["name"]], capture_output=True,
                                 text=True, timeout=90).stdout
        except (subprocess.SubprocessError, OSError):
            return ck, None
        m = re.search(r"Always-on:\s+(<\s*)?~?([\d,]+)", out)
        if not m:
            return ck, None
        n = lambda label: int((re.search(rf"{label} \((\d+)\)", out) or [0, 0])[1])
        return ck, dict(tokens=int(m.group(2).replace(",", "")), skills=n("Skills"), agents=n("Agents"))

    with ThreadPoolExecutor(8) as ex:
        got = dict(ex.map(details, plugins))
    cache.update({k: v for k, v in got.items() if v})
    for p in plugins:
        d = got.get(f"{p['key']}@{p['version']}")
        mine = [i for i in items if i["source"] == p["name"] and i["kind"] != "mcp"]
        if d is None:
            continue
        p["cost"] = d["tokens"]
        missing = len(mine) - (d["skills"] + d["agents"])
        if missing > 0:  # estimate the components `details` didn't see (the longest-described ones, conservatively)
            extra = sorted(mine, key=lambda i: -len(i["desc"]))[:missing]
            p["cost"] += sum((len(i["name"]) + len(i["desc"])) // 4 for i in extra)
            p["cost_estimated"] = True
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(cache, indent=1, sort_keys=True))


def assess(plugins, items, cur):
    """Item status (recommended/alternative/duplicate/ungrouped/retired) and plugin cleanup flags."""
    th = {**CLEANUP_DEFAULTS, **cur.get("cleanup", {})}
    groups = cur.get("group", [])
    picks = {p for g in groups for p in as_list(g.get("pick"))}
    in_pick_group = {n for g in groups if g.get("pick") for n in g.get("items", [])}
    grouped = {n for g in groups for n in g.get("items", [])} | picks
    family = {pl for g in groups for pl in g.get("plugins", [])}  # whole plugin = one specialist family, not alternatives
    internal = set(cur.get("internal", []))
    dups, retired_items = cur.get("duplicates", {}), cur.get("retire", {})
    pstat = cur.get("plugin_status", {})
    retired_plugins = {n for n, s in pstat.items() if s.get("status") == "retire"}

    for it in items:
        n = it["name"]
        if n in retired_items or it["source"] in retired_plugins:
            it["status"] = "retired"
            it["status_why"] = retired_items.get(n) or pstat[it["source"]].get("reason", "")
        elif n in picks:
            it["status"] = "recommended"
        elif n in dups:
            it["status"], it["status_why"] = "duplicate", f"duplicate of {dups[n]}"
        elif n in in_pick_group:
            it["status"] = "alternative"
        elif n in internal:
            it["status"], it["status_why"] = "internal", "run by its own plugin, not by you"
        elif n not in grouped and it["source"] not in family:
            it["status"] = "ungrouped"
        else:
            it["status"] = "grouped"

    for p in plugins:
        mine = [i for i in items if i["source"] == p["name"]]
        p["picks"] = sum(i["status"] == "recommended" for i in mine)
        p["items"] = len(mine)
        redundant = sum(i["status"] in ("alternative", "duplicate") for i in mine)
        p["overlap"] = round(redundant / len(mine), 2) if mine else 0
        manual = pstat.get(p["name"], {})
        why = []
        # never used => lastUsedAt is the install/enable time, which still ages correctly
        unused = (p.get("days_idle") is None or p["days_idle"] >= th["unused_days"]) and \
                 (p.get("sessions_idle") is None or p["sessions_idle"] >= th["unused_sessions"])
        costly = (p.get("cost") or 0) >= th["cost_tokens"]
        redundant_ok = p["overlap"] >= th["overlap_ratio"]
        if unused:
            why.append(f"unused {p.get('days_idle', '?')}d / {p.get('sessions_idle', '?')} sessions")
        if not p["picks"]:
            why.append("no recommended pick")
        if costly:
            why.append(f"{p['cost']:,} always-on tokens")
        if redundant_ok:
            why.append(f"{int(p['overlap'] * 100)}% alternatives/duplicates")
        eligible = mine and not p["picks"] and (costly or redundant_ok)  # hook/LSP-only plugins (no items) never flagged
        if manual.get("status"):
            p["status"], p["status_why"] = manual["status"], manual.get("reason", "")
        elif not p["enabled"]:
            p["status"], p["status_why"] = "disabled", ""
        elif eligible and unused:
            p["status"], p["status_why"] = "review", "; ".join(why)
        elif eligible:
            p["status"], p["status_why"] = "watch", "; ".join(why) + " — but used recently or too new to judge"
        else:
            p["status"], p["status_why"] = "keep", "; ".join(w for w in why if "pick" not in w) or ""
        p["disable_cmd"] = f"claude plugin disable {p['key']}"
    return th


def skill_overrides(items):
    """settings.json snippet for retired user/bundled skills (the only kind skillOverrides can turn off)."""
    off = {i["name"].lstrip("/"): "off" for i in items
           if i.get("status") == "retired" and i["kind"] == "skill" and i["source"] in ("user", "built-in")}
    return json.dumps({"skillOverrides": off}, indent=2) if off else ""


def changes(items, state_file):
    """Compare with the previous build; returns (since_date, new_names, removed_names)."""
    prev = load_json(state_file, None)
    now_keys = sorted(f"{i['kind']}:{i['name']}" for i in items)
    state_file.write_text(json.dumps(dict(built=str(date.today()), items=now_keys)))
    if not prev:
        return None, [], []
    old = set(prev.get("items", []))
    new = [k for k in now_keys if k not in old]
    removed = sorted(old - set(now_keys))
    for it in items:
        if f"{it['kind']}:{it['name']}" in new:
            it["new"] = True
    return prev.get("built"), new, removed


# ---------- rendering ----------

KIND_LABEL = {"skill": "Skills", "command": "Slash commands", "agent": "Subagents", "mcp": "MCP servers"}


def short(s, n):
    s = clean(s)
    return s if len(s) <= n else s[: n - 1].rsplit(" ", 1)[0] + "…"


def render_md(plugins, items, cur, by_name):
    L = [f"# Claude Code capability catalog",
         f"_Generated {date.today()} by build_catalog.py — do not edit by hand; edit curated.toml and re-run._", ""]
    L += [clean(cur.get("intro", "")), ""] if cur.get("intro") else []
    L += ["## How to invoke",
          "- **Skill / slash command** (`name` or `plugin:name`): user types `/name`; an agent calls its Skill tool with that name.",
          "- **Subagent** (`plugin:agent`): delegate via the Agent/Task tool with `subagent_type` set to the name. Not in the `/` menu.",
          "- **MCP server**: its tools appear as `mcp__<server>__<tool>` (plugin servers: `mcp__plugin_<plugin>_<server>__<tool>`).",
          "- Items marked *(disabled)* are installed but switched off in settings.json.", ""]
    counts = {k: sum(1 for i in items if i["kind"] == k) for k in KIND_LABEL}
    L += ["Totals: " + ", ".join(f"{v} {KIND_LABEL[k].lower()}" for k, v in counts.items())
          + f", {len(plugins)} plugins.", ""]
    retired = [i for i in items if i.get("status") == "retired"]
    if retired:
        L += ["## Avoid (retired — scheduled for removal)", ""]
        L += [f"- `{i['name']}` — {i.get('status_why') or 'retired'}" for i in retired] + [""]
    L += ["Item markers: ★ recommended · *(alt)* an alternative to the recommended pick · "
          "*(dup)* duplicate of another item · *(internal)* run by its own plugin, don't invoke directly · *(retired)* avoid.", ""]

    L += ["## Which to pick (task guide)",
          "★ = recommended pick when several tools overlap for that task (hand-chosen in curated.toml; no star = no clear default).", ""]
    for g in cur.get("group", []):
        L.append(f"### {g['title']}")
        if g.get("pick"):
            L.append(f"**Recommended (★):** " + ", ".join(f"`{p}`" for p in as_list(g["pick"])))
        if g.get("guide"):
            L.append(clean(g["guide"]))
        picks = set(as_list(g.get("pick")))
        for pl in g.get("plugins", []):
            n_items = sum(1 for i in items if i["source"] == pl)
            L.append(f"- all `{pl}:*` ({n_items} items) — see Plugin: {pl} below")
        for n in g.get("items", []):
            it = by_name.get(n)
            L.append(f"- `{n}`{' ★' if n in picks else ''} — {short(it.get('note') or it['desc'], 140) if it else '(not installed)'}")
        L.append("")

    L += ["## MCP servers", ""]
    for it in sorted((i for i in items if i["kind"] == "mcp"), key=lambda i: (i["scope"], i["name"])):
        where = it.get("project") or it["source"]
        dis = " *(disabled)*" if not it["enabled"] else ""
        L.append(f"- `{it['name']}` [{it['scope']}: {where}]{dis} — {it['desc'] or it.get('target', '')} (tools: `{it['use']}`)")
        if it.get("tools"):
            L.append(f"  - tools: {clean(it['tools'])}")
    L.append("")

    L += ["## Plugins: context cost, usage, cleanup status", "",
          "Cost = always-on tokens added to every session while enabled (from `claude plugin details`; ~ = partly estimated). "
          "Status: keep · watch (meets cost/overlap rules but used recently or too new) · review (cleanup candidate) · retire · disabled.", "",
          "| plugin | status | cost | uses | idle | picks | items | why |", "|---|---|---|---|---|---|---|---|"]
    for p in sorted(plugins, key=lambda p: -(p.get("cost") or 0)):
        cost = f"{'~' if p.get('cost_estimated') else ''}{p['cost']:,}" if p.get("cost") is not None else "?"
        idle = f"{p['days_idle']}d" if p.get("days_idle") is not None else "?"
        L.append(f"| {p['name']} | {p['status']} | {cost} | {p.get('uses', '?')} | {idle} | {p['picks']} | {p['items']} | {p.get('status_why', '')} |")
    L.append("")

    tag = {"alternative": " *(alt)*", "duplicate": " *(dup)*", "retired": " *(retired)*", "recommended": " ★",
           "internal": " *(internal)*"}

    def section(title, rows, sub=()):
        L.append(f"## {title}")
        L.extend(sub)
        L.append("")
        for it in rows:
            dis = " *(disabled)*" if not it["enabled"] else ""
            note = f" **Note:** {clean(it['note'])}" if it.get("note") else ""
            L.append(f"- `{it['name']}` ({it['kind']}){tag.get(it.get('status'), '')}{dis} — "
                     f"{short(it['desc'], 320) or '(no description)'}{note}")
        L.append("")

    for src in ["built-in", "user", "claude.ai (synced)"]:
        rows = [i for i in items if i["source"] == src and i["kind"] != "mcp"]
        if rows:
            section(f"Source: {src}", rows)
    for p in plugins:
        rows = [i for i in items if i["source"] == p["name"] and i["kind"] != "mcp"]
        if rows or p["lsp"]:
            sub = [f"_{p['desc']}_"] if p["desc"] else []
            if p["lsp"]:
                sub.append(f"LSP servers: {', '.join(p['lsp'])} (used automatically for code intelligence; nothing to invoke)")
            section(f"Plugin: {p['name']} ({p['marketplace']}{', disabled' if not p['enabled'] else ''})", rows, sub)
    return "\n".join(L)


def render_lite(plugins, items, cur, by_name):
    """Small enough to paste into another assistant or load up front: task guide + defaults only."""
    L = ["# Claude Code tools — quick guide",
         f"_Generated {date.today()}. Full list: CATALOG.md. Invoke skills/commands as `/name`; "
         "subagents via the Agent tool (`subagent_type`); MCP tools appear as `mcp__<server>__<tool>`._", ""]
    for g in cur.get("group", []):
        picks = as_list(g.get("pick"))
        rest = [n for n in g.get("items", []) if n not in picks and by_name.get(n, {}).get("status") != "retired"] \
            + [f"{pl}:* (all)" for pl in g.get("plugins", [])]
        L.append(f"**{g['title']}** — " + (", ".join(f"`{p}`" for p in picks) + ". " if picks else "")
                 + (clean(g.get("guide", "")) + " " if g.get("guide") else "")
                 + (f"Also: {', '.join(rest)}." if rest else ""))
    mcps = [i for i in items if i["kind"] == "mcp" and i["enabled"]]
    L += ["", "**MCP servers:** " + "; ".join(f"`{i['name']}` ({short(i['desc'], 70)})" for i in mcps)]
    retired = [i["name"] for i in items if i.get("status") == "retired"]
    if retired:
        L += ["", "**Avoid (retired):** " + ", ".join(retired)]
    return "\n".join(L) + "\n"


def render_html(plugins, items, cur, extra):
    data = json.dumps(dict(items=[{k: v for k, v in i.items() if k != "path"} for i in items],
                           groups=cur.get("group", []), plugins=plugins, built=str(date.today()), **extra))
    tpl = (HERE / "catalog_template.html").read_text()
    return tpl.replace("/*DATA*/null", data.replace("</", "<\\/"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=HERE)
    ap.add_argument("--curated", type=Path, default=HERE / "curated.toml")
    a = ap.parse_args()
    cur = tomllib.loads(a.curated.read_text()) if a.curated.exists() else {}
    plugins, items = scan_plugins()
    items += scan_user()
    by_name = merge(items, cur)
    items = list({(i["kind"], i["name"]): i for i in items}.values())
    a.out.mkdir(parents=True, exist_ok=True)
    has_usage = attach_usage(plugins, items)
    plugin_costs(plugins, items, a.out / ".cache" / "plugin-costs.json")
    th = assess(plugins, items, cur)
    since, new, removed = changes(items, a.out / ".cache" / "last-build.json")
    extra = dict(thresholds=th, has_usage=has_usage, since=since, new=new, removed=removed,
                 overrides=skill_overrides(items),
                 total_cost=sum(p.get("cost") or 0 for p in plugins if p["enabled"]))
    (a.out / "CATALOG.md").write_text(render_md(plugins, items, cur, by_name))
    (a.out / "CATALOG-lite.md").write_text(render_lite(plugins, items, cur, by_name))
    (a.out / "catalog.html").write_text(render_html(plugins, items, cur, extra))
    probs = lint(items, by_name, cur)
    kinds = {k: sum(1 for i in items if i["kind"] == k) for k in KIND_LABEL}
    flags = {s: sum(p["status"] == s for p in plugins) for s in ("review", "watch", "retire")}
    print(f"wrote {a.out}/CATALOG.md, CATALOG-lite.md, catalog.html — {kinds}, {len(plugins)} plugins, "
          f"{extra['total_cost']:,} always-on tokens, plugin flags {flags}"
          + (f", since {since}: +{len(new)} -{len(removed)}" if since else ""))
    for p in probs:
        print("  lint:", p, file=sys.stderr)
    return 1 if any(p.startswith(("group", "curated")) for p in probs) else 0


if __name__ == "__main__":
    sys.exit(main())
