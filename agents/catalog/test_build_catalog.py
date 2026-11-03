"""Checks the cleanup/status rules and change tracking. Run: python3 test_build_catalog.py"""
import json, os, tempfile
from pathlib import Path

# Set before the import: build_catalog reads it at module load (the path is never created)
os.environ["CLAUDE_CONFIG_DIR"] = config_dir = os.path.join(tempfile.gettempdir(), "catalog-test-claude")
import build_catalog as b

assert b.CLAUDE == Path(config_dir), b.CLAUDE


def plugin(name, **kw):
    return dict(name=name, key=f"{name}@m", enabled=True, cost=kw.pop("cost", 0),
                days_idle=kw.pop("days", 30), sessions_idle=kw.pop("sess", 30), **kw)


def item(name, source, kind="skill"):
    return dict(name=name, source=source, kind=kind, desc="d", enabled=True)


cur = {"group": [{"title": "G", "pick": ["p:a"], "items": ["p:a", "q:b", "r:c"]}],
       "duplicates": {"q:dup": "p:a"}, "retire": {"mine": "unused"},
       "plugin_status": {"s": {"status": "retire", "reason": "nope"}}}
plugins = [plugin("p", cost=5000), plugin("q", cost=5000), plugin("r", cost=5000, days=2, sess=1),
           plugin("t", cost=10), plugin("s"), plugin("hooks-only", cost=0)]
items = [item("p:a", "p"), item("q:b", "q"), item("q:dup", "q"), item("r:c", "r"), item("t:x", "t"),
         item("s:y", "s"), item("mine", "user")]
b.assess(plugins, items, cur)
st = {i["name"]: i["status"] for i in items}
ps = {p["name"]: p["status"] for p in plugins}

assert st == {"p:a": "recommended", "q:b": "alternative", "q:dup": "duplicate", "r:c": "alternative",
              "t:x": "ungrouped", "s:y": "retired", "mine": "retired"}, st
assert ps["p"] == "keep"            # has a ★ pick -> never flagged
assert ps["q"] == "review"          # unused, no pick, costly
assert ps["r"] == "watch"           # same, but used 2 days ago
assert ps["t"] == "keep"            # cheap and nothing redundant
assert ps["s"] == "retire"          # manual decision wins
assert ps["hooks-only"] == "keep"   # no items -> never flagged
assert json.loads(b.skill_overrides([dict(item("mine", "user"), status="retired")])) == {"skillOverrides": {"mine": "off"}}
assert b.skill_overrides([dict(item("q:b", "q"), status="retired")]) == ""  # plugin skills can't be overridden

# whole-plugin families are "grouped" (specialists, not alternatives); internal helpers get their own status
fam = [item("f:one", "f"), item("f:two", "f"), item("h:worker", "h", "agent")]
b.assess([plugin("f", cost=50), plugin("h")], fam,
         {"group": [{"title": "F", "plugins": ["f"]}], "internal": ["h:worker"]})
assert [i["status"] for i in fam] == ["grouped", "grouped", "internal"], [i["status"] for i in fam]

with tempfile.TemporaryDirectory() as d:
    f = Path(d) / "state.json"
    assert b.changes([item("a", "x")], f) == (None, [], [])          # first build: nothing to compare
    since, new, removed = b.changes([item("b", "x")], f)
    assert (new, removed) == (["skill:b"], ["skill:a"]), (new, removed)

# a curated MCP server that isn't registered here is reported but doesn't fail the build
probs = b.lint([], {}, {"mcp": {"ghost": {"desc": "x"}}, "notes": {"gone": {}}})
assert probs == ["curated entry for unknown item: gone", "mcp server not registered on this machine: ghost"], probs
assert not any(p.startswith(("group", "curated")) for p in probs[1:])
# a group that names that server only gets the per-machine note, not a fatal group error
probs = b.lint([], {}, {"mcp": {"ghost": {"desc": "x"}}, "group": [{"title": "G", "items": ["ghost", "nope"]}]})
assert probs == ["group 'G' names unknown item: nope", "mcp server not registered on this machine: ghost"], probs

# a curated claude.ai skill the signed-in account doesn't sync is one note, not a fatal error per mention
probs = b.lint([], {}, {"group": [{"title": "G", "items": ["anthropic-skills:pptx", "anthropic-skills:docs"]}],
                        "notes": {"anthropic-skills:docs": "n"}, "duplicates": {"anthropic-skills:pptx": "x:y"}})
assert probs == ["curated entry for unknown item: x:y",
                 "claude.ai skills not synced to this account: anthropic-skills:docs, anthropic-skills:pptx"], probs

pl = [dict(name="ai", key="pydantic-ai@m", version="1", enabled=True, cost=9)]
it = [dict(kind="skill", name="ai:x", source="ai", desc="d", path="/p", use="/ai:x", status="grouped", enabled=True)]
data = b.catalog_data(pl, it, {"stack": {"signals": {"pydantic-ai@m": {"deps": ["pydantic[-_]ai"]}}}})
assert data["plugins"][0]["key"] == "pydantic-ai@m"
assert data["items"][0]["path"] == "/p"
assert data["items"][0]["project"] is None
assert data["signals"]["pydantic-ai@m"]["deps"] == ["pydantic[-_]ai"]
assert b.catalog_data([], [], {})["signals"] == {}


assert b.named("added", []) == ""
assert b.named("removed", ["skill:p:one", "mcp:two"]) == "  removed: p:one, two"
assert b.named("added", [f"skill:{i}" for i in range(10)], limit=2) == "  added: 0, 1, +8 more"


def stack_cur(key, **sig):
    return {"stack": {"signals": {key: sig}}}


assert b.lint([], {}, stack_cur("nope@m"), pl) == ["curated stack signal for unknown plugin: nope@m"]
assert b.lint([], {}, stack_cur("ai"), pl) == ["curated stack signal for unknown plugin: ai"]
assert b.lint([], {}, stack_cur("pydantic-ai@m", paths=["("]), pl) == ["curated stack signal has invalid regex for pydantic-ai@m: ("]
by = {"ai:x": it[0]}
cur = {**stack_cur("pydantic-ai@m"), "group": [{"title": "G", "pick": ["ai:x"], "items": ["ai:x"]}]}
assert b.lint([], by, cur, pl) == ["curated stack signal on a plugin that owns a pick: pydantic-ai@m (ai:x)"]

# an empty CLAUDE_CONFIG_DIR means unset, like the shell's ${VAR:-}, not the cwd
import importlib
os.environ["CLAUDE_CONFIG_DIR"] = ""
assert importlib.reload(b).CLAUDE == Path.home() / ".claude", b.CLAUDE

print("ok")
