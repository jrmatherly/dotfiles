"""Checks the cleanup/status rules and change tracking. Run: python3 test_build_catalog.py"""
import json, tempfile
from pathlib import Path
import build_catalog as b


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

print("ok")
